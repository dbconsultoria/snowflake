"""Ponto de entrada do pipeline.

    python -m etl.main --step all
    python -m etl.main --step bronze
    python -m etl.main --step silver --batch-id 20261116T060000Z-1a2b3c4d
"""
from __future__ import annotations

import argparse
import os
import sys
import uuid
from datetime import datetime, timezone

from etl.connections import snowflake_connection
from etl.load_bronze import run_bronze
from etl.log import get_logger, github_error, setup_logging
from etl.run_sql import run_ddl, run_sql_dir, run_tests

STEPS = ("ddl", "bronze", "silver", "gold", "tests")

log = get_logger("etl.main")


def new_batch_id() -> str:
    return f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"


def write_github_output(name: str, value: str) -> None:
    output_file = os.getenv("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a", encoding="utf-8") as fh:
            fh.write(f"{name}={value}\n")


def run(step: str, batch_id: str) -> None:
    steps = STEPS if step == "all" else (step,)
    with snowflake_connection(query_tag=f"myspark_dl:{step}:{batch_id}") as sf:
        for s in steps:
            log.info("stage started", extra={"stage": s, "batch_id": batch_id})
            if s == "ddl":
                run_ddl(sf)
            elif s == "bronze":
                run_bronze(sf, batch_id)
            elif s in ("silver", "gold"):
                run_sql_dir(sf, s, batch_id)
            elif s == "tests":
                run_tests(sf, batch_id)
            log.info("stage finished", extra={"stage": s, "batch_id": batch_id})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pipeline medallion TiDB -> Snowflake")
    parser.add_argument("--step", choices=(*STEPS, "all"), default="all")
    parser.add_argument("--batch-id", default=None, help="Reutiliza um batch existente (silver/gold/tests)")
    args = parser.parse_args(argv)

    setup_logging()
    batch_id = args.batch_id or new_batch_id()
    write_github_output("batch_id", batch_id)

    try:
        run(args.step, batch_id)
    except Exception as exc:  # noqa: BLE001
        log.exception("pipeline failed", extra={"step": args.step, "batch_id": batch_id})
        github_error(f"Pipeline falhou na etapa '{args.step}' (batch {batch_id}): {exc}")
        return 1
    log.info("pipeline succeeded", extra={"step": args.step, "batch_id": batch_id})
    return 0


if __name__ == "__main__":
    sys.exit(main())
