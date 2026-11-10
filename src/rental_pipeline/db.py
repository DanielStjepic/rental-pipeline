import psycopg
from dotenv import load_dotenv
import os
from psycopg import Connection
from psycopg.rows import TupleRow



load_dotenv()
def get_connection() -> Connection[TupleRow]:
    return psycopg.connect(host=os.environ['PG_HOST'], port =os.environ['PG_PORT'], dbname=os.environ['PG_DBNAME'], user=os.environ['PG_USER'], password=os.environ['PG_PASSWORD'], connect_timeout = 3)




