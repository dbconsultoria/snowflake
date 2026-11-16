"""Configuração do pipeline.

Local: lê ./.env e ./snowflake/.env (python-dotenv).
GitHub Actions: as mesmas variáveis chegam como env vars vindas de Secrets
(variáveis já definidas no ambiente nunca são sobrescritas pelo .env).

Chave privada do Snowflake, em ordem de prioridade:
  1. SNOWFLAKE_PRIVATE_KEY       conteúdo PEM completo (GitHub Actions)
  2. SNOWFLAKE_PRIVATE_KEY_PATH  caminho do arquivo .p8 (local), relativo à raiz do projeto
"""
from __future__ import annotations

import os
import re
import textwrap
from dataclasses import dataclass
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = PROJECT_ROOT / "sql"

for _env_file in (PROJECT_ROOT / ".env", PROJECT_ROOT / "snowflake" / ".env"):
    if _env_file.is_file():
        load_dotenv(_env_file, override=False)


class ConfigError(RuntimeError):
    pass


def _required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise ConfigError(f"Variável de ambiente obrigatória ausente: {name}")
    return value


def _optional(name: str, default: str | None = None) -> str | None:
    value = os.getenv(name, "").strip()
    return value or default


_PEM_RE = re.compile(
    r"-----BEGIN ([A-Z ]*PRIVATE KEY)-----(.*?)-----END \1-----", re.DOTALL
)


def _normalize_pem(raw: str) -> bytes:
    """Remonta o PEM a partir de um secret colado de forma imperfeita.

    Aceita: quebras de linha trocadas por espaços, "\\n" literal, CRLF, aspas
    em volta, indentação, e até só o corpo base64 sem BEGIN/END.
    """
    text = raw.strip().strip("'\"").replace("\\n", "\n").replace("\r", "")
    match = _PEM_RE.search(text)
    if match:
        label, body = match.group(1), match.group(2)
    else:
        label, body = "PRIVATE KEY", text
    body = re.sub(r"\s+", "", body)
    if not body or not re.fullmatch(r"[A-Za-z0-9+/=]+", body):
        raise ConfigError(
            "SNOWFLAKE_PRIVATE_KEY não contém uma chave PEM válida "
            f"({len(raw)} caracteres recebidos; esperado o conteúdo completo do .p8)"
        )
    lines = "\n".join(textwrap.wrap(body, 64))
    return f"-----BEGIN {label}-----\n{lines}\n-----END {label}-----\n".encode()


def _load_private_key_der() -> bytes:
    pem_content = _optional("SNOWFLAKE_PRIVATE_KEY")
    if pem_content:
        pem_bytes = _normalize_pem(pem_content)
        source = "SNOWFLAKE_PRIVATE_KEY"
    else:
        key_path = Path(_required("SNOWFLAKE_PRIVATE_KEY_PATH"))
        if not key_path.is_absolute():
            key_path = PROJECT_ROOT / key_path
        if not key_path.is_file():
            raise ConfigError(f"Arquivo da chave privada não encontrado: {key_path}")
        pem_bytes = key_path.read_bytes()
        source = str(key_path)

    passphrase = _optional("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
    try:
        key = serialization.load_pem_private_key(
            pem_bytes, password=passphrase.encode() if passphrase else None
        )
    except Exception as exc:  # noqa: BLE001
        raise ConfigError(f"Não foi possível ler a chave privada ({source}): {exc}") from exc

    return key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


@dataclass(frozen=True)
class SnowflakeConfig:
    account: str
    user: str
    warehouse: str
    role: str
    database: str
    private_key_der: bytes


@dataclass(frozen=True)
class TiDBConfig:
    host: str
    port: int
    user: str
    password: str
    database: str
    ssl_ca: str | None  # None => bundle do certifi


def snowflake_config() -> SnowflakeConfig:
    return SnowflakeConfig(
        account=_required("SNOWFLAKE_ACCOUNT"),
        user=_required("SNOWFLAKE_USER"),
        warehouse=_required("SNOWFLAKE_WAREHOUSE"),
        role=_optional("SNOWFLAKE_ROLE", "ETL_ROLE"),
        database=_optional("SNOWFLAKE_DATABASE", "MYSPARK_DL"),
        private_key_der=_load_private_key_der(),
    )


def tidb_config() -> TiDBConfig:
    return TiDBConfig(
        host=_required("DB_HOST"),
        port=int(_optional("DB_PORT", "4000")),
        user=_required("DB_USERNAME"),
        password=_required("DB_PASSWORD"),
        database=_required("DB_DATABASE"),
        ssl_ca=_optional("DB_SSL_CA"),
    )
