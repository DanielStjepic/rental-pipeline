-- =====================================================================
-- 01_build_warehouse.sql
-- Rebuilds the Pagila star schema from scratch. Safe to rerun:
-- the schema is dropped and recreated on every run.
-- Run order: this file first, then 02_merge_fact_rental.sql for
-- recurring incremental loads.
-- =====================================================================

drop schema if exists star cascade;

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE SCHEMA star;
ALTER SCHEMA star OWNER TO postgres;

SET default_tablespace = '';
SET default_table_access_method = heap;


-- =====================================================================
-- 1. TABLES
-- =====================================================================

CREATE TABLE star.dim_actor (
    actor_key integer NOT NULL,
    actor_id integer NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    full_name text GENERATED ALWAYS AS (((first_name || ' '::text) || last_name)) STORED
);
ALTER TABLE star.dim_actor OWNER TO postgres;

CREATE SEQUENCE star.dim_actor_actor_key_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE star.dim_actor_actor_key_seq OWNER TO postgres;
ALTER SEQUENCE star.dim_actor_actor_key_seq OWNED BY star.dim_actor.actor_key;

-- CHANGED: weighting_factor was numeric(6,5), which caused rounding drift
-- (weights per film summed to 0.99999 / 1.00002). Unbounded numeric keeps
-- full precision so allocated revenue reconciles.
CREATE TABLE star.dim_bridge_film_actor (
    film_key integer NOT NULL,
    actor_key integer NOT NULL,
    weighting_factor numeric NOT NULL
);
ALTER TABLE star.dim_bridge_film_actor OWNER TO postgres;

CREATE TABLE star.dim_customer (
    customer_key integer NOT NULL,
    customer_id integer NOT NULL,
    registered_store_id integer NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    full_name text GENERATED ALWAYS AS (((first_name || ' '::text) || last_name)) STORED,
    email text,
    address text NOT NULL,
    district text,
    city text NOT NULL,
    postal text,
    phone text,
    country text NOT NULL,
    activebool boolean NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    is_current boolean NOT NULL
);
ALTER TABLE star.dim_customer OWNER TO postgres;

CREATE SEQUENCE star.dim_customer_customer_key_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE star.dim_customer_customer_key_seq OWNER TO postgres;
ALTER SEQUENCE star.dim_customer_customer_key_seq OWNED BY star.dim_customer.customer_key;

CREATE TABLE star.dim_date (
    date_id integer NOT NULL,
    year integer NOT NULL,
    quarter integer NOT NULL,
    month integer NOT NULL,
    month_name text NOT NULL,
    day integer NOT NULL,
    day_of_week integer NOT NULL,
    day_name text NOT NULL,
    is_weekend boolean NOT NULL,
    week_of_year integer NOT NULL,
    full_date date NOT NULL
);
ALTER TABLE star.dim_date OWNER TO postgres;

CREATE TABLE star.dim_film (
    film_key integer NOT NULL,
    film_id integer NOT NULL,
    title text NOT NULL,
    description text,
    release_year integer,
    language text,
    original_language text NOT NULL,
    rental_duration smallint NOT NULL,
    rental_rate numeric(4,2) NOT NULL,
    length integer,
    replacement_cost numeric(5,2),
    rental_duration_band text NOT NULL,
    rental_rate_band text NOT NULL,
    length_band text NOT NULL,
    replacement_cost_band text NOT NULL,
    rating text NOT NULL,
    has_trailers boolean NOT NULL,
    has_commentaries boolean NOT NULL,
    has_deleted_scenes boolean NOT NULL,
    has_behind_scenes boolean NOT NULL,
    category text NOT NULL
);
ALTER TABLE star.dim_film OWNER TO postgres;

CREATE SEQUENCE star.dim_film_film_key_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE star.dim_film_film_key_seq OWNER TO postgres;
ALTER SEQUENCE star.dim_film_film_key_seq OWNED BY star.dim_film.film_key;

CREATE TABLE star.dim_staff (
    staff_key integer NOT NULL,
    staff_id integer NOT NULL,
    works_at_store_id integer NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    address text NOT NULL,
    district text,
    postal text,
    phone text,
    city text NOT NULL,
    country text NOT NULL,
    email text,
    active boolean NOT NULL,
    username text NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    is_current boolean NOT NULL
);
ALTER TABLE star.dim_staff OWNER TO postgres;

CREATE SEQUENCE star.dim_staff_staff_key_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE star.dim_staff_staff_key_seq OWNER TO postgres;
ALTER SEQUENCE star.dim_staff_staff_key_seq OWNED BY star.dim_staff.staff_key;

