-- =============================================================================
-- MYSPARK_DL - bootstrap (rodar UMA vez, como ACCOUNTADMIN). Idempotente.
-- Pré-requisitos já existentes: usuário ETL_USER (TYPE=SERVICE, key pair) e
-- warehouse ETL_WH.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1. Role do pipeline (pendurada em SYSADMIN, conforme boas práticas)
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ETL_ROLE COMMENT = 'Role do pipeline ETL MYSPARK_DL';
GRANT ROLE ETL_ROLE TO ROLE SYSADMIN;

-- USAGE já permite usar e auto-resumir o warehouse.
GRANT USAGE ON WAREHOUSE ETL_WH TO ROLE ETL_ROLE;

-- -----------------------------------------------------------------------------
-- 2. Banco e schemas (criados por SYSADMIN; schemas passam a ser da ETL_ROLE)
-- -----------------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS MYSPARK_DL COMMENT = 'Data lake medallion (TiDB -> Snowflake)';
CREATE SCHEMA IF NOT EXISTS MYSPARK_DL.BRONZE  COMMENT = 'Cópia crua da fonte TiDB (append-only)';
CREATE SCHEMA IF NOT EXISTS MYSPARK_DL.SILVER  COMMENT = 'Dados tratados + REJECTS';
CREATE SCHEMA IF NOT EXISTS MYSPARK_DL.GOLD    COMMENT = 'Star schema (SCD2 + fato)';
CREATE SCHEMA IF NOT EXISTS MYSPARK_DL.CONTROL COMMENT = 'Log de execução e watermarks';

GRANT USAGE ON DATABASE MYSPARK_DL TO ROLE ETL_ROLE;

-- Ownership dos schemas: a ETL_ROLE cria tabelas, views, sequences e stages
-- temporários sem precisar de grants adicionais.
GRANT OWNERSHIP ON SCHEMA MYSPARK_DL.BRONZE  TO ROLE ETL_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA MYSPARK_DL.SILVER  TO ROLE ETL_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA MYSPARK_DL.GOLD    TO ROLE ETL_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA MYSPARK_DL.CONTROL TO ROLE ETL_ROLE COPY CURRENT GRANTS;

-- -----------------------------------------------------------------------------
-- 3. Usuário de serviço
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

GRANT ROLE ETL_ROLE TO USER ETL_USER;
ALTER USER ETL_USER SET DEFAULT_ROLE = ETL_ROLE DEFAULT_WAREHOUSE = ETL_WH;

-- -----------------------------------------------------------------------------
-- 4. Proteção de créditos (conta trial)
-- -----------------------------------------------------------------------------
-- Cota mensal de 5 créditos: avisa em 75%/90%, suspende em 100% (deixa as
-- queries em execução terminarem) e suspende imediatamente em 110%.
-- Para receber os e-mails de aviso, habilite as notificações de resource
-- monitor no seu perfil (Snowsight > Settings > Notifications).
CREATE RESOURCE MONITOR IF NOT EXISTS ETL_MONITOR WITH
    CREDIT_QUOTA    = 5
    FREQUENCY       = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75  PERCENT DO NOTIFY
        ON 90  PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE ETL_WH SET
    RESOURCE_MONITOR            = ETL_MONITOR
    STATEMENT_TIMEOUT_IN_SECONDS = 1800;   -- nenhuma query passa de 30 min

-- -----------------------------------------------------------------------------
-- 5. Conferência
-- -----------------------------------------------------------------------------
SHOW GRANTS TO ROLE ETL_ROLE;
SHOW GRANTS TO USER ETL_USER;
