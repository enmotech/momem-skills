-- Get complete ticket transcript with all related data
-- Used by: memory-distillation skill Step 2
-- moclaw renamed issue->ticket, comment->ticket_comment,
-- agent_task_queue->agent_task, task_message->agent_task_message.
-- status/creator_type/assignee_type/author_type are now INT enums, mapped to
-- strings via CASE so the transcript shape stays stable. ticket_comment has no
-- workspace_id column, so it is selected as NULL.

-- Main ticket info
SELECT
    'ticket' as record_type,
    i.id,
    i.workspace_id,
    i.project_id,
    i.title,
    i.description,
    i.number,
    CASE i.status WHEN 4 THEN 'done' WHEN 2 THEN 'in_progress' WHEN 6 THEN 'cancelled' ELSE i.status::text END AS status,
    CASE i.creator_type WHEN 0 THEN 'member' WHEN 1 THEN 'agent' ELSE i.creator_type::text END AS creator_type,
    i.creator_id::text,
    CASE i.assignee_type WHEN 0 THEN 'member' WHEN 1 THEN 'agent' WHEN 3 THEN 'team' ELSE COALESCE(i.assignee_type::text, '') END AS assignee_type,
    i.assignee_id::text,
    i.created_at,
    i.updated_at,
    NULL as content,
    NULL as author_type,
    NULL as author_id
FROM ticket i
WHERE i.id = :ticket_id

UNION ALL

-- Comments (human interactions)
SELECT
    'comment' as record_type,
    c.id,
    NULL as workspace_id,
    NULL as project_id,
    NULL as title,
    NULL as description,
    NULL as number,
    NULL as status,
    NULL as creator_type,
    NULL as creator_id,
    NULL as assignee_type,
    NULL as assignee_id,
    c.created_at,
    NULL as updated_at,
    c.content,
    CASE c.author_type WHEN 0 THEN 'member' WHEN 1 THEN 'agent' ELSE c.author_type::text END AS author_type,
    c.author_id::text
FROM ticket_comment c
WHERE c.ticket_id = :ticket_id

UNION ALL

-- Agent tasks
SELECT
    'task' as record_type,
    atq.id,
    NULL as workspace_id,
    NULL as project_id,
    NULL as title,
    atq.result::text as description,
    NULL as number,
    CASE atq.status WHEN 3 THEN 'completed' WHEN 4 THEN 'failed' WHEN 5 THEN 'cancelled' ELSE atq.status::text END AS status,
    NULL as creator_type,
    atq.agent_id::text as creator_id,
    NULL as assignee_type,
    NULL as assignee_id,
    atq.created_at,
    atq.completed_at as updated_at,
    atq.trigger_summary as content,
    NULL as author_type,
    NULL as author_id
FROM agent_task atq
WHERE atq.ticket_id = :ticket_id

UNION ALL

-- Task messages (agent reasoning/tool calls)
SELECT
    'message' as record_type,
    tm.id,
    NULL as workspace_id,
    NULL as project_id,
    NULL as title,
    NULL as description,
    NULL as number,
    NULL as status,
    tm.type as creator_type,
    tm.tool as creator_id,
    NULL as assignee_type,
    NULL as assignee_id,
    tm.created_at,
    NULL as updated_at,
    tm.content,
    NULL as author_type,
    NULL as author_id
FROM agent_task_message tm
JOIN agent_task atq ON tm.agent_task_id = atq.id
WHERE atq.ticket_id = :ticket_id

ORDER BY created_at ASC;
