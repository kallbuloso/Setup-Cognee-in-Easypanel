# Cognee – Deploy de Produção (Easypanel + Docker Compose)

Deploy **pronto para produção** do Cognee com:
- **Cognee REST API** (imagem oficial)
- **Postgres + pgvector** (Vector Store + DB relacional)
- **Neo4j** (Grafo) com **APOC** e **GDS**
- Serviço **init** para preparar o volume do Cognee

Sem exposição de portas para Postgres/Neo4j (somente rede interna do Compose). A API é publicada pelo proxy do **Easypanel**.

---

## Sumário
- [Arquitetura](#arquitetura)
- [Requisitos](#requisitos)
- [Arquivos do projeto](#arquivos-do-projeto)
- [Configuração](#configuração)
- [Deploy no Easypanel](#deploy-no-easypanel)
- [Teste rápido](#teste-rápido)
- [Operações de rotina](#operações-de-rotina)
- [Backup e Restore](#backup-e-restore)
- [Atualizações](#atualizações)
- [Monitoramento e Health](#monitoramento-e-health)
- [Segurança](#segurança)
- [Solução de problemas (FAQ)](#solução-de-problemas-faq)
- [Licença](#licença)

---

## Arquitetura

```

┌─────────────────┐        ┌─────────────────────┐
│ Easypanel Proxy │  ───▶  │  cognee (porta 8000)│
└─────────────────┘        └─────────┬───────────┘
          │ rede interna (docker)
┌─────────▼──────────┐
│  postgres+pgvector │  (sem portas expostas)
└─────────┬──────────┘
          │
┌─────────▼──────────┐
│       neo4j        │  (APOC+GDS; sem portas expostas)
└────────────────────┘

```

- **Volumes persistentes**:
  - `cognee_system` – dados locais do Cognee (`/app/.cognee_system`)
  - `pg_data` – dados do Postgres
  - `neo4j_data`, `neo4j_logs`, `neo4j_import`, `neo4j_plugins` – dados do Neo4j

---

## Requisitos
- VPS Linux (ex.: Ubuntu 22.04+)
- Docker + Docker Compose
- Easypanel (opcional, mas recomendado)
- Chave de API do provedor LLM (ex.: **OpenAI**)

---

## Arquivos do projeto

```

.
├─ docker-compose.yml
├─ .env                 # suas credenciais (NÃO versionar público)
├─ .env.example         # modelo de variáveis
└─ .gitignore

````

> **Importante**: mantenha o `.env` **fora** de repositórios públicos.

---

## Configuração

1. Copie `.env.example` para `.env`:
```bash
   cp .env.example .env
````

2. Edite o `.env` e ajuste **senhas** e **chaves**:

   * `LLM_API_KEY`
   * `DB_PASSWORD`
   * `NEO4J_PASSWORD`
   * (opcional) `GRAPH_DATABASE_PASSWORD`

---

## Deploy no Easypanel

1. Crie um **App → Docker Compose**.
2. Cole o conteúdo do `docker-compose.yml`.
3. Em **Environment file**, aponte para o `.env`.
4. **Deploy**.

> Postgres/Neo4j **não** expõem portas; a API do Cognee será publicada pelo proxy do Easypanel.
> Configure o domínio/rota no painel conforme sua preferência; o healthcheck pode usar `GET /health`.

---

## Teste rápido

* Saúde:

  ```bash
  curl -sS http://SEU_DOMINIO/health
  ```
* Docs (Swagger):
  ```bash
  http://SEU_DOMINIO/docs
  ```

### Autenticação (se `REQUIRE_AUTHENTICATION=true`)

```bash
# cadastro
curl -sS -X POST http://SEU_DOMINIO/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@exemplo.com","password":"SENHA_FORTE"}'

# login
curl -sS -X POST http://SEU_DOMINIO/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@exemplo.com","password":"SENHA_FORTE"}'
```

Use o `access_token` no header `Authorization: Bearer ...`.

---

## Operações de rotina

* **Ver logs**:

  ```bash
  docker compose logs -f cognee
  docker compose logs -f postgres
  docker compose logs -f neo4j
  ```
* **Reiniciar apenas a API**:

  ```bash
  docker compose restart cognee
  ```

---

## Backup e Restore

### Backup (volumes)

* **Postgres** (`pg_data`):

  ```bash
  docker run --rm --volumes-from $(docker compose ps -q postgres) \
    -v $(pwd):/backup alpine sh -lc \
    'apk add --no-cache tar && tar czf /backup/pg_data_$(date +%F).tgz /var/lib/postgresql/data'
  ```

* **Neo4j** (`neo4j_data`):

  ```bash
  docker run --rm --volumes-from $(docker compose ps -q neo4j) \
    -v $(pwd):/backup alpine sh -lc \
    'apk add --no-cache tar && tar czf /backup/neo4j_data_$(date +%F).tgz /data'
  ```

* **Cognee** (`cognee_system`):

  ```bash
  docker run --rm --volumes-from $(docker compose ps -q cognee) \
    -v $(pwd):/backup alpine sh -lc \
    'apk add --no-cache tar && tar czf /backup/cognee_system_$(date +%F).tgz /app/.cognee_system'
  ```

### Restore

* Pare a stack, restaure os arquivos nos mesmos caminhos dos volumes e **suba** novamente.

---

## Atualizações

```bash
docker compose pull
docker compose up -d
# conferir /health e /docs
```

Se o Neo4j mudar de tag e reclamar de chaves novas/antigas, remova envs desconhecidas ou desative validação estrita **temporariamente**. Em geral, mantenha a tag estável (ex.: `neo4j:5.25-community` e `pgvector/pgvector:pg16`).

---

## Monitoramento e Health

* **/health** (API)
* Healthcheck do Neo4j via `cypher-shell` (configurado no `docker-compose.yml`)
* Opcional: Prometheus/Grafana (não incluído)

---

## Segurança

* **Não** exponha Postgres/Neo4j publicamente (mantido por padrão).
* Use senhas fortes e armazene o `.env` como **secret** no Easypanel.
* Faça **backups** regulares de `pg_data` e `neo4j_data`.

---

## Solução de problemas (FAQ)

* **Porta 5432 em uso**
  Remova `ports` do Postgres (já removido por padrão) ou altere a porta. Melhor: **não publicar** Postgres.

* **Neo4j “unhealthy”**
  O healthcheck usa `cypher-shell`; garanta `NEO4J_PASSWORD` correto e dê tempo para o boot inicial (plugins).

* **ValidationError: vector_db_port**
  Não deixe `VECTOR_DB_PORT=` vazio; defina `VECTOR_DB_PORT=5432` ou remova a chave.

* **`/app/.cognee_system/databases` não encontrado**
  O serviço `init-cognee-fs` cria a pasta automaticamente. Se limpou o volume, ele recria no próximo deploy.

* **PDF Advanced loader**
  Log informativo: usa `PyPdfLoader` se `unstructured[pdf]` não estiver instalado. Funciona normal.

---

## Licença

Este repositório fornece apenas os artefatos de **deploy**. O Cognee segue a licença do projeto original. Consulte a licença oficial do Cognee [na página do GitHub](https://github.com/topoteretes/cognee/blob/main/LICENSE).