CREATE TABLE star.dim_store (
    store_key integer NOT NULL,
    store_id integer NOT NULL,
    manager_name text,
    manager_surname text,
    manager_full_name text GENERATED ALWAYS AS (((manager_name || ' '::text) || manager_surname)) STORED,
    address text NOT NULL,
    district text,
    postal_code text,
    phone text,
    city text,
    country text
);
ALTER TABLE star.dim_store OWNER TO postgres;

CREATE SEQUENCE star.dim_store_store_key_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER SEQUENCE star.dim_store_store_key_seq OWNER TO postgres;
ALTER SEQUENCE star.dim_store_store_key_seq OWNED BY star.dim_store.store_key;

CREATE TABLE star.fact_payment (
    payment_id integer NOT NULL,
    payment_date_key integer NOT NULL,
    customer_key integer NOT NULL,
    staff_key integer NOT NULL,
    rental_id integer,
    amount numeric(5,2) NOT NULL
);
ALTER TABLE star.fact_payment OWNER TO postgres;

CREATE TABLE star.fact_rental (
    rental_id integer NOT NULL,
    customer_key integer NOT NULL,
    staff_key integer NOT NULL,
    rental_date_key integer NOT NULL,
    return_date_key integer NOT NULL,
    store_key integer NOT NULL,
    film_key integer NOT NULL,
    rental_duration_days integer
);
ALTER TABLE star.fact_rental OWNER TO postgres;

-- NEW: staging table for incremental loads (see 02_merge_fact_rental.sql).
-- Same columns as public.rental, no constraints, so messy batches with
-- duplicates can land here. stg_row_id records arrival order and is the
-- tiebreaker when two versions of a rental share the same last_update.
CREATE TABLE star.st_rental AS
SELECT * FROM public.rental WHERE false;
ALTER TABLE star.st_rental
    ADD COLUMN stg_row_id bigint GENERATED ALWAYS AS IDENTITY;
ALTER TABLE star.st_rental OWNER TO postgres;


-- =====================================================================
-- 2. DEFAULTS AND CONSTRAINTS
-- =====================================================================

ALTER TABLE ONLY star.dim_actor    ALTER COLUMN actor_key    SET DEFAULT nextval('star.dim_actor_actor_key_seq'::regclass);
ALTER TABLE ONLY star.dim_customer ALTER COLUMN customer_key SET DEFAULT nextval('star.dim_customer_customer_key_seq'::regclass);
ALTER TABLE ONLY star.dim_film     ALTER COLUMN film_key     SET DEFAULT nextval('star.dim_film_film_key_seq'::regclass);
ALTER TABLE ONLY star.dim_staff    ALTER COLUMN staff_key    SET DEFAULT nextval('star.dim_staff_staff_key_seq'::regclass);
ALTER TABLE ONLY star.dim_store    ALTER COLUMN store_key    SET DEFAULT nextval('star.dim_store_store_key_seq'::regclass);

ALTER TABLE ONLY star.dim_actor             ADD CONSTRAINT dim_actor_pk                PRIMARY KEY (actor_key);
ALTER TABLE ONLY star.dim_bridge_film_actor ADD CONSTRAINT dim_bridge_film_actor_pkey  PRIMARY KEY (film_key, actor_key);
ALTER TABLE ONLY star.dim_customer          ADD CONSTRAINT dim_customer_pkey           PRIMARY KEY (customer_key);
ALTER TABLE ONLY star.dim_date              ADD CONSTRAINT dim_date_pkey               PRIMARY KEY (date_id);
ALTER TABLE ONLY star.dim_film              ADD CONSTRAINT dim_film_pkey               PRIMARY KEY (film_key);
ALTER TABLE ONLY star.dim_staff             ADD CONSTRAINT dim_staff_pkey              PRIMARY KEY (staff_key);
ALTER TABLE ONLY star.dim_store             ADD CONSTRAINT dim_store_pkey              PRIMARY KEY (store_key);

ALTER TABLE ONLY star.dim_bridge_film_actor
    ADD CONSTRAINT dim_bridge_film_actor_actor_key_fkey FOREIGN KEY (actor_key) REFERENCES star.dim_actor(actor_key);
ALTER TABLE ONLY star.dim_bridge_film_actor
    ADD CONSTRAINT dim_bridge_film_actor_film_key_fkey  FOREIGN KEY (film_key)  REFERENCES star.dim_film(film_key);


-- =====================================================================
-- 3. DIMENSIONS
-- =====================================================================

