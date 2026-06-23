-- Retrieve similar memories using vector search with scope weighting and frequency boost
-- Used by: memory-retrieval skill Step 3

SELECT *
FROM (
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
      last_seen_at,
      occurrence_count,
      'similar' as match_type,
      1 - (embedding <=> :query_embedding::vector) as similarity,
      CASE
        WHEN profile_id = :profile_id THEN 1.0
        WHEN db_type = :db_type THEN 0.6
        ELSE 0.3
      END as scope_weight,
      -- Frequency boost: log(occurrence_count + 1) gives higher weight to frequently observed patterns
      ln(occurrence_count + 1) as frequency_boost
  FROM momem.agent_memories
  WHERE workspace_id = :workspace_id
    AND memory_type = ANY(string_to_array(:memory_types, ','))
    AND superseded_by IS NULL
    AND (profile_id = :profile_id OR profile_id IS NULL)
    AND (db_type = :db_type OR db_type IS NULL)
    AND (:project_id IS NULL OR metadata->>'project_id' = :project_id)
) ranked
ORDER BY similarity * scope_weight * frequency_boost DESC
LIMIT :top_k;
