---
name: memory-distillation
description: Extract and distill memories from completed tickets into the memory bank. Use when the agent is awakened by cron to process unprocessed tickets, or when the user explicitly requests memory distillation.
---

# Memory Distillation

Extract structured memories from completed tickets and store them in the memory bank for future retrieval.

## Script Location

All scripts are in the `scripts/` directory relative to this SKILL.md file. Before invoking any script, resolve the absolute path:

```
SKILL_DIR = directory containing this SKILL.md file
SCRIPTS   = $SKILL_DIR/scripts/
REFERENCE = $SKILL_DIR/reference/
```

All bash commands or SQL scripts below use `$SCRIPTS/<script>` as the full path. Do NOT use relative paths or assume a working directory.

## Scripts

| Script | Purpose |
|--------|---------|
| `$SCRIPTS/get_undistilled_tickets.sql` | Query undistilled tickets with optional filters |
| `$SCRIPTS/get_ticket_transcript.sql` | Get complete ticket transcript (comments, tasks, messages) |
| `$SCRIPTS/check_similar_memory.sql` | Check if similar memory exists (deduplication) |
| `$SCRIPTS/update_memory_occurrence.sql` | Update occurrence_count for existing memory |
| `$SCRIPTS/store_memory.sql` | Store a NEW memory (only when no similar exists) |
| `$SCRIPTS/mark_ticket_distilled.sql` | Mark a ticket as distilled |
| `$SCRIPTS/supersede_memory.sql` | Supersede old memories for environment_fact/preference |
| `$SCRIPTS/clear_ticket_distillation.sql` | Clear distillation status for re-distillation |
| `$SCRIPTS/render_sql.py` | Render `:param` SQL placeholders before executing with SwissQL |

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `swissql_profile_id` | Yes | SwissQL backend connection profile ID (where the memory tables are stored, e.g. `moclaw-pg`) |
| `profile_id` | Yes | Target database connection profile ID (the profile where the ticket worked/operated, e.g. `momas-mysql-expert`). Extract this from the ticket's transcript/tool calls. Do NOT use `swissql_profile_id` / `moclaw-pg` here. |
| `db_type` | Yes | Target database engine type (e.g. `mysql`, `oracle`, `postgres`). Extract this from the ticket transcript. |
| `workspace_id` | Yes | Workspace ID to process |
| `ticket_id` | No | Specific ticket ID (process all undistilled if omitted) |
| `since` | No | Time range filter (e.g., "2 hours ago", "2024-01-01") |
| `agent_id` | No | Filter by agent UUID |
| `agent_name` | No | Filter by agent name |
| `skill_name` | No | Filter by skill name |
| `project_id` | No | Filter by project UUID |
| `embedding_api` | No | Embedding API endpoint (default: `$EMBEDDING_API`) |
| `embedding_key` | No | Embedding API key (default: `$EMBEDDING_KEY`) |
| `embedding_model` | No | Embedding model name (default: `$EMBEDDING_MODEL`) |
| `similarity_threshold` | No | Deduplication threshold (default: 0.85; preference uses max 0.80, success_playbook uses max 0.82) |
| `distiller_type` | No | Distiller type (e.g. `agent` or manually omitted) |
| `distiller_id` | No | Distiller ID/UUID |
| `distiller_name` | No | Distiller name |

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

run_write_sql() {
  local sql_file="$1"
  shift
  local tmp
  tmp=$(mktemp)
  render_sql "$sql_file" "$@" > "$tmp"
  swissql exec --profile-id "$SWISSQL_PROFILE_ID" --allow-write --file "$tmp"
  rm -f "$tmp"
}
```

### Step 1: Query Undistilled Tickets

Execute SQL to get undistilled tickets with optional filters:

```bash
run_sql "$SCRIPTS/get_undistilled_tickets.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_ticket_id="{{ticket_id}}" \
  SQL_PARAM_since="{{since}}" \
  SQL_PARAM_agent_id="{{agent_id}}" \
  SQL_PARAM_agent_name="{{agent_name}}" \
  SQL_PARAM_skill_name="{{skill_name}}" \
  SQL_PARAM_project_id="{{project_id}}"
```

**Filter examples:**

```bash
# Process all undistilled tickets in workspace
run_sql "$SCRIPTS/get_undistilled_tickets.sql" \
  SQL_PARAM_workspace_id=ws-123

# Filter by agent name
run_sql "$SCRIPTS/get_undistilled_tickets.sql" \
  SQL_PARAM_workspace_id=ws-123 \
  SQL_PARAM_agent_name=pg-checker

# Filter by skill and time range
run_sql "$SCRIPTS/get_undistilled_tickets.sql" \
  SQL_PARAM_workspace_id=ws-123 \
  SQL_PARAM_skill_name=demo-pg-check \
  SQL_PARAM_since="2 hours ago"

# Combine multiple filters (AND relationship)
run_sql "$SCRIPTS/get_undistilled_tickets.sql" \
  SQL_PARAM_workspace_id=ws-123 \
  SQL_PARAM_agent_name=pg-checker \
  SQL_PARAM_skill_name=demo-pg-check \
  SQL_PARAM_project_id=proj-456 \
  SQL_PARAM_since=2024-01-01
```

### Step 2: Get Ticket Transcript

For each ticket, aggregate all related data (comments, tasks, messages):

```bash
run_sql "$SCRIPTS/get_ticket_transcript.sql" \
  SQL_PARAM_ticket_id="{{ticket_id}}"
