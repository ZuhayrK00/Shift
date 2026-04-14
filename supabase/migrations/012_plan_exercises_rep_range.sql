-- Replace target_reps with target_reps_min / target_reps_max on plan_exercises.

alter table public.plan_exercises
  add column if not exists target_reps_min integer,
  add column if not exists target_reps_max integer;

-- Preserve any existing data before dropping the old column.
update public.plan_exercises
  set target_reps_min = target_reps
  where target_reps is not null;

alter table public.plan_exercises
  drop column if exists target_reps;
