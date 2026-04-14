-- =============================================================================
-- Migration 009: consolidate the exercise catalog onto a single source.
--
-- After three rounds of imports (free-exercise-db → everkinetic →
-- ExerciseDB) the table accumulated rows from each source because the
-- earlier cleanup migrations only removed one prefix at a time. This
-- migration is the catch-all: delete every built-in row whose
-- image_url doesn't point at our own exercise-images storage bucket
-- (the one populated by the ExerciseDB importer), with one exception
-- — rows that are still referenced by a logged session_set are left
-- alone so existing workout history doesn't end up with dangling
-- exercise_id references.
--
-- Idempotent: matches by image_url, so re-running against an already
-- consolidated DB is a no-op.
-- =============================================================================

delete from public.exercises
where is_built_in = true
  and (
    image_url is null
    or image_url not like '%/storage/v1/object/public/exercise-images/%'
  )
  and id not in (
    select distinct exercise_id
      from public.session_sets
     where exercise_id is not null
  );
