# MYSPARK_DL — data lake medallion no Snowflake

Recriação do data lake do [myspark](https://github.com/dbconsultoria/myspark) no Snowflake, com a
mesma modelagem medallion. Fonte OLTP: **TiDB Cloud** (MySQL, porta 4000, TLS obrigatório).
Processamento em **Python**, orquestração por **GitHub Actions**. Sem Spark, sem Airflow.

![Arquitetura do MYSPARK_DL: TiDB Cloud → Bronze → Silver → Gold → testes de qualidade no Snowflake, orquestrado pelo GitHub Actions](MySpark%20Data%20Lake%20Medallion%20Architecture.png)

<details>
<summary>Versão em texto do fluxo</summary>

```
TiDB (tbcategories, tbproducts, tbcustomers, tborders, tborderdetail)
  │  PyMySQL + TLS
  ▼
BRONZE   cópia crua, append-only, tipos da fonte + _ingested_at/_batch_id
  │  views V_<tabela>_LATEST = snapshot vigente
  ▼
SILVER   tratado (trim, nulos, email, telefone, datas) + integridade -> SILVER.REJECTS
  ▼
GOLD     DIM_CATEGORIES / DIM_PRODUCTS / DIM_CUSTOMERS (SCD2, MERGE) + FACT_ORDERS
  ▼
tests    reconciliação entre camadas, unicidade SCD2, fato sem chave órfã
CONTROL  ETL_RUN_LOG (cada etapa/tabela) + WATERMARK (carga incremental)
```

</details>

## Estrutura

```
etl/
  config.py        variáveis (.env local / Secrets no Actions), chave por arquivo ou conteúdo
  connections.py   TiDB (TLS verificado, UTC) e Snowflake (key pair)
  extract.py       schema da fonte e extração (FULL ou INCREMENTAL por watermark)
  load_bronze.py   write_pandas (PUT parquet + COPY INTO) em tabelas pré-criadas
  run_sql.py       executa sql/<camada>/*.sql em ordem numérica; runner de testes
  control.py       CONTROL.ETL_RUN_LOG e CONTROL.WATERMARK
  log.py           logging JSON (uma linha por evento)
  main.py          CLI: --step ddl|bronze|silver|gold|tests|all
sql/
  ddl/             DDL idempotente de CONTROL, BRONZE, SILVER, GOLD (roda a cada execução)
  silver/          01..05 — uma tabela por arquivo
  gold/            01..03 dimensões SCD2, 04 fato
  tests/           SELECTs que retornam violações (-- severity: error | warn)
setup/00_bootstrap.sql   role, banco, schemas, grants, resource monitor (uma vez, ACCOUNTADMIN)
.github/workflows/pipeline.yml
```

## Setup

### 1. Snowflake (uma vez)

Pré-requisitos já existentes: usuário `ETL_USER` (TYPE = SERVICE, key pair) e warehouse `ETL_WH`.

Rode `setup/00_bootstrap.sql` inteiro numa worksheet como **ACCOUNTADMIN**. Ele é idempotente e cria:

- Role `ETL_ROLE` (filha de SYSADMIN) com `USAGE` no `ETL_WH`
- Banco `MYSPARK_DL` e schemas `BRONZE`, `SILVER`, `GOLD`, `CONTROL` (ownership da `ETL_ROLE`)
- Grant da role ao `ETL_USER` + `DEFAULT_ROLE`/`DEFAULT_WAREHOUSE`
- Resource monitor `ETL_MONITOR`: 5 créditos/mês, avisa em 75%/90%, suspende o `ETL_WH` em 100%
- `STATEMENT_TIMEOUT_IN_SECONDS = 1800` no `ETL_WH`

As tabelas **não** são criadas no bootstrap: o pipeline aplica `sql/ddl/` a cada execução
(`CREATE ... IF NOT EXISTS`). Para alterar uma tabela existente, use `ALTER TABLE` num novo
arquivo de DDL ou recrie a tabela.

### 2. Ambiente local

```bash
python -m venv .venv
.venv\Scripts\activate            # Windows  (Linux/macOS: source .venv/bin/activate)
pip install -r requirements.txt
```

Variáveis: copie `.env.example` para `snowflake/.env` e preencha. O `config.py` lê `./.env` e
`./snowflake/.env`; variáveis já definidas no ambiente têm prioridade.

- Chave privada local: `SNOWFLAKE_PRIVATE_KEY_PATH`, relativo à raiz do projeto
  (ex.: `./snowflake/rsa_key.p8`).
- Se a chave for criptografada, defina `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`.

`.env`, `*.p8`, `*.pub`, `*.pem` e `*.key` estão no `.gitignore`.

### 3. GitHub Secrets

Em *Settings → Secrets and variables → Actions → New repository secret*:

| Secret | Valor |
|---|---|
| `SNOWFLAKE_ACCOUNT` | identificador da conta (`ORG-ACCOUNT`) |
| `SNOWFLAKE_USER` | `ETL_USER` |
| `SNOWFLAKE_WAREHOUSE` | `ETL_WH` |
| `SNOWFLAKE_ROLE` | `ETL_ROLE` |
| `SNOWFLAKE_DATABASE` | `MYSPARK_DL` |
| `SNOWFLAKE_PRIVATE_KEY` | conteúdo **completo** do `.p8`, incluindo `-----BEGIN/END PRIVATE KEY-----` |
| `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` | só se a chave for criptografada |
| `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE` | conexão TiDB (sem aspas) |

No Actions o `SNOWFLAKE_PRIVATE_KEY` tem prioridade sobre o `_PATH`. Quebras de linha reais ou
`\n` literais funcionam.

> **TiDB Cloud:** os runners do GitHub usam IPs dinâmicos. Se o cluster tiver regras de firewall
> no endpoint público, ele precisa aceitar conexões de qualquer IP (a autenticação continua por
> usuário/senha + TLS).

## Como rodar

```bash
python -m etl.main --step all          # ddl -> bronze -> silver -> gold -> tests
python -m etl.main --step bronze       # só uma etapa
python -m etl.main --step tests --batch-id 20261116T060000Z-1a2b3c4d
```

Cada execução tem um `batch_id` (`YYYYMMDDTHHMMSSZ-xxxxxxxx`), gravado no Bronze, no Silver, no
Gold, em `SILVER.REJECTS` e em `CONTROL.ETL_RUN_LOG`. Qualquer erro gera exit code 1.

**GitHub Actions** (`.github/workflows/pipeline.yml`):

- Gatilhos: manual (`workflow_dispatch`) e semanal (segunda-feira, 06:00 UTC).
- Jobs `bronze → silver → gold → quality-tests` encadeados por `needs`. O `batch_id` gerado no
  bronze é repassado aos demais.
- Cache de pip; `concurrency` impede execuções sobrepostas.
- Um erro falha o job e cria uma anotação `::error::` no resumo da execução.

Consultas úteis:

```sql
SELECT * FROM MYSPARK_DL.CONTROL.ETL_RUN_LOG ORDER BY started_at DESC;
SELECT * FROM MYSPARK_DL.SILVER.REJECTS WHERE batch_id = '<batch>';
SELECT * FROM MYSPARK_DL.CONTROL.WATERMARK;
```

## Regras por camada

### Bronze
- Append-only: cada execução acrescenta um batch; nada é sobrescrito.
- Tipos da fonte preservados: `int → NUMBER(10,0)`, `decimal(18,2) → NUMBER(18,2)`,
  `datetime/timestamp → TIMESTAMP_NTZ`. Os timestamps são lidos do TiDB com `time_zone = '+00:00'`
  e ficam em **UTC**.
- Views `BRONZE.V_<tabela>_LATEST`: snapshot vigente da fonte.
  - Consideram só o que chegou desde a última carga FULL, então linhas apagadas na fonte somem do
    snapshot.
  - Para tabelas com PK, mantêm a última versão de cada `code`.
  - Para `tborderdetail` (sem PK), mantêm as linhas do batch mais recente de cada pedido.

### Silver (reconstruído a cada execução)
| Tabela | Tratamento | Rejeição (→ `SILVER.REJECTS`) |
|---|---|---|
| tbcategories | trim, espaços colapsados | chave nula |
| tbproducts | trim; `active` → BOOLEAN (NULL → TRUE, default da fonte) | `category` órfã; `salevalue` negativo |
| tbcustomers | trim; email minúsculo (inválido → NULL); telefone só dígitos; `birthdate` → DATE (fora de 1900..hoje → NULL) | chave nula |
| tborders | — | `customer` órfão |
| tborderdetail | **sem deduplicação** (linhas idênticas são legítimas; a fato expõe `line_count`) | sem pedido (`orders` nulo); pedido ou produto órfão/rejeitado; `quantity` ≤ 0; `salesvalue` nulo/negativo |

- **FK órfã** (código que não existe na tabela pai) é rejeitada.
- **FK nula** é válida (a fonte usa `ON DELETE SET NULL`) e vira o membro `-1` no Gold. A exceção
  é o item sem pedido, que não teria como entrar na fato.
- Rejeição em cascata: se um produto ou pedido é rejeitado, seus itens também são.
- `REJECTS` guarda a linha original inteira em `record` (VARIANT).

### Gold
- **SCD2** com `MERGE` em uma única instrução: o hash `SHA2-256` dos atributos rastreados detecta
  a mudança, a versão vigente é fechada e a nova é inserida.
  - `valid_to = 9999-12-31` na versão vigente.
  - Intervalo semiaberto: `[valid_from, valid_to)`.
  - A **primeira versão de cada chave começa em 1900-01-01**, para que pedidos anteriores à
    primeira carga resolvam a versão vigente na data.
  - As versões seguintes começam no timestamp da execução.
  - Atributos rastreados: categorias = descrição; produtos = descrição, preço, ativo, categoria;
    clientes = nome, endereço, telefone, email, nascimento.
  - Registros apagados na fonte mantêm sua versão vigente no Gold.
- **FACT_ORDERS**: uma linha por produto por pedido.
  - `order_code` é a dimensão degenerada.
  - `customer_sk` e `product_sk` são resolvidas pela versão vigente em `order_date`.
  - Medidas: `total_quantity`, `total_sales = Σ quantity × salesvalue` e `line_count`.
  - É reconstruída por completo (`INSERT OVERWRITE`), o que é idempotente.
- Membro `-1` ("Desconhecido") em todas as dimensões.

### Testes (`sql/tests`)
| Teste | Severidade |
|---|---|
| Bronze (snapshot) = Silver + rejeitados do batch, por tabela | error |
| Linhas, quantidade e valor: Silver = fato | error |
| Exatamente um `is_current` por chave de negócio | error |
| Vigências contíguas, sem sobreposição/buraco | error |
| Fato sem SK órfã e grão (pedido, produto) único | error |
| Todo código não nulo resolve uma versão vigente na data do pedido | error |
| Linhas da fato no membro `-1` | warn |
| Resumo das rejeições do batch | warn |

Para criar um teste novo, adicione um `NN_nome.sql` com um `SELECT` que retorne as violações e a
linha `-- severity: error|warn`.

## Carga incremental

Todas as tabelas começam em `FULL`. **A fonte não tem colunas `updated_at`**, então o watermark só
detecta **inserções**:

- `tbcategories`, `tbproducts`, `tbcustomers` devem continuar em FULL. Em incremental, o SCD2 nunca
  veria alterações.
- `tborders` (watermark `code`) e `tborderdetail` (watermark `orders`) podem virar incrementais:

```sql
UPDATE MYSPARK_DL.CONTROL.WATERMARK SET load_mode = 'INCREMENTAL'
WHERE table_name IN ('TBORDERS', 'TBORDERDETAIL');
```

O watermark é atualizado em toda carga, inclusive FULL, então a troca vale a partir da próxima
execução. Limitação: um item adicionado depois a um pedido já carregado não é capturado. Para
ressincronizar tudo, volte para `FULL` por uma execução.

## Custo (conta trial)

- Volume pequeno: cerca de 10 mil linhas por execução. Uma execução semanal com `ETL_WH` XS
  consome poucos minutos de warehouse. Cada job pode retomar o warehouse, com cobrança mínima de
  60 s por retomada.
- O resource monitor suspende o warehouse ao atingir 5 créditos no mês.
- O Bronze cresce cerca de 10 mil linhas por semana. Para limitar o histórico:
  `DELETE FROM BRONZE.<T> WHERE _ingested_at < (SELECT last_full_load_at FROM CONTROL.WATERMARK WHERE table_name = '<T>')`.

## Limitações conhecidas
- Sem timestamps de alteração na fonte, uma mudança de cadastro é datada pelo momento em que o
  pipeline a detecta. Pedidos feitos entre a alteração real e a execução ficam com a versão
  anterior.
- `CREATE TABLE IF NOT EXISTS` não altera tabelas existentes. Uma evolução de schema exige
  `ALTER` (ver Apêndice A).

---

## Apêndice A — Adicionando uma nova dimensão

O pipeline não descobre tabelas novas sozinho: cada camada é declarada explicitamente. Incluir uma
dimensão é basicamente copiar os padrões que já existem. O workflow do GitHub Actions **não muda**,
porque ele executa tudo o que estiver nas pastas `sql/`.

Exemplo usado abaixo: entra na fonte uma tabela `tbsuppliers (code, name, email)` e a
`tbproducts` ganha a coluna `supplier`.

### A.1 Passo a passo

**1. Extração** (`etl/extract.py`): acrescente a tabela em `SOURCE_TABLES`.

```python
SourceTable("tbsuppliers", (("code", "int"), ("name", "str"), ("email", "str"))),
```

Se uma tabela existente ganhou coluna, acrescente a coluna também (`("supplier", "int")` em
`tbproducts`).

**2. Bronze** (`sql/ddl/02_bronze.sql`): crie a tabela com os tipos da fonte, mais `_ingested_at` e
`_batch_id`, e a view `V_TBSUPPLIERS_LATEST`, copiando a de `tbcategories`.

**3. Watermark** (`sql/ddl/01_control.sql`): acrescente `('TBSUPPLIERS', NULL)` no `VALUES` do
`MERGE`. O MERGE só insere o que falta, então é seguro rodar de novo.

**4. Silver**
- Em `sql/ddl/03_silver.sql`, declare a tabela.
- Crie `sql/silver/02_tbsuppliers.sql`, copiando o script de categorias. Ele precisa rodar **antes**
  de `tbproducts`, para a checagem de FK órfã enxergar os fornecedores. Os scripts rodam em ordem
  alfabética, então renumere os seguintes com `git mv` (por exemplo,
  `02_tbproducts.sql` → `03_tbproducts.sql`).
- No script de produtos, acrescente a rejeição
  `WHEN b.supplier IS NOT NULL AND s.code IS NULL THEN 'FK órfã: supplier=...'`, com um
  `LEFT JOIN SILVER.TBSUPPLIERS s ON s.code = b.supplier`.

**5. Gold**
- Em `sql/ddl/04_gold.sql`, crie a sequence, a tabela `DIM_SUPPLIERS` e o membro `-1`.
- Crie `sql/gold/NN_dim_suppliers.sql` copiando o MERGE de `01_dim_categories.sql`. Troque só as
  colunas e a lista de atributos do hash.

**6. Testes**: inclua a dimensão nova em:
- `01_layer_counts.sql` (contagens entre camadas);
- `03_scd2_single_current.sql` e `04_scd2_contiguous_ranges.sql` (SCD2);
- `05_fact_orphan_keys.sql` e `06_fact_version_resolution.sql`, se ela entrar na fato.

**7. README**: atualize as tabelas de regras por camada.

### A.2 Decisão de modelagem: como a dimensão se liga à fato

| Opção | Como fica | Quando usar |
|---|---|---|
| **A — pelo produto** (snowflake) | `DIM_PRODUCTS` ganha `supplier_code`, como já tem `category_code`. A fato não muda. | O fornecedor é sempre o mesmo para o produto. Mais simples. |
| **B — direto na fato** (estrela) | A fato ganha `supplier_sk`, resolvido pela data do pedido como as outras chaves. No `04_fact_orders.sql` entra mais um `LEFT JOIN` com `COALESCE(..., -1)`. | O fornecedor depende do pedido. |

### A.3 Cuidados com tabelas que já existem

**1. `CREATE TABLE IF NOT EXISTS` não altera tabelas existentes.** Coluna nova em tabela que já
existe precisa de um `ALTER` no DDL. Ele também pode rodar várias vezes:

```sql
ALTER TABLE BRONZE.TBPRODUCTS ADD COLUMN IF NOT EXISTS supplier NUMBER(10,0);
ALTER TABLE SILVER.TBPRODUCTS ADD COLUMN IF NOT EXISTS supplier NUMBER(10,0);
ALTER TABLE GOLD.FACT_ORDERS  ADD COLUMN IF NOT EXISTS supplier_sk NUMBER(38,0) DEFAULT -1;
```

**2. Atributo novo no hash gera uma versão nova de todos os registros.** Na opção A, ao acrescentar
`supplier_code` ao hash de `DIM_PRODUCTS`, todos os produtos têm o hash alterado na execução
seguinte e ganham uma versão nova, mesmo sem mudança real. Há duas saídas:
- aceitar isso, já que o histórico continua consistente;
- ou, antes do deploy, preencher a coluna nova nas versões vigentes e recalcular o `attr_hash`
  delas com a fórmula nova. Assim só mudanças reais geram versão:

```sql
UPDATE GOLD.DIM_PRODUCTS d
   SET supplier_code = s.supplier,
       attr_hash = SHA2(CONCAT_WS('|',
           COALESCE(s.description, '~'),
           COALESCE(TO_VARCHAR(s.salevalue), '~'),
           COALESCE(TO_VARCHAR(s.active), '~'),
           COALESCE(TO_VARCHAR(s.category), '~'),
           COALESCE(TO_VARCHAR(s.supplier), '~')), 256)   -- mesma fórmula do novo MERGE
  FROM SILVER.TBPRODUCTS s
 WHERE d.product_code = s.code
   AND d.is_current;
```

Rode esse `UPDATE` depois de o Silver já ter a coluna nova e antes do primeiro Gold com o hash novo.

### A.4 Checklist

- [ ] `etl/extract.py` — tabela/coluna em `SOURCE_TABLES`
- [ ] `sql/ddl/01_control.sql` — seed do watermark
- [ ] `sql/ddl/02_bronze.sql` — tabela + view `_LATEST` (+ `ALTER` se for coluna nova)
- [ ] `sql/ddl/03_silver.sql` + `sql/silver/NN_*.sql` — na ordem certa de dependência
- [ ] `sql/ddl/04_gold.sql` + `sql/gold/NN_dim_*.sql` — sequence, tabela, membro `-1`, MERGE
- [ ] `sql/gold/04_fact_orders.sql` — se a dimensão entrar na fato
- [ ] `sql/tests/` — contagens, SCD2 e chaves órfãs
- [ ] Hash: aceitar a nova versão em massa ou recalcular o `attr_hash` antes
- [ ] Rodar localmente `python -m etl.main --step all` antes do push
