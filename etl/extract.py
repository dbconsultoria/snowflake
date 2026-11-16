"""Extração das tabelas OLTP do TiDB para DataFrames pandas."""
from __future__ import annotations

from dataclasses import dataclass

import pandas as pd
import pymysql

from etl.control import Watermark
from etl.log import get_logger

log = get_logger(__name__)


@dataclass(frozen=True)
class SourceTable:
    name: str
    # (nome da coluna na fonte, tipo lógico: int | decimal | str | datetime)
    columns: tuple[tuple[str, str], ...]


# Schema da fonte (mysql/dump.sql). Ordem = ordem de carga.
SOURCE_TABLES: tuple[SourceTable, ...] = (
    SourceTable("tbcategories", (("code", "int"), ("description", "str"))),
    SourceTable(
        "tbproducts",
        (("code", "int"), ("description", "str"), ("salevalue", "decimal"),
         ("active", "int"), ("category", "int")),
    ),
    SourceTable(
        "tbcustomers",
        (("code", "int"), ("Name", "str"), ("Address", "str"), ("Phone", "str"),
         ("Email", "str"), ("BirthDate", "datetime")),
    ),
    SourceTable("tborders", (("code", "int"), ("customer", "int"), ("orderdate", "datetime"))),
    SourceTable(
        "tborderdetail",
        (("product", "int"), ("orders", "int"), ("quantity", "int"), ("salesvalue", "decimal")),
    ),
)


def _build_query(table: SourceTable, wm: Watermark) -> tuple[str, tuple]:
    select_list = ", ".join(f"`{col}` AS `{col.lower()}`" for col, _ in table.columns)
    sql = f"SELECT {select_list} FROM `{table.name}`"
    params: tuple = ()
    if wm.load_mode == "INCREMENTAL":
        if not wm.watermark_column:
            raise ValueError(f"{table.name}: load_mode INCREMENTAL exige watermark_column")
        valid_cols = {c.lower() for c, _ in table.columns}
        if wm.watermark_column.lower() not in valid_cols:
            raise ValueError(f"{table.name}: watermark_column inválida: {wm.watermark_column}")
        if wm.watermark_value is not None:
            sql += f" WHERE `{wm.watermark_column.lower()}` > %s"
            params = (wm.watermark_value,)
    return sql, params


def _typed_frame(table: SourceTable, rows: list[tuple]) -> pd.DataFrame:
    names = [col.lower() for col, _ in table.columns]
    df = pd.DataFrame.from_records(rows, columns=names)
    for (col, kind), name in zip(table.columns, names):
        if kind == "int":
            df[name] = df[name].astype("Int64")  # inteiro com NULL
        elif kind == "datetime":
            df[name] = pd.to_datetime(df[name])
        elif kind == "str":
            df[name] = df[name].astype("object")
        # decimal: mantém objetos Decimal -> decimal128 no parquet (precisão exata)
    return df


def extract_table(conn: pymysql.connections.Connection, table: SourceTable, wm: Watermark) -> pd.DataFrame:
    sql, params = _build_query(table, wm)
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
    df = _typed_frame(table, list(rows))
    log.info(
        "table extracted",
        extra={"table": table.name, "rows": len(df), "load_mode": wm.load_mode,
               "watermark_from": wm.watermark_value if wm.load_mode == "INCREMENTAL" else None},
    )
    return df
