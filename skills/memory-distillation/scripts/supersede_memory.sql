-- Supersede existing memory of same type AND same profile_id
-- Used by: memory-distillation skill Step 4 (for environment_fact and preference types)
-- Important: Only supersede memories within the same profile to prevent cross-environment contamination

WITH updated AS (
  UPDATE agent_memories
  SET superseded_by = :new_memory_id
  WHERE workspace_id = :workspace_id
    AND memory_type = :memory_type
    AND NULLIF(:profile_id, '') IS NOT NULL
    AND profile_id = NULLIF(:profile_id, '')
    AND superseded_by IS NULL
    AND id != :new_memory_id
    AND (:project_id IS NULL OR metadata->>'project_id' = :project_id)
  RETURNING id
)
SELECT COUNT(*) as superseded_count
FROM updated;
