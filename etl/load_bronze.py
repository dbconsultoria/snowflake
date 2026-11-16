"""Carga das tabelas extraídas no schema BRONZE (append-only).

write_pandas faz PUT (parquet) em stage temporário + COPY INTO. As tabelas
Bronze são pré-criadas (sql/ddl) com os tipos da fonte, então nada é inferido.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pandas as pd
from snowflake.connector import SnowflakeConnection
from snowflake.connector.pandas_tools import write_pandas

from etl.connections import tidb_connection
from etl.control import get_watermark, logged_step, update_watermark
from etl.extract import SOURCE_TABLES, SourceTable, extract_table
from etl.log import get_logger

log = get_logger(__name__)


def _load_table(sf: SnowflakeConnection, df: pd.DataFrame, table: SourceTable, batch_id: str) -> int:
    if df.empty:
        return 0
    df = df.copy()
    df.columns = [c.upper() for c in df.columns]
    df["_INGESTED_AT"] = pd.Timestamp(datetime.now(timezone.utc).replace(tzinfo=None))
    df["_BATCH_ID"] = batch_id

    success, _chunks, nrows, _ = write_pandas(
        sf,
        df,
        table_name=table.name.upper(),
        schema="BRONZE",
        auto_create_table=False,
        overwrite=False,
        quote_identifiers=True,
        use_logical_type=True,
    )
    if not success or nrows != len(df):
        raise RuntimeError(f"write_pandas falhou para {table.name}: {nrows}/{len(df)} linhas")
    return nrows


def run_bronze(sf: SnowflakeConnection, batch_id: str) -> None:
    with tidb_connection() as tidb:
        for table in SOURCE_TABLES:
            with logged_step(sf, batch_id, "bronze", table.name.upper()) as step:
                wm = get_watermark(sf, table.name)
                df = extract_table(tidb, table, wm)
                step.rows = _load_table(sf, df, table, batch_id)

                new_wm = None
                if wm.watermark_column:
                    values = df[wm.watermark_column.lower()].dropna()
                    if not values.empty:
                        new_wm = str(values.max())
                update_watermark(sf, table.name, batch_id, wm.load_mode, new_wm)
