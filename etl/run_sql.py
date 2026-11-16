"""Executa os arquivos .sql versionados em ordem numérica.

Cada arquivo pode conter vários statements. Antes de rodar, a sessão recebe
as variáveis $batch_id e $run_ts, usadas pelos scripts.
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path

from snowflake.connector import SnowflakeConnection

from etl.config import SQL_DIR
from etl.control import logged_step
from etl.log import get_logger

log = get_logger(__name__)

_SEVERITY_RE = re.compile(r"--\s*severity:\s*(error|warn)", re.IGNORECASE)


class DataQualityError(RuntimeError):
    pass


def sql_files(subdir: str) -> list[Path]:
    files = sorted((SQL_DIR / subdir).glob("*.sql"), key=lambda p: p.name)
    if not files:
        raise FileNotFoundError(f"Nenhum arquivo .sql em {SQL_DIR / subdir}")
    return files


def set_session_vars(conn: SnowflakeConnection, batch_id: str, run_ts: datetime | None = None) -> None:
    run_ts = run_ts or datetime.now(timezone.utc).replace(tzinfo=None)
    conn.cursor().execute(
        "SET (batch_id, run_ts) = (%s, %s::TIMESTAMP_NTZ)",
        (batch_id, run_ts.strftime("%Y-%m-%d %H:%M:%S.%f")),
    )


def _execute_file(conn: SnowflakeConnection, path: Path) -> int | None:
    """Retorna o rowcount do ÚLTIMO DML do arquivo (convenção: a carga principal
    fica no fim de cada script; rejeições etc. vêm antes)."""
    last_dml_rows = None
    for cur in conn.execute_string(path.read_text(encoding="utf-8"), remove_comments=True):
        if cur.description and cur.description[0].name.lower().startswith("number of rows"):
            last_dml_rows = cur.rowcount
    return last_dml_rows


def run_ddl(conn: SnowflakeConnection) -> None:
    """DDL idempotente; roda antes de existir CONTROL, então só loga no stdout."""
    for path in sql_files("ddl"):
        _execute_file(conn, path)
        log.info("ddl applied", extra={"file": path.name})


def run_sql_dir(conn: SnowflakeConnection, subdir: str, batch_id: str) -> None:
    set_session_vars(conn, batch_id)
    for path in sql_files(subdir):
        with logged_step(conn, batch_id, subdir, path.stem.upper()) as step:
            step.rows = _execute_file(conn, path)


def run_tests(conn: SnowflakeConnection, batch_id: str) -> None:
    """Cada teste é um SELECT que retorna as violações. 0 linhas = passou."""
    set_session_vars(conn, batch_id)
    failures: list[str] = []
    for path in sql_files("tests"):
        sql = path.read_text(encoding="utf-8")
        match = _SEVERITY_RE.search(sql)
        severity = match.group(1).lower() if match else "error"
        with logged_step(conn, batch_id, "tests", path.stem.upper()) as step:
            cur = conn.cursor().execute(sql)
            rows = cur.fetchall()
            step.rows = len(rows)
            if rows:
                cols = [d.name.lower() for d in cur.description]
                sample = [dict(zip(cols, r)) for r in rows[:10]]
                level = "error" if severity == "error" else "warning"
                getattr(log, level)(
                    "data quality violation",
                    extra={"test": path.stem, "severity": severity, "violations": len(rows), "sample": sample},
                )
                if severity == "error":
                    failures.append(f"{path.stem} ({len(rows)} violações)")
            else:
                log.info("data quality passed", extra={"test": path.stem})
    if failures:
        raise DataQualityError("Testes de qualidade falharam: " + ", ".join(failures))
