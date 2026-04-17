-- =============================================================================
-- Migration 020: add position column to workout_plans for user-defined ordering.
-- =============================================================================

ALTER TABLE public.workout_plans
  ADD COLUMN IF NOT EXISTS position INT NOT NULL DEFAULT 0;

-- Back-fill positions based on creation order so existing plans keep their order.
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at ASC) - 1 AS pos
  FROM public.workout_plans
)
UPDATE public.workout_plans wp
SET position = r.pos
FROM ranked r
WHERE wp.id = r.id;
