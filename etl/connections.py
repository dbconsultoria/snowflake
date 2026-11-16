"""Fábricas de conexão: TiDB (PyMySQL + TLS) e Snowflake (key pair)."""
from __future__ import annotations

import certifi
import pymysql
import snowflake.connector

from etl.config import snowflake_config, tidb_config


def tidb_connection() -> pymysql.connections.Connection:
    cfg = tidb_config()
    return pymysql.connect(
        host=cfg.host,
        port=cfg.port,
        user=cfg.user,
        password=cfg.password,
        database=cfg.database,
        charset="utf8mb4",
        # TLS obrigatório no TiDB Cloud: verifica certificado e hostname.
        ssl={"ca": cfg.ssl_ca or certifi.where()},
        ssl_verify_cert=True,
        ssl_verify_identity=True,
        connect_timeout=30,
        read_timeout=600,
        # TIMESTAMP do MySQL passa a ser entregue em UTC.
        init_command="SET time_zone = '+00:00'",
    )


def snowflake_connection(query_tag: str = "myspark_dl") -> snowflake.connector.SnowflakeConnection:
    cfg = snowflake_config()
    return snowflake.connector.connect(
        account=cfg.account,
        user=cfg.user,
        private_key=cfg.private_key_der,
        role=cfg.role,
        warehouse=cfg.warehouse,
        database=cfg.database,
        application="myspark_dl_etl",
        session_parameters={
            "QUERY_TAG": query_tag,
            "TIMEZONE": "UTC",
            "STATEMENT_TIMEOUT_IN_SECONDS": 1800,
        },
    )
