-- =============================================================================
-- Migration 007: drop the free-exercise-db rows in favour of everkinetic.
--
-- The free-exercise-db import shipped photo-real images that didn't fit
-- the design we want; we're switching to everkinetic for the stylised
-- anatomical illustrations with target-muscle highlighting.
--
-- Only delete rows that aren't referenced by any logged session set, so
-- existing workout history doesn't end up with dangling exercise_id
-- references. Anything still in use stays put — the user can clean up
-- duplicates manually after the new import lands.
--
-- Idempotent: matches by image_url prefix, so re-running the migration
-- against a DB that's already clean is a no-op.
-- =============================================================================

delete from public.exercises
where image_url like 'https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db%'
  and id not in (
    select distinct exercise_id
      from public.session_sets
     where exercise_id is not null
  );