-- dim_date
-- CHANGED: range extended from 2026-12-31 to 2030-12-31 so incremental
-- loads after New Year still find their date keys.
INSERT INTO star.dim_date (
    date_id, year, quarter, month, month_name,
    day, day_of_week, day_name, is_weekend, week_of_year, full_date
)
SELECT
    to_char(d, 'YYYYMMDD')::int,
    EXTRACT(year    FROM d)::int,
    EXTRACT(quarter FROM d)::int,
    EXTRACT(month   FROM d)::int,
    trim(to_char(d, 'Month')),
    EXTRACT(day     FROM d)::int,
    EXTRACT(isodow  FROM d)::int,
    trim(to_char(d, 'Day')),
    EXTRACT(isodow  FROM d) IN (6, 7),
    EXTRACT(week    FROM d)::int,
    d::date
FROM generate_series('2020-01-01'::date, '2030-12-31'::date, '1 day') AS d;

-- Unknown member for unreturned rentals
INSERT INTO star.dim_date (
    date_id, year, quarter, month, month_name,
    day, day_of_week, day_name, is_weekend, week_of_year, full_date
)
VALUES (-1, -1, -1, -1, 'Unknown', -1, -1, 'Unknown', false, -1, '1900-01-01');


-- dim_actor
INSERT INTO star.dim_actor (actor_id, first_name, last_name)
SELECT actor_id, first_name, last_name
FROM public.actor;

-- NEW: placeholder member for films with no actors recorded in the source.
-- Without it, those films' revenue drops out of the bridge join and the
-- allocated-revenue report does not reconcile.
INSERT INTO star.dim_actor (actor_key, actor_id, first_name, last_name)
VALUES (-1, -1, 'Not', 'Recorded');


-- dim_film
INSERT INTO star.dim_film (
    film_id, title, description, release_year, language, original_language,
    rental_duration, rental_rate, length, replacement_cost,
    rental_duration_band, rental_rate_band, length_band, replacement_cost_band,
    rating, has_trailers, has_commentaries, has_deleted_scenes, has_behind_scenes, category
)
SELECT
    f.film_id,
    f.title,
    f.description,
    f.release_year,
    l.name,
    coalesce(l2.name, 'Unknown'),
    f.rental_duration,
    f.rental_rate,
    f.length,
    f.replacement_cost,
    CASE
        WHEN f.rental_duration < 4 THEN 'short'
        WHEN f.rental_duration <= 6 THEN 'medium'
        ELSE 'long'
    END,
    CASE
        WHEN f.rental_rate < 2 THEN 'cheap'
        WHEN f.rental_rate BETWEEN 2 AND 4 THEN 'medium'
        ELSE 'expensive'
    END,
    CASE
        WHEN f.length < 60 THEN 'short'
        WHEN f.length <= 120 THEN 'medium'
        ELSE 'long'
    END,
    CASE
        WHEN f.replacement_cost < 13 THEN 'cheap'
        WHEN f.replacement_cost <= 20 THEN 'medium'
        ELSE 'expensive'
    END,
    f.rating,
    coalesce(f.special_features @> array['Trailers']::text[], false),
    coalesce(f.special_features @> array['Commentaries']::text[], false),
    coalesce(f.special_features @> array['Deleted Scenes']::text[], false),
    coalesce(f.special_features @> array['Behind the Scenes']::text[], false),
    c.name
FROM public.film f
LEFT JOIN public.language l       ON l.language_id  = f.language_id
LEFT JOIN public.language l2      ON l2.language_id = f.original_language_id
LEFT JOIN public.film_category fc ON fc.film_id     = f.film_id
LEFT JOIN public.category c       ON c.category_id  = fc.category_id;


-- dim_customer
-- One version per customer on a fresh build; SCD Type 2 history is added
-- later by the change-detection pipeline.
INSERT INTO star.dim_customer (
    customer_id, registered_store_id, first_name, last_name, email, address,
    district, city, postal, phone, country, activebool,
    valid_from, valid_to, is_current
)
SELECT
    c.customer_id,
    c.store_id,
    c.first_name,
    c.last_name,
    coalesce(c.email, 'Unknown'),
    a.address,
    a.district,
    c2.city,
    a.postal_code,
    a.phone,
    c3.country,
    c.activebool,
    c.create_date,
    '9999-12-31',
    true
FROM public.customer c
LEFT JOIN public.address a  ON a.address_id  = c.address_id
LEFT JOIN public.city c2    ON c2.city_id    = a.city_id
LEFT JOIN public.country c3 ON c3.country_id = c2.country_id;


-- dim_staff
-- valid_from is a fixed date (not now()) so every rebuild is identical.
INSERT INTO star.dim_staff (
    staff_id, works_at_store_id, first_name, last_name, address, district,
    postal, phone, city, country, email, active, username,
    valid_from, valid_to, is_current
)
SELECT
    s.staff_id,
    s.store_id,
    s.first_name,
    s.last_name,
    a.address,
    a.district,
    a.postal_code,
    a.phone,
    c.city,
    c2.country,
    s.email,
    s.active,
    s.username,
    '2026-07-31',
    '9999-12-31',
    true
