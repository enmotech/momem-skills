-- Get undistilled tickets with optional filters
-- Used by: memory-distillation skill Step 1
-- moclaw renamed issue->ticket, agent_task_queue->agent_task,
-- task_message->agent_task_message; status is now an INT enum (4 = done).

SELECT
    i.id AS ticket_id,
    i.workspace_id,
    i.project_id,
    i.title,
    i.description,
    i.number,
    CASE i.status WHEN 4 THEN 'done' WHEN 2 THEN 'in_progress' WHEN 6 THEN 'cancelled' ELSE i.status::text END AS status,
    i.created_at,
    i.updated_at
FROM ticket i
LEFT JOIN momem.ticket_distillation_status tds ON i.id = tds.ticket_id
WHERE i.workspace_id = :workspace_id
  AND i.status = 4
  AND tds.ticket_id IS NULL  -- Not yet distilled
  -- Optional filters
  AND (:ticket_id IS NULL OR i.id = :ticket_id)
  AND (:since IS NULL OR i.created_at >= :since)
  -- Agent filter (via agent_task)
  AND (:agent_id IS NULL OR EXISTS (
      SELECT 1 FROM agent_task atq
      WHERE atq.ticket_id = i.id AND atq.agent_id = :agent_id
  ))
  -- Agent name filter
  AND (:agent_name IS NULL OR EXISTS (
      SELECT 1 FROM agent_task atq
      JOIN agent a ON atq.agent_id = a.id
      WHERE atq.ticket_id = i.id AND a.name = :agent_name
  ))
  -- Skill filter (via agent_task_message)
  AND (:skill_name IS NULL OR EXISTS (
      SELECT 1 FROM agent_task atq
      JOIN agent_task_message tm ON tm.agent_task_id = atq.id
      WHERE atq.ticket_id = i.id
        AND tm.tool = 'Skill'
        AND tm.input->>'skill' = :skill_name
  ))
  -- Project filter
  AND (:project_id IS NULL OR i.project_id = :project_id)
ORDER BY i.created_at DESC;
