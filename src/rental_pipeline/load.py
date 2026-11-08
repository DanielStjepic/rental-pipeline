from psycopg import sql
from pathlib import Path
from rental_pipeline.db import get_connection



PROJECT_ROOT = Path(__file__).resolve().parents[2] / 'sql' / '02_merge_fact_rental.sql'
def read_sql(path):
    with open(path, encoding='utf-8') as f:
        return f.read()

def count_rows(conn, table):
    with conn.cursor() as cur:
        query = sql.SQL("Select count(*) from {}").format(sql.Identifier(*table.split('.')))
        cur.execute(query)
        row = cur.fetchone()
        return row[0]


def run_merge(conn):
    with conn.cursor() as cur:
        query = read_sql(PROJECT_ROOT)
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

  


            
