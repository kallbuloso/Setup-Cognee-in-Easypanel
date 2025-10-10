# ====== Config ======
SHELL := /bin/bash
PROJECT ?= cognee-prod

# Serviços (ajuste se renomear no compose)
SERVICE_API      ?= cognee
SERVICE_PG       ?= postgres
SERVICE_NEO4J    ?= neo4j
SERVICE_INIT     ?= init-cognee-fs

# Diretório local p/ backups
BACKUP_DIR ?= ./backups
DATE := $(shell date +%F_%H-%M-%S)

# ====== Helpers ======
define header
	@echo "==> $(1)"
endef

# ====== Ações principais ======

.PHONY: up
up: ## Sobe/atualiza toda a stack em segundo plano
	$(call header,"docker compose pull")
	@docker compose pull
	$(call header,"docker compose up -d")
	@docker compose up -d

.PHONY: down
down: ## Derruba toda a stack (mantém volumes)
	$(call header,"docker compose down")
	@docker compose down

.PHONY: restart
restart: ## Reinicia somente a API do Cognee
	$(call header,"restart: $(SERVICE_API)")
	@docker compose restart $(SERVICE_API)

.PHONY: ps
ps: ## Lista serviços da stack
	@docker compose ps

.PHONY: logs
logs: ## Segue logs de todos os serviços
	@docker compose logs -f

.PHONY: logs-api
logs-api: ## Segue logs do serviço Cognee
	@docker compose logs -f $(SERVICE_API)

.PHONY: logs-pg
logs-pg: ## Segue logs do Postgres
	@docker compose logs -f $(SERVICE_PG)

.PHONY: logs-neo4j
logs-neo4j: ## Segue logs do Neo4j
	@docker compose logs -f $(SERVICE_NEO4J)

