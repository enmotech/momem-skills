-- Mark a ticket as distilled
-- Used by: momem store

INSERT INTO ticket_distillation_status 
(ticket_id, workspace_id, distilled_at, memory_count, distill_version, distillation_method, metadata)
VALUES (
    :ticket_id,
    :workspace_id,
    now(),
    :memory_count,
    :distill_version,
    'skill',
    jsonb_strip_nulls(jsonb_build_object(
        'tool', 'skill',
        'skill_name', 'memory-distillation',
        'distiller', CASE
            WHEN NULLIF(:distiller_type, '') IS NOT NULL OR NULLIF(:distiller_id, '') IS NOT NULL OR NULLIF(:distiller_name, '') IS NOT NULL THEN
                jsonb_strip_nulls(jsonb_build_object(
                    'type', NULLIF(:distiller_type, ''),
                    'id', NULLIF(:distiller_id, ''),
                    'name', NULLIF(:distiller_name, '')
                ))
            ELSE NULL
        END
    ))
)
ON CONFLICT (ticket_id) DO UPDATE SET
    distilled_at = now(),
    memory_count = :memory_count,
    distill_version = :distill_version,
    distillation_method = 'skill',
    metadata = jsonb_strip_nulls(jsonb_build_object(
        'tool', 'skill',
        'skill_name', 'memory-distillation',
        'distiller', CASE
            WHEN NULLIF(:distiller_type, '') IS NOT NULL OR NULLIF(:distiller_id, '') IS NOT NULL OR NULLIF(:distiller_name, '') IS NOT NULL THEN
                jsonb_strip_nulls(jsonb_build_object(
                    'type', NULLIF(:distiller_type, ''),
                    'id', NULLIF(:distiller_id, ''),
                    'name', NULLIF(:distiller_name, '')
                ))
            ELSE NULL
        END
    ));
