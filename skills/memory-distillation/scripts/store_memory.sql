-- Store a NEW distilled memory with embedding (no similar memory found)
-- Used by: memory-distillation skill Step 4 (only when no similar memory exists)

-- moclaw renamed issue->ticket and agent_task_queue->agent_task; assignee_type
-- is now an INT enum (1 = agent) and the task FK is ticket_id.
WITH issue_primary AS (
    SELECT CASE WHEN assignee_type = 1 THEN assignee_id::text ELSE NULL END AS primary_agent_id
    FROM ticket
    WHERE id = :ticket_id
),
task_agents AS (
    SELECT agent_id::text AS agent_id, MIN(created_at) AS first_seen
    FROM agent_task
    WHERE ticket_id = :ticket_id
      AND agent_id IS NOT NULL
    GROUP BY agent_id
),
candidate_agents AS (
    SELECT primary_agent_id AS agent_id, 'epoch'::timestamptz AS first_seen, 0 AS priority
    FROM issue_primary
    WHERE primary_agent_id IS NOT NULL

    UNION ALL

    SELECT t.agent_id, t.first_seen, 1 AS priority
    FROM task_agents t
    LEFT JOIN issue_primary p ON true
    WHERE p.primary_agent_id IS NULL OR t.agent_id <> p.primary_agent_id
),
provenance AS (
    SELECT
        COALESCE((array_agg(agent_id ORDER BY priority, first_seen))[1], '') AS primary_agent_id,
        COALESCE(array_agg(agent_id ORDER BY priority, first_seen), ARRAY[]::text[]) AS agent_ids
    FROM candidate_agents
)
INSERT INTO agent_memories
(workspace_id, agent_id, profile_id, db_type, memory_type, content, embedding, metadata, occurrence_count, last_seen_at)
SELECT
    :workspace_id,
    NULLIF(primary_agent_id, '')::uuid,
    NULLIF(:profile_id, ''),
    NULLIF(:db_type, ''),
    :memory_type,
    :content,
    :embedding::vector,  -- vector(1536) from Embedding API
    jsonb_build_object(
        'ticket_id', :ticket_id,
        'ticket_ids', jsonb_build_array(:ticket_id),
        'project_id', NULLIF(:project_id, ''),
        'error_code', :error_code,
        'agent_ids', to_jsonb(agent_ids),
        'source', 'distill',
        'distill_version', :distill_version
    ),
    1,           -- occurrence_count: 初始值为 1
    now()        -- last_seen_at: 当前时间
FROM provenance
RETURNING id;
