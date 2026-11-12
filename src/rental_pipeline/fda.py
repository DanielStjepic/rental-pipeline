import requests, logging, time
from typing import Any

FDA_API_URL = 'https://api.fda.gov/drug/enforcement.json'

logger = logging.getLogger(__name__)

def fetch_page(limit: int, skip: int) -> list[dict[str, Any]]:
    payload = {'limit': limit, 'skip': skip}
    r = requests.get(FDA_API_URL, params=payload, timeout=5)
    r.raise_for_status()
    data = r.json()
    return data['results']


def fetch_all_pages(limit: int, max_pages: int = 5) -> list[dict[str, Any]]:
    skip = 0
    records: list[dict[str, Any]] = []
    for _ in range(max_pages):
        try:
            page = fetch_page(limit, skip)
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






def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s %(name)s | %(message)s")
    limit = 5
    records = fetch_all_pages(limit)
    logger.info("Total: %s, rcl_no: %s", len(records), records[0]['recall_number'])

    
    


if __name__ == "__main__":
    main()

  
