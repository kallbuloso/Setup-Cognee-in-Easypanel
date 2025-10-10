# Changelog

## [1.0.0] - 2025-10-09
### Added
- `docker-compose.yml` de produção consolidado:
  - Cognee API (imagem oficial)
  - Postgres + pgvector (vector store + relacional)
  - Neo4j (APOC + GDS) com healthcheck via `cypher-shell`
  - Serviço `init-cognee-fs` para preparar `/app/.cognee_system/databases`
- `.env.example` sanitizado (sem chaves vazias que quebrem validação)
- `README.md` com instruções de deploy, operação, backup e troubleshooting
- `.gitignore` incluindo `.env` e artefatos locais

### Notes
- Postgres e Neo4j não expõem portas; acesso interno pela rede do Compose.
- API exposta pelo proxy do Easypanel; health em `GET /health`.
