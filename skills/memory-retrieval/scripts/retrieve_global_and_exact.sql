-- Retrieve global injection + exact error_code match
-- Used by: memory-retrieval skill Step 2
-- Combines two queries into one using UNION ALL

-- Global injection: environment_fact and preference (always injected)
SELECT 
    id,
    workspace_id,
    agent_id,
    profile_id,
    db_type,
    memory_type,
    content,
    metadata,
    created_at,
    'global' as match_type,
    0.0 as similarity,
    1.0 as scope_weight
FROM momem.agent_memories
WHERE workspace_id = :workspace_id
  AND memory_type IN ('environment_fact', 'preference')
  AND superseded_by IS NULL
  AND (profile_id = :profile_id OR profile_id IS NULL)
  AND (:project_id IS NULL OR metadata->>'project_id' = :project_id)

UNION ALL

-- Exact match: error_resolution with matching error_code
SELECT 
    id,
    workspace_id,
    agent_id,
    profile_id,
    db_type,
    memory_type,
    content,
    metadata,
    created_at,
    'exact' as match_type,
    0.0 as similarity,
    1.0 as scope_weight
FROM momem.agent_memories
WHERE workspace_id = :workspace_id
  AND memory_type = 'error_resolution'
  AND metadata->>'error_code' = ANY(string_to_array(:query, ' '))
  AND superseded_by IS NULL
  AND (profile_id = :profile_id OR profile_id IS NULL)
  AND (:project_id IS NULL OR metadata->>'project_id' = :project_id)

ORDER BY memory_type, created_at DESC;
