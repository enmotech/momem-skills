---
name: memory-retrieval
description: Retrieve relevant memories from the memory bank based on query text. Use when the agent needs to recall past experiences, error resolutions, or environment facts before executing a task.
---

# Memory Retrieval

Retrieve relevant memories from `agent_memories` table based on query text with scope filtering.

## Script Location

All scripts are in the `scripts/` directory relative to this SKILL.md file. Before invoking any script, resolve the absolute path:

```
SKILL_DIR = directory containing this SKILL.md file
SCRIPTS   = $SKILL_DIR/scripts/
```

All bash commands below use `$SCRIPTS/<script>` as the full path. Do NOT use relative paths or assume a working directory.

## Scripts

| Script | Purpose |
|--------|---------|
| `$SCRIPTS/retrieve_global_and_exact.sql` | Global injection (environment_fact/preference) + exact error_code match |
| `$SCRIPTS/retrieve_similar.sql` | Vector similarity search with scope weighting |
| `$SCRIPTS/render_sql.py` | Render `:param` SQL placeholders before executing with SwissQL |

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `swissql_profile_id` | Yes | SwissQL backend connection profile ID |
| `workspace_id` | Yes | Workspace ID for multi-tenant isolation |
| `query` | Yes | Query text for vector search |
| `profile_id` | No | Filter by connection profile (scope weighting) |
| `db_type` | No | Filter by database engine (scope weighting) |
| `project_id` | No | Filter by project |
| `memory_types` | No | Filter by memory types (comma-separated, e.g., `error_resolution,failure_scenario`) |
| `top_k` | No | Max results per type (default: 3) |
| `embedding_api` | No | Embedding API endpoint (default: `$EMBEDDING_API`) |
| `embedding_key` | No | Embedding API key (default: `$EMBEDDING_KEY`) |
| `embedding_model` | No | Embedding model name (default: `$EMBEDDING_MODEL`) |

## Environment Variables

The following environment variables are used as defaults for Embedding API parameters:

| Variable | Description | Example |
|----------|-------------|---------|
| `EMBEDDING_API` | API endpoint | `https://api.openai.com/v1/embeddings` |
| `EMBEDDING_KEY` | API key | `sk-xxx` |
| `EMBEDDING_MODEL` | Model name | `text-embedding-3-small` |

## Workflow

### Execution Helper

The current `swissql exec` command does not support `-p key=value` parameters.
Render SQL files first, then execute the rendered temporary SQL file:

```bash
SWISSQL_PROFILE_ID="{{swissql_profile_id}}"

render_sql() {
  local sql_file="$1"
  shift
  env "$@" python3 "$SCRIPTS/render_sql.py" "$sql_file"
}

run_sql() {
  local sql_file="$1"
  shift
  local tmp
  tmp=$(mktemp)
  render_sql "$sql_file" "$@" > "$tmp"
  swissql exec --profile-id "$SWISSQL_PROFILE_ID" --file "$tmp"
  rm -f "$tmp"
}
```

### Step 1: Get Query Embedding

Call Embedding API to vectorize the query:

```bash
# Use parameters if provided, otherwise fall back to environment variables
EMBED_API=${{embedding_api:-$EMBEDDING_API}}
EMBED_KEY=${{embedding_key:-$EMBEDDING_KEY}}
EMBED_MODEL=${{embedding_model:-$EMBEDDING_MODEL}}

curl -s "$EMBED_API" \
  -H "Authorization: Bearer $EMBED_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"$EMBED_MODEL\", \"input\": \"{{query}}\"}" \
  | jq -r '.data[0].embedding'
```

### Step 2: Retrieve Global and Exact Matches

Execute SQL to get:
- **Global injection**: All non-superseded `environment_fact` and `preference` memories
- **Exact match**: `error_resolution` memories with matching `error_code` from query

```bash
run_sql "$SCRIPTS/retrieve_global_and_exact.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_profile_id="{{profile_id}}" \
  SQL_PARAM_project_id="{{project_id}}" \
  SQL_PARAM_query="{{query}}"
```

### Step 3: Retrieve Similar Memories

Execute SQL to get vector-similar memories with scope weighting:

```bash
run_sql "$SCRIPTS/retrieve_similar.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_query_embedding="{{query_embedding}}" \
  SQL_PARAM_profile_id="{{profile_id}}" \
  SQL_PARAM_db_type="{{db_type}}" \
  SQL_PARAM_project_id="{{project_id}}" \
  SQL_PARAM_memory_types="{{memory_types}}" \
  SQL_PARAM_top_k="{{top_k}}"
```

### Step 4: Merge and Sort Results

Combine results from Step 2 and Step 3:

1. **Deduplicate**: Remove duplicate memories by `id`
2. **Sort**: 
   - `human_correction` memories first (highest priority)
   - Then by `similarity * scope_weight` descending
3. **Limit**: Return top K results

### Step 5: Format Output

```json
{
  "query": "ORA-01555 undo retention",
  "scope": {
    "workspace_id": "ws-123",
    "profile_id": "prod-oracle-1",
    "db_type": "oracle"
  },
  "memories": [
    {
      "id": "mem-456",
      "type": "error_resolution",
      "content": "prod-oracle-1 上的 ORA-01555：由每晚 2 点的 ETL 长事务触发；将 undo_retention 从 900s 调整为 3600s；问题解决，次次运行已验证。",
      "similarity": 0.92,
      "scope_weight": 1.0,
      "metadata": {
        "ticket_id": "xxx",
        "error_code": "ORA-01555"
      },
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "stats": {
    "total": 5,
    "by_type": {
      "error_resolution": 2,
      "environment_fact": 2,
      "preference": 1
    }
  }
}
```

## Scope Weighting

Memories are weighted by scope match:

| Scope Match | Weight | Example |
|-------------|--------|---------|
| `profile_id` exact match | 1.0 | Memory for `prod-oracle-1`, query for `prod-oracle-1` |
| `db_type` match | 0.6 | Memory for `oracle`, query for `oracle` (different profile) |
| No match | 0.3 | Memory with no profile/db_type, or different db_type |

## Memory Types

| Type | Retrieval Strategy |
|------|-------------------|
| `environment_fact` | Always injected (global) |
| `preference` | Always injected (global) |
| `error_resolution` | Exact match on `error_code` + vector similarity |
| `failure_scenario` | Vector similarity only |
| `success_playbook` | Vector similarity only |
| `human_correction` | Vector similarity (highest priority in sort) |

## Performance Optimization

- SQL queries: 4+ → 2 (50%+ reduction)
- HNSW index scans: 4 → 1 (75% reduction)
- Network round trips: 4+ → 2 (50%+ reduction)
