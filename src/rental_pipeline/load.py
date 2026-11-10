from psycopg import sql
from pathlib import Path
from rental_pipeline.db import get_connection
from psycopg import Connection
from psycopg.rows import TupleRow
from psycopg import OperationalError
import time
from collections.abc import Callable



PROJECT_ROOT = Path(__file__).resolve().parents[2]
MERGE_FILE_PATH = PROJECT_ROOT / 'sql' / '02_merge_fact_rental.sql'
def read_sql(path: Path | str) -> str:
    with open(path, encoding='utf-8') as f:
        return f.read()

def count_rows(conn: Connection[TupleRow], table: str) -> int:
    with conn.cursor() as cur:
        query = sql.SQL("Select count(*) from {}").format(sql.Identifier(*table.split('.')))
        cur.execute(query)
        row = cur.fetchone()
        if row is None:
            raise RuntimeError(f"Count(*) from {table} returned an unexpected value")
        return row[0]




def run_merge(conn: Connection[TupleRow]) -> None:
    with conn.cursor() as cur:
        query = read_sql(MERGE_FILE_PATH)
        cur.execute(query)


def verify_merge(conn: Connection[TupleRow]) -> None:
    with conn.cursor() as cur:
        query = sql.SQL("Select count(distinct sr.rental_id) from star.st_rental sr " \
        "left join star.fact_rental fr on fr.rental_id = sr.rental_id where fr.rental_id is null")
        result = cur.execute(query)
        row = result.fetchone()
        if row is None:
            raise RuntimeError(f"Verification query returned no row")
        if row[0] != 0:
            raise RuntimeError(f"There are missing rentals in star.fact_rental table: {row[0]}")

def run_rental_merge() -> None:
    with get_connection() as conn:
        bef = count_rows(conn, 'star.fact_rental')
        run_merge(conn)
        verify_merge(conn)
        aft = count_rows(conn, 'star.fact_rental')
        print(f'Diff: {aft-bef} ')
        print(f'Before: {bef}, after: {aft}')

def run_with_retry(func: Callable[[],None]) -> None:
    max_retries = 3
    for i in range(max_retries):
        try:
            func()
            break
        except OperationalError as err:
            if i != max_retries - 1:
                print(f"Attempt no.{i + 1} failed {err}")
                time.sleep(pow(2,i))
            else:
                print(f"Attempt no.{i + 1} failed {err}")
                raise




def main() -> None:
    run_with_retry(run_rental_merge)
    
    
    


if __name__ == "__main__":
    main()

  


            