.PHONY: health
health: ## Checa /health da API (requer curl e que a rota esteja publicada)
	@if command -v curl >/dev/null 2>&1; then \
		echo "GET /health"; \
		curl -fsS $${BASE_URL:-http://127.0.0.1:8000}/health || true; echo; \
	else \
		echo "Instale 'curl' para usar esta verificação local."; \
	fi

# ====== Lint / validações ======

.PHONY: lint
lint: ## Valida o docker-compose (estrutura + interpolação de envs)
	$(call header,"Validando docker-compose.yml")
	@docker compose config >/dev/null && echo "OK: docker-compose.yml válido."

.PHONY: lint-verbose
lint-verbose: ## Mostra a versão expandida do compose (útil p/ debug)
	$(call header,"docker compose config (expandido)")
	@docker compose config

# ====== Execução dentro dos containers ======

.PHONY: sh-api
sh-api: ## Shell dentro do container Cognee
	@docker compose exec $(SERVICE_API) bash || docker compose exec $(SERVICE_API) sh

.PHONY: sh-pg
sh-pg: ## Shell dentro do container Postgres
	@docker compose exec $(SERVICE_PG) bash || docker compose exec $(SERVICE_PG) sh

.PHONY: sh-neo4j
sh-neo4j: ## Shell dentro do container Neo4j
	@docker compose exec $(SERVICE_NEO4J) bash || docker compose exec $(SERVICE_NEO4J) sh

# ====== Seed / bootstrap ======
# Uso:
#  make seed EMAIL=admin@exemplo.com PASSWORD='SENHA_FORTE' [BASE_URL=https://api.seu-dominio.com]
#  - Salva o token em token.txt e imprime no console.

.PHONY: seed
seed: ## Cria um usuário e faz login; requer: EMAIL, PASSWORD; opcional: BASE_URL (default http://127.0.0.1:8000)
	@if ! command -v curl >/dev/null 2>&1; then echo "Erro: 'curl' não encontrado."; exit 1; fi
	@if ! command -v jq >/dev/null 2>&1; then echo "Erro: 'jq' não encontrado. Instale para usar 'make seed'."; exit 1; fi
	@if [ -z "$(EMAIL)" ] || [ -z "$(PASSWORD)" ]; then echo "Uso: make seed EMAIL=... PASSWORD=... [BASE_URL=...]"; exit 1; fi
	@BASE_URL=$${BASE_URL:-http://127.0.0.1:8000}; \
	echo "==> Registrando usuário em $$BASE_URL"; \
	curl -fsS -X POST "$$BASE_URL/api/v1/auth/register" \
	  -H "Content-Type: application/json" \
	  -d "{\"email\":\"$(EMAIL)\",\"password\":\"$(PASSWORD)\"}" || true; \
	echo; \
	echo "==> Autenticando..."; \
	TOKEN=$$(curl -fsS -X POST "$$BASE_URL/api/v1/auth/login" \
	  -H "Content-Type: application/json" \
	  -d "{\"email\":\"$(EMAIL)\",\"password\":\"$(PASSWORD)\"}" | jq -r '.access_token'); \
	if [ "$$TOKEN" = "null" ] || [ -z "$$TOKEN" ]; then echo "Falha ao obter token. Verifique as credenciais e se REQUIRE_AUTHENTICATION=true."; exit 2; fi; \
	echo "$$TOKEN" > token.txt; \
	echo "==> Token salvo em token.txt"; \
	echo "==> Testando endpoint autenticado (/api/v1/status)"; \
	curl -fsS "$$BASE_URL/api/v1/status" -H "Authorization: Bearer $$TOKEN" && echo; \
	echo "Pronto."

# Seed opcional: cria coleção 'demo' (requer token.txt já criado pelo alvo 'seed')
.PHONY: seed-collection
seed-collection: ## Cria collection 'demo' e insere um texto de exemplo
	@if ! command -v curl >/dev/null 2>&1; then echo "Erro: 'curl' não encontrado."; exit 1; fi
	@if [ ! -f token.txt ]; then echo "token.txt não encontrado. Rode 'make seed' primeiro."; exit 1; fi
	@BASE_URL=$${BASE_URL:-http://127.0.0.1:8000}; \
	TOKEN=$$(cat token.txt); \
	echo "==> Criando collection 'demo' em $$BASE_URL"; \
	curl -fsS -X POST "$$BASE_URL/api/v1/collections" \
	  -H "Authorization: Bearer $$TOKEN" \
	  -H "Content-Type: application/json" \
	  -d '{"name":"demo","description":"Coleção de teste"}' || true; \
	echo; \
	echo "==> Ingerindo texto de exemplo"; \
	curl -fsS -X POST "$$BASE_URL/api/v1/add?collection=demo" \
	  -H "Authorization: Bearer $$TOKEN" \
	  -H "Content-Type: application/json" \
	  -d '{"content":"Olá, mundo! Ingestão de teste no Cognee."}' && echo; \
	echo "Coleção 'demo' pronta."

# ====== Backups ======

.PHONY: backup
backup: backup-pg backup-neo4j backup-cognee ## Faz backup de todos os volumes

.PHONY: backup-pg
backup-pg: ## Backup do volume do Postgres (pg_data)
	@mkdir -p $(BACKUP_DIR)
	$(call header,"Backup Postgres -> $(BACKUP_DIR)/pg_data_$(DATE).tgz")
	@docker run --rm --volumes-from `docker compose ps -q $(SERVICE_PG)` \
		-v `pwd`:/backup alpine sh -lc \
		"apk add --no-cache tar >/dev/null && tar czf /backup/$(BACKUP_DIR)/pg_data_$(DATE).tgz /var/lib/postgresql/data"

.PHONY: backup-neo4j
backup-neo4j: ## Backup do volume do Neo4j (neo4j_data)
	@mkdir -p $(BACKUP_DIR)
	$(call header,"Backup Neo4j -> $(BACKUP_DIR)/neo4j_data_$(DATE).tgz")
	@docker run --rm --volumes-from `docker compose ps -q $(SERVICE_NEO4J)` \
		-v `pwd`:/backup alpine sh -lc \
		"apk add --no-cache tar >/dev/null && tar czf /backup/$(BACKUP_DIR)/neo4j_data_$(DATE).tgz /data"

.PHONY: backup-cognee
backup-cognee: ## Backup do diretório de dados do Cognee (cognee_system)
	@mkdir -p $(BACKUP_DIR)
	$(call header,"Backup Cognee -> $(BACKUP_DIR)/cognee_system_$(DATE).tgz")
	@docker run --rm --volumes-from `docker compose ps -q $(SERVICE_API)` \
		-v `pwd`:/backup alpine sh -lc \
		"apk add --no-cache tar >/dev/null && tar czf /backup/$(BACKUP_DIR)/cognee_system_$(DATE).tgz /app/.cognee_system"

# ====== Restore (manual assistido) ======
# Use com cautela: pare a stack, restaure e suba novamente.

.PHONY: restore-pg
restore-pg: ## Restaura pg_data a partir de um arquivo .tgz (ex.: make restore-pg FILE=backups/pg_data_<DATA>.tgz)
	@test -n "$(FILE)" || (echo "Uso: make restore-pg FILE=backups/arquivo.tgz" && exit 1)
	$(call header,"Restaurando Postgres de $(FILE)")
	@docker compose down
	@CONTAINER=`docker compose ps -q $(SERVICE_PG)`; \
	docker run --rm --volumes-from $$CONTAINER -v `pwd`:/backup alpine sh -lc \
	"apk add --no-cache tar >/dev/null && rm -rf /var/lib/postgresql/data/* && tar xzf /backup/$(FILE) -C /"
	@docker compose up -d

.PHONY: restore-neo4j
restore-neo4j: ## Restaura neo4j_data (ex.: make restore-neo4j FILE=backups/neo4j_data_<DATA>.tgz)
	@test -n "$(FILE)" || (echo "Uso: make restore-neo4j FILE=backups/arquivo.tgz" && exit 1)
	$(call header,"Restaurando Neo4j de $(FILE)")
	@docker compose down
	@CONTAINER=`docker compose ps -q $(SERVICE_NEO4J)`; \
	docker run --rm --volumes-from $$CONTAINER -v `pwd`:/backup alpine sh -lc \
	"apk add --no-cache tar >/dev/null && rm -rf /data/* && tar xzf /backup/$(FILE) -C /"
	@docker compose up -d

.PHONY: restore-cognee
restore-cognee: ## Restaura cognee_system (ex.: make restore-cognee FILE=backups/cognee_system_<DATA>.tgz)
	@test -n "$(FILE)" || (echo "Uso: make restore-cognee FILE=backups/arquivo.tgz" && exit 1)
	$(call header,"Restaurando Cognee system de $(FILE)")
	@docker compose down
	@CONTAINER=`docker compose ps -q $(SERVICE_API)`; \
	docker run --rm --volumes-from $$CONTAINER -v `pwd`:/backup alpine sh -lc \
	"apk add --no-cache tar >/dev/null && rm -rf /app/.cognee_system/* && tar xzf /backup/$(FILE) -C /"
	@docker compose up -d

# ====== Util ======

.PHONY: env-check
env-check: ## Mostra variáveis críticas no container da API (debug)
	@docker compose exec $(SERVICE_API) env | grep -E '^(DB_|VECTOR_DB_|GRAPH_DATABASE_|NEO4J_|LLM_|EMBEDDING_|REQUIRE_AUTHENTICATION|SYSTEM_ROOT_DIRECTORY)'

.PHONY: help
help: ## Mostra esta ajuda
	@grep -E '^[a-zA-Z0-9_\-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf " \033[36m%-22s\033[0m %s\n", $$1, $$2}'
