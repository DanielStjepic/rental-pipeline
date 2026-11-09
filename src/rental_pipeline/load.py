from psycopg import sql
from pathlib import Path
from rental_pipeline.db import get_connection
from psycopg import Connection
from psycopg.rows import TupleRow




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
        print(PROJECT_ROOT)
        cur.execute(query)
        

def main():
    with get_connection() as conn:
        bef = count_rows(conn, 'star.fact_rental')
        run_merge(conn)
    
        aft = count_rows(conn, 'star.fact_rental')
        print(f'Diff: {aft-bef} ')
        print(f'Before: {bef}, after: {aft}')
    
    


if __name__ == "__main__":
    main()

  


            
