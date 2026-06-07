-- Update occurrence_count, last_seen_at, and provenance for an existing memory
-- Used by: memory-distillation skill Step 4 (when similar memory found)

WITH issue_primary AS (
    SELECT CASE WHEN assignee_type = 'agent' THEN assignee_id::text ELSE NULL END AS primary_agent_id
    FROM issue
    WHERE id = :ticket_id
),
task_agents AS (
    SELECT agent_id::text AS agent_id, MIN(created_at) AS first_seen
    FROM agent_task_queue
    WHERE issue_id = :ticket_id
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
incoming_provenance AS (
    SELECT
        COALESCE(array_agg(agent_id ORDER BY priority, first_seen), ARRAY[]::text[]) AS agent_ids,
        :ticket_id::text AS ticket_id
    FROM candidate_agents
),
current_metadata AS (
    SELECT metadata
    FROM agent_memories
    WHERE id = :memory_id
),
merged_agent_ids AS (
    SELECT COALESCE(array_agg(agent_id ORDER BY first_ord), ARRAY[]::text[]) AS agent_ids
    FROM (
        SELECT agent_id, MIN(ord) AS first_ord
        FROM (
            SELECT value AS agent_id, ord::int AS ord
            FROM current_metadata,
                jsonb_array_elements_text(COALESCE(metadata->'agent_ids', '[]'::jsonb)) WITH ORDINALITY AS existing(value, ord)

            UNION ALL

            SELECT agent_id, 100000 + ord::int AS ord
            FROM incoming_provenance,
                unnest(agent_ids) WITH ORDINALITY AS incoming(agent_id, ord)
        ) all_agents
        WHERE agent_id <> ''
        GROUP BY agent_id
    ) deduped_agents
),
merged_ticket_ids AS (
    SELECT COALESCE(array_agg(ticket_id ORDER BY first_ord), ARRAY[]::text[]) AS ticket_ids
    FROM (
        SELECT ticket_id, MIN(ord) AS first_ord
        FROM (
            SELECT metadata->>'ticket_id' AS ticket_id, 0 AS ord
            FROM current_metadata
            WHERE metadata->>'ticket_id' IS NOT NULL

            UNION ALL

            SELECT value AS ticket_id, ord::int AS ord
            FROM current_metadata,
                jsonb_array_elements_text(COALESCE(metadata->'ticket_ids', '[]'::jsonb)) WITH ORDINALITY AS existing(value, ord)

            UNION ALL

            SELECT ticket_id, 100000 AS ord
            FROM incoming_provenance
        ) all_tickets
        WHERE ticket_id <> ''
        GROUP BY ticket_id
    ) deduped_tickets
)
UPDATE agent_memories
SET
    occurrence_count = occurrence_count + 1,
    last_seen_at = now(),
    metadata = jsonb_set(
        jsonb_set(metadata, '{agent_ids}', to_jsonb(merged_agent_ids.agent_ids), true),
        '{ticket_ids}', to_jsonb(merged_ticket_ids.ticket_ids), true
    )
FROM merged_agent_ids, merged_ticket_ids
WHERE id = :memory_id
RETURNING id, occurrence_count, last_seen_at;