FROM public.staff s
LEFT JOIN public.address a  ON a.address_id  = s.address_id
LEFT JOIN public.city c     ON c.city_id     = a.city_id
LEFT JOIN public.country c2 ON c2.country_id = c.country_id;


-- dim_store (Type 1, no history)
INSERT INTO star.dim_store (
    store_id, manager_name, manager_surname, address, district,
    postal_code, phone, city, country
)
SELECT
    s.store_id,
    s2.first_name,
    s2.last_name,
    a.address,
    a.district,
    a.postal_code,
    a.phone,
    c.city,
    c2.country
FROM public.store s
LEFT JOIN public.staff s2   ON s2.staff_id   = s.manager_staff_id
LEFT JOIN public.address a  ON a.address_id  = s.address_id
LEFT JOIN public.city c     ON c.city_id     = a.city_id
LEFT JOIN public.country c2 ON c2.country_id = c.country_id;


-- =====================================================================
-- 4. BRIDGE (after dim_film and dim_actor)
-- =====================================================================

INSERT INTO star.dim_bridge_film_actor (film_key, actor_key, weighting_factor)
SELECT
    df.film_key,
    da.actor_key,
    1.0 / count(*) OVER (PARTITION BY fa.film_id)
FROM public.film_actor fa
JOIN star.dim_film df  ON df.film_id  = fa.film_id
JOIN star.dim_actor da ON da.actor_id = fa.actor_id;

-- NEW: every film with no actors in the source gets one bridge row to the
-- "Not Recorded" placeholder, weight 1, so its revenue is still allocated.
-- Driven from dim_film (not from revenue) because the bridge describes the
-- film, whether or not it was ever rented.
INSERT INTO star.dim_bridge_film_actor (film_key, actor_key, weighting_factor)
SELECT df.film_key, -1, 1
FROM star.dim_film df
WHERE NOT EXISTS (
    SELECT 1
    FROM star.dim_bridge_film_actor b
    WHERE b.film_key = df.film_key
);


-- =====================================================================
-- 5. FACTS (last: every dimension must be loaded)
-- =====================================================================

-- Joins to Type 2 dimensions use the natural key only. That is safe here
-- because a fresh build has exactly one version per customer/staff.
-- Recurring loads (02_merge_fact_rental.sql) use the version-at-the-time
-- BETWEEN condition instead.

INSERT INTO star.fact_rental (
    rental_id, customer_key, staff_key, rental_date_key, return_date_key,
    store_key, film_key, rental_duration_days
)
SELECT
    r.rental_id,
    dc.customer_key,
    ds.staff_key,
    dd.date_id,
    coalesce(to_char(r.return_date, 'YYYYMMDD')::int, -1),
    ds2.store_key,
    df.film_key,
    (r.return_date::date - r.rental_date::date)::int
FROM public.rental r
LEFT JOIN star.dim_customer dc ON dc.customer_id = r.customer_id
LEFT JOIN star.dim_staff ds    ON ds.staff_id    = r.staff_id
LEFT JOIN star.dim_date dd     ON dd.date_id     = to_char(r.rental_date, 'YYYYMMDD')::int
LEFT JOIN public.inventory i   ON i.inventory_id = r.inventory_id
LEFT JOIN star.dim_film df     ON df.film_id     = i.film_id
LEFT JOIN star.dim_store ds2   ON ds2.store_id   = i.store_id;


INSERT INTO star.fact_payment (
    payment_id, payment_date_key, customer_key, staff_key, rental_id, amount
)
SELECT
    p.payment_id,
    dd.date_id,
    c.customer_key,
    ds.staff_key,
    p.rental_id,
    p.amount
FROM public.payment p
LEFT JOIN star.dim_date dd     ON dd.date_id     = to_char(p.payment_date, 'YYYYMMDD')::int
LEFT JOIN star.dim_customer c  ON c.customer_id  = p.customer_id
LEFT JOIN star.dim_staff ds    ON ds.staff_id    = p.staff_id;


-- =====================================================================
-- 6. INDEXES
-- =====================================================================

-- NEW: one row per rental, enforced by the database. Speeds up the MERGE
-- match on rental_id and rejects accidental duplicate inserts.
CREATE UNIQUE INDEX ux_fact_rental_rental_id ON star.fact_rental (rental_id);

-- NEW: selective filter used in customer-level queries (Index Scan, not
-- Seq Scan, in EXPLAIN ANALYZE).
CREATE INDEX idx_fact_rental_customer ON star.fact_rental (customer_key);

-- Refresh planner statistics after the bulk load.
ANALYZE star.fact_rental;
ANALYZE star.fact_payment;
