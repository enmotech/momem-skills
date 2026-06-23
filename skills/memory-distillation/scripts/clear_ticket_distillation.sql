-- Clear distillation status and memories for a ticket (for --force re-distillation)
-- Used by: momem store --force

-- Step 1: Delete memories for this ticket
DELETE FROM momem.agent_memories
WHERE metadata->>'ticket_id' = :ticket_id;

-- Step 2: Delete distillation status
DELETE FROM momem.ticket_distillation_status
WHERE ticket_id = :ticket_id;