```

### Step 2.5: Identify Target Database Profile and Type

Before distilling memories, analyze the ticket transcript (comments, tasks, and task messages) to identify:
1. The **target database connection profile ID** (the SwissQL profile the ticket was operating on, such as `momas-mysql-expert` or `momas-mysql-master`, usually visible in command line tool calls like `--profile-id <profile>`). Do **not** use the memory storage profile (e.g., `moclaw-pg` or `$SWISSQL_PROFILE_ID`) for this.
2. The **database engine type** (e.g., `mysql`, `oracle`, `postgres`).

These identified values must be used as `profile_id` and `db_type` parameters in subsequent steps.

### Step 3: Distill Memories

Read the transcript and apply the distillation prompt (see `$REFERENCE/distillation-prompt.md`).

Output format:

```json
[
  {"type": "error_resolution", "content": "...", "error_code": "..."},
  {"type": "failure_scenario", "content": "..."},
  {"type": "success_playbook", "content": {"fault": "...", "preconditions": [...], "steps": [...], "validation": [...], "rollback": "..."}},
  {"type": "environment_fact", "content": "..."},
  {"type": "preference", "content": "..."}
]
```

### Step 4: Store Memories (with Deduplication)

For each memory in the distilled result:

1. Call Embedding API to get vector:

```bash
# Use parameters if provided, otherwise fall back to environment variables
EMBED_API=${{embedding_api:-$EMBEDDING_API}}
EMBED_KEY=${{embedding_key:-$EMBEDDING_KEY}}
EMBED_MODEL=${{embedding_model:-$EMBEDDING_MODEL}}

curl -s "$EMBED_API" \
  -H "Authorization: Bearer $EMBED_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"$EMBED_MODEL\", \"input\": \"{{content}}\"}" \
  | jq -r '.data[0].embedding'
```

2. Check for similar memory (deduplication):

```bash
run_sql "$SCRIPTS/check_similar_memory.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_memory_type="{{type}}" \
  SQL_PARAM_profile_id="{{profile_id}}" \
  SQL_PARAM_project_id="{{project_id}}" \
  SQL_PARAM_new_embedding="{{embedding_vector}}" \
  SQL_PARAM_error_code="{{error_code}}" \
  SQL_PARAM_similarity_threshold="{{similarity_threshold}}"
```

3. **Decision**: If similar memory found (similarity > threshold):
   - Update existing memory's `occurrence_count`:

```bash
run_write_sql "$SCRIPTS/update_memory_occurrence.sql" \
  SQL_PARAM_memory_id="{{existing_memory_id}}" \
  SQL_PARAM_ticket_id="{{ticket_id}}"
```

   - Skip storing new memory

4. **Decision**: If no similar memory found:
   - Store new memory:

```bash
run_write_sql "$SCRIPTS/store_memory.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_profile_id="{{profile_id}}" \
  SQL_PARAM_db_type="{{db_type}}" \
  SQL_PARAM_memory_type="{{type}}" \
  SQL_PARAM_content="{{content}}" \
  SQL_PARAM_embedding="{{embedding_vector}}" \
  SQL_PARAM_ticket_id="{{ticket_id}}" \
  SQL_PARAM_project_id="{{project_id}}" \
  SQL_PARAM_error_code="{{error_code}}" \
  SQL_PARAM_distill_version="{{distill_version}}"
```

`store_memory.sql` and `update_memory_occurrence.sql` derive ticket provenance
from `ticket_id`: `agent_memories.agent_id` is the ticket's primary/assignee
agent, and `metadata.agent_ids` contains all participating agents with the
primary agent first. `metadata.ticket_ids` records every ticket that contributed
to a deduplicated memory. Callers should not pass agent provenance manually.

   - For `environment_fact` and `preference` types, supersede old memories **with the same profile_id**:

```bash
run_write_sql "$SCRIPTS/supersede_memory.sql" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_memory_type="{{type}}" \
  SQL_PARAM_profile_id="{{profile_id}}" \
  SQL_PARAM_project_id="{{project_id}}" \
  SQL_PARAM_new_memory_id="{{new_id}}"
```

**Important**: Only memories with the same `profile_id` are superseded. This prevents cross-environment contamination (e.g., oracle A's facts won't overwrite oracle B's facts).

**Deduplication**: Similar memories are not stored again. Instead, `occurrence_count` is incremented on the existing memory. Default similarity threshold is 0.85; `preference` uses max 0.80 and `success_playbook` uses max 0.82 because these are often phrased differently across equivalent tickets. `error_resolution` additionally requires the same `error_code` when one is provided.

### Step 5: Mark Ticket as Distilled

```bash
run_write_sql "$SCRIPTS/mark_ticket_distilled.sql" \
  SQL_PARAM_ticket_id="{{ticket_id}}" \
  SQL_PARAM_workspace_id="{{workspace_id}}" \
  SQL_PARAM_memory_count="{{count}}" \
  SQL_PARAM_distill_version="{{distill_version}}" \
  SQL_PARAM_distiller_type="{{distiller_type}}" \
  SQL_PARAM_distiller_id="{{distiller_id}}" \
  SQL_PARAM_distiller_name="{{distiller_name}}"
```

## Memory Types

| Type | Description | Example |
|------|-------------|---------|
| `error_resolution` | How a specific error was resolved | ORA-01555 fix: increase undo_retention |
| `failure_scenario` | Failure pattern and root cause | High undo usage during ETL batch |
| `success_playbook` | Step-by-step success guide | Structured fault/preconditions/steps/validation/rollback |
| `environment_fact` | Environment-specific knowledge | ETL runs at 2 AM daily |
| `human_correction` | Human corrections to agent behavior | Don't use KILL SESSION, use ALTER SYSTEM KILL SESSION |
| `preference` | User's preferred approaches | Prefer ROLLBACK over KILL SESSION |

## Additional Resources

- For the complete distillation prompt, see `$REFERENCE/distillation-prompt.md`
