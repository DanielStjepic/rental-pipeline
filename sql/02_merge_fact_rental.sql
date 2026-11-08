-- =====================================================================
-- 02_merge_fact_rental.sql
-- Recurring incremental load: star.st_rental (staging) -> star.fact_rental
--
-- 1. Deduplicate the staging batch (newest version of each rental wins)
-- 2. Translate source IDs to warehouse keys (Type 2: version at the time)
-- 3. MERGE: update changed rentals, insert new ones, skip unchanged
--
-- Idempotent: rerunning the same batch changes 0 rows.
-- =====================================================================

BEGIN;

WITH latest AS (
    -- Step 1: one row per rental. Ties on last_update are broken by
    -- arrival order (stg_row_id), so every run picks the same row.
    SELECT *
    FROM (
        SELECT sr.*,
               row_number() OVER (PARTITION BY sr.rental_id
                                  ORDER BY sr.last_update DESC, sr.stg_row_id DESC) AS rnk
        FROM star.st_rental sr
    ) x
    WHERE rnk = 1
)
MERGE INTO star.fact_rental t
USING (
    -- Step 2: source IDs -> warehouse keys
    SELECT
        r.rental_id,
        dc.customer_key,
        ds.staff_key,
        dd.date_id AS rental_date_key,
        coalesce(to_char(r.return_date, 'YYYYMMDD')::int, -1) AS return_date_key,
        ds2.store_key,
        df.film_key,
        (r.return_date::date - r.rental_date::date)::int AS rental_duration_days
    FROM latest r
    LEFT JOIN star.dim_customer dc
           ON dc.customer_id = r.customer_id
          AND r.rental_date::date BETWEEN dc.valid_from AND dc.valid_to
    LEFT JOIN star.dim_staff ds
           ON ds.staff_id = r.staff_id
          AND r.rental_date::date BETWEEN ds.valid_from AND ds.valid_to
    LEFT JOIN star.dim_date dd
           ON dd.date_id = to_char(r.rental_date, 'YYYYMMDD')::int
    LEFT JOIN public.inventory i
           ON i.inventory_id = r.inventory_id
    LEFT JOIN star.dim_film df
           ON df.film_id = i.film_id
    LEFT JOIN star.dim_store ds2
           ON ds2.store_id = i.store_id
) s
ON s.rental_id = t.rental_id
-- Step 3a: existing rental that changed (e.g. it was returned)
WHEN MATCHED AND (
        s.return_date_key      IS DISTINCT FROM t.return_date_key
     OR s.rental_duration_days IS DISTINCT FROM t.rental_duration_days
) THEN
    UPDATE SET return_date_key      = s.return_date_key,
               rental_duration_days = s.rental_duration_days
-- Step 3b: new rental
WHEN NOT MATCHED THEN
    INSERT (rental_id, customer_key, staff_key, rental_date_key,
            return_date_key, store_key, film_key, rental_duration_days)
    VALUES (s.rental_id, s.customer_key, s.staff_key, s.rental_date_key,
            s.return_date_key, s.store_key, s.film_key, s.rental_duration_days);

-- Optional: clear the batch once it is loaded. Same transaction, so if the
-- MERGE fails nothing is cleared and the batch can simply be rerun.
-- TRUNCATE star.st_rental;

COMMIT;
