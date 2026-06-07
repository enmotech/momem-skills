# Momem Skills

AI Agent skills for `momem` — the CLI-first memory distillation and retrieval tool for DBA operations knowledge.

This repository is automatically synced from the `skills/` directory of `momem-cli` on every release.

## Available Skills

| Skill | Purpose | Key Operations |
|---|---|---|
| [memory-distillation](skills/memory-distillation/SKILL.md) | Extract and distill structured memories from completed tickets into the memory bank | SQL queries on undistilled tickets, transcript aggregation, similarity deduplication checks, and storage in pgvector |
| [memory-retrieval](skills/memory-retrieval/SKILL.md) | Recall relevant memories based on query text with scope filtering and frequency weighting | Exact error_code match, vector similarity search, scope weighting (profile_id, db_type, project_id), and frequency boost |

## Environment & Secrets Configuration

To run these skills, make sure the executing environment has the following credentials and variables configured:

### 1. Database Connection
- `SWISSQL_PROFILE_ID`: The SwissQL backend connection profile ID used to execute SQL scripts.
- `MOMEM_DB_URL`: PostgreSQL connection URL used by the underlying DB connection for CLI path.

### 2. Embedding API (For Vector Retrieval and Storage)
- `EMBEDDING_API`: The endpoint of your vector embedding provider (e.g. `https://api.openai.com/v1/embeddings`).
- `EMBEDDING_KEY`: The API key for your embedding provider.
- `EMBEDDING_MODEL`: The model name used for embeddings (e.g. `text-embedding-3-small`).

## How It Works

1. **Deduplication on Storage**:
   Similar memories are not stored multiple times. Instead, the `occurrence_count` is incremented, and the contributing `ticket_id` is appended to `metadata.ticket_ids`.
2. **Scope Weighting**:
   Retrieved memories are weighted based on how closely they match the target environment:
   - `profile_id` match: 1.0
   - `db_type` match: 0.6
   - General (no match): 0.3
3. **Frequency Boost**:
   `ln(occurrence_count + 1)` prioritizes frequently-observed patterns during retrieval.

## Contributing

These skills are versioned and maintained as part of the [momem-cli](https://github.com/enmotech/momem-cli) repository. Please submit all changes, fixes, or improvements to the upstream `momem-cli` repository under the `skills/` directory.

## License

This project is licensed under the same license as the upstream `momem-cli` repository.
