
create schema if not EXISTS raw ;

alter schema raw OWNER TO postgres;


create  TABLE if not EXISTS raw.fda_drug_enforcement(
    stg_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raw_data jsonb NOT NULL,
    recall_number text NOT NULL,
    loaded_at timestamptz default current_timestamp NOT NULL
);
