"""Acesso ao schema CONTROL: log de execução e watermarks."""
from __future__ import annotations

import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterator

from snowflake.connector import SnowflakeConnection

from etl.log import get_logger

log = get_logger(__name__)


@dataclass
class StepResult:
    rows: int | None = None


@contextmanager
def logged_step(
    conn: SnowflakeConnection, batch_id: str, step: str, table_name: str
) -> Iterator[StepResult]:
    """Registra RUNNING -> SUCCESS/FAILED em CONTROL.ETL_RUN_LOG."""
    log_id = str(uuid.uuid4())
    result = StepResult()
    ctx = {"batch_id": batch_id, "step": step, "table": table_name}
    conn.cursor().execute(
        "INSERT INTO CONTROL.ETL_RUN_LOG (log_id, batch_id, step, table_name, status, started_at) "
        "VALUES (%s, %s, %s, %s, 'RUNNING', SYSDATE())",
        (log_id, batch_id, step, table_name),
    )
    log.info("step started", extra=ctx)
    try:
        yield result
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"[:4000]
        conn.cursor().execute(
            "UPDATE CONTROL.ETL_RUN_LOG SET status = 'FAILED', ended_at = SYSDATE(), "
            "rows_affected = %s, error_message = %s WHERE log_id = %s",
            (result.rows, error, log_id),
        )
        log.error("step failed", extra={**ctx, "error": error})
        raise
    conn.cursor().execute(
        "UPDATE CONTROL.ETL_RUN_LOG SET status = 'SUCCESS', ended_at = SYSDATE(), "
        "rows_affected = %s WHERE log_id = %s",
        (result.rows, log_id),
    )
    log.info("step finished", extra={**ctx, "rows": result.rows})


@dataclass(frozen=True)
class Watermark:
    table_name: str
    load_mode: str  # FULL | INCREMENTAL
    watermark_column: str | None
    watermark_value: str | None


def get_watermark(conn: SnowflakeConnection, table_name: str) -> Watermark:
    row = conn.cursor().execute(
        "SELECT table_name, load_mode, watermark_column, watermark_value "
        "FROM CONTROL.WATERMARK WHERE table_name = %s",
        (table_name.upper(),),
    ).fetchone()
    if row is None:
        return Watermark(table_name.upper(), "FULL", None, None)
    return Watermark(*row)


def update_watermark(
    conn: SnowflakeConnection,
    table_name: str,
    batch_id: str,
    load_mode: str,
    new_value: str | None,
) -> None:
    """Avança o watermark e, em carga FULL, marca o início do snapshot vigente.

    last_full_load_at é lido do próprio Bronze (MIN(_ingested_at) do batch),
    garantindo igualdade exata com o valor gravado. Uma carga FULL vazia
    usa SYSDATE(), o que faz o snapshot vigente ficar vazio (correto).
    """
    table = table_name.upper()
    full_load_expr = (
        f"COALESCE((SELECT MIN(_ingested_at) FROM BRONZE.{table} "
        f"WHERE _batch_id = %(batch_id)s), SYSDATE())"
        if load_mode == "FULL"
        else "last_full_load_at"
    )
    conn.cursor().execute(
        f"""
        UPDATE CONTROL.WATERMARK
           SET watermark_value   = COALESCE(%(value)s, watermark_value),
               last_full_load_at = COALESCE({full_load_expr}, last_full_load_at),
               last_batch_id     = %(batch_id)s,
               updated_at        = SYSDATE()
         WHERE table_name = %(table)s
        """,
        {"value": new_value, "batch_id": batch_id, "table": table},
    )
