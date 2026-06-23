-- Check if a similar memory already exists (for deduplication)
-- Used by: memory-distillation skill Step 4 (before storing)
-- Returns: existing memory id if similarity > threshold, otherwise empty

SELECT 
    id,
    content,
    memory_type,
    metadata,
    1 - (embedding <=> :new_embedding::vector) as similarity
FROM momem.agent_memories
WHERE workspace_id = :workspace_id
  AND memory_type = :memory_type
  AND superseded_by IS NULL
  AND NULLIF(:profile_id, '') IS NOT NULL
  AND profile_id = NULLIF(:profile_id, '')
  AND (:project_id IS NULL OR metadata->>'project_id' = :project_id)
  AND (:error_code IS NULL OR :memory_type <> 'error_resolution' OR metadata->>'error_code' = :error_code)
  AND 1 - (embedding <=> :new_embedding::vector) >
    CASE
      WHEN :memory_type = 'preference' THEN LEAST(COALESCE(:similarity_threshold, 0.85), 0.80)
      WHEN :memory_type = 'success_playbook' THEN LEAST(COALESCE(:similarity_threshold, 0.85), 0.82)
      ELSE COALESCE(:similarity_threshold, 0.85)
    END
ORDER BY similarity DESC
LIMIT 1;
