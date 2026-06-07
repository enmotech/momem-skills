-- Get complete ticket transcript with all related data
-- Used by: memory-distillation skill Step 2

-- Main ticket info
SELECT 
    'ticket' as record_type,
    i.id,
    i.workspace_id,
    i.project_id,
    i.title,
    i.description,
    i.number,
    i.status,
    i.creator_type,
    i.creator_id::text,
    i.assignee_type,
    i.assignee_id::text,
    i.created_at,
    i.updated_at,
    NULL as content,
    NULL as author_type,
    NULL as author_id
FROM issue i
WHERE i.id = :ticket_id

UNION ALL

-- Comments (human interactions)
SELECT 
    'comment' as record_type,
    c.id,
    c.workspace_id,
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
    c.author_type,
    c.author_id::text
FROM comment c
WHERE c.issue_id = :ticket_id

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
    atq.status,
    NULL as creator_type,
    atq.agent_id::text as creator_id,
    NULL as assignee_type,
    NULL as assignee_id,
    atq.created_at,
    atq.completed_at as updated_at,
    atq.trigger_summary as content,
    NULL as author_type,
    NULL as author_id
FROM agent_task_queue atq
WHERE atq.issue_id = :ticket_id

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
FROM task_message tm
JOIN agent_task_queue atq ON tm.task_id = atq.id
WHERE atq.issue_id = :ticket_id

ORDER BY created_at ASC;
