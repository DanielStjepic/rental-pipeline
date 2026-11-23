from rental_pipeline.db import get_connection
from rental_pipeline.load import (
    PROJECT_ROOT,
    count_rows,
    read_sql,
    run_rental_merge,
)

BUILD_FILE_PATH = PROJECT_ROOT / 'sql' / 'rental' / '01_build_warehouse.sql' 
def test_database_integration(monkeypatch):
    
    monkeypatch.setenv("PG_DBNAME", "pagila_test")
    with get_connection() as conn:
        source_count = count_rows(conn, 'public.rental')
        with conn.cursor() as cur:
            query = read_sql(BUILD_FILE_PATH)
            cur.execute(query)
         
    with get_connection() as conn:
        rentals_count = count_rows(conn,'star.fact_rental')
    assert rentals_count == source_count


def helper_fresh_database_build_insert(monkeypatch):
    monkeypatch.setenv("PG_DBNAME", "pagila_test")
    with get_connection() as conn, conn.cursor() as cur:
        query = read_sql(BUILD_FILE_PATH)
        cur.execute(query)


    
   

def test_merging_staging_to_fact_rental(monkeypatch):
    records = [(900001, '2026-11-20 09:15',120, 15,  None, 1, '2026-11-20 09:15'),
            (900002, '2026-11-20 10:30',245, 88, '2026-11-21 18:00', 2, '2026-11-21 18:00'),
            (900003, '2026-11-20 11:00',310, 42, None, 1, '2026-11-20 11:00'),
            (900003, '2026-11-20 11:00',310, 42, '2026-11-22 14:00', 1, '2026-11-20 14:00')]
    helper_fresh_database_build_insert(monkeypatch)

    with get_connection() as conn:
        with conn.cursor() as cur:
            with cur.copy('COPY star.st_rental (rental_id, rental_date, inventory_id, customer_id, return_date,staff_id, last_update) from STDIN') as copy:
                for record in records:
                    copy.write_row(record)

    with get_connection() as conn:
        before = count_rows(conn, 'star.fact_rental')
    run_rental_merge()
    with get_connection() as conn:
        after1 = count_rows(conn, 'star.fact_rental')
    run_rental_merge()
    with get_connection() as conn:
        after2 = count_rows(conn, 'star.fact_rental')

    with get_connection() as conn, conn.cursor() as cur:

        query = 'SELECT return_date_key from star.fact_rental where rental_id = 900003'
        cur.execute(query)
        dedup = cur.fetchall()

    distincts = [x[0] for x in records]
    assert after1 == before + len(set(distincts))

    assert after2 - after1 == 0

    assert len(dedup) == 1

    assert dedup[0][0] == 20261122

    