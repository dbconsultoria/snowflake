"""Logging estruturado (uma linha JSON por evento)."""
from __future__ import annotations

import json
import logging
import os
import sys
from datetime import datetime, timezone

_STANDARD_ATTRS = set(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key not in _STANDARD_ATTRS and not key.startswith("_"):
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str, ensure_ascii=False)


def setup_logging() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # console do Windows
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    # O conector do Snowflake é muito verboso em INFO.
    logging.getLogger("snowflake").setLevel(logging.WARNING)


def github_error(message: str) -> None:
    """Gera uma anotação de erro visível no resumo do GitHub Actions."""
    if os.getenv("GITHUB_ACTIONS") == "true":
        print(f"::error::{message.replace(chr(10), ' ')}", flush=True)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
