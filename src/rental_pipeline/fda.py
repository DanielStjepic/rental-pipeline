import functools
import logging
import time
from typing import Any

import requests
from psycopg import Connection
from psycopg.rows import TupleRow
from psycopg.types.json import Jsonb

from rental_pipeline.db import get_connection
from rental_pipeline.retry import run_with_retry

FDA_API_URL = 'https://api.fda.gov/drug/enforcement.json'

logger = logging.getLogger(__name__)

class TransientApiException(Exception):
    """The API had a temporary problem (429 or 5xx); safe to retry."""


def fetch_page(limit: int, skip: int) -> list[dict[str, Any]]:
    payload = {'limit': limit, 'skip': skip}
    r = requests.get(FDA_API_URL, params=payload, timeout=5)
    if r.status_code == 429 or (r.status_code > 499 and r.status_code < 600):
        raise TransientApiException(r.status_code)   
    r.raise_for_status()
    data = r.json()
    return data['results']


def fetch_all_pages(limit: int, max_pages: int = 5) -> list[dict[str, Any]]:
    skip = 0
    records: list[dict[str, Any]] = []
    for _ in range(max_pages):
        try:
            page = run_with_retry(functools.partial(fetch_page, limit, skip), retry_on=(TransientApiException, requests.Timeout, requests.ConnectionError))
            records.extend(page)
        except requests.HTTPError as err:
            if err.response is None:    
                raise
            if err.response.status_code == 404:
                if len(records) == 0:
                    raise
                else:
                    break
            else:
                raise
        logger.info("Skip: %s, total on page: %s", skip,len(page))            
        skip += limit
        if len(page) < limit:
            break
        time.sleep(0.4)
    return records


def insert_fda(records: list[dict[str, Any]], conn: Connection[TupleRow]) -> int:
    inserted = 0
    with conn.cursor() as curr:

        with curr.copy("COPY raw.fda_drug_enforcement (raw_data, recall_number) from STDIN") as copy:
            for record in records:
                copy.write_row( (Jsonb(record), record["recall_number"]))
                inserted += 1
    return inserted





def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s %(name)s | %(message)s")
    limit = 5
    records = fetch_all_pages(limit)
    logger.info("Fetched records: %s", len(records))
    with get_connection() as conn:       
        rows = insert_fda(records, conn)
    logger.info("Inserted rows: %s", rows)
    
    


if __name__ == "__main__":
    main()

  
