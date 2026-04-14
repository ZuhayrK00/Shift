-- =============================================================================
-- Migration 006: enrich the exercises catalog with image URLs and richer
-- metadata pulled from the free-exercise-db dataset.
--
-- All additive — every new column is nullable and has no default
-- behaviour change for existing rows. The actual data is loaded by the
-- `npm run import-exercises` script which runs against the Supabase
-- service-role API and is safe to re-run (uses upserts).
--
-- We also seed the standard 17 muscle groups used by free-exercise-db
-- so the import script can resolve them by slug without needing to
-- create them inline. Existing muscle_groups rows are untouched.
-- =============================================================================

-- ----- Exercise columns ----------------------------------------------------

alter table public.exercises
  add column if not exists image_url text,
  add column if not exists secondary_image_url text,
  add column if not exists level text,
  add column if not exists force text,
  add column if not exists mechanic text,
  add column if not exists category text,
  add column if not exists instructions_steps jsonb;

-- Light validation. The free-exercise-db enums map cleanly to these.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'exercises_level_check'
       and conrelid = 'public.exercises'::regclass
  ) then
    alter table public.exercises
      add constraint exercises_level_check
      check (level is null or level in ('beginner', 'intermediate', 'expert'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'exercises_force_check'
       and conrelid = 'public.exercises'::regclass
  ) then
    alter table public.exercises
      add constraint exercises_force_check
      check (force is null or force in ('push', 'pull', 'static'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'exercises_mechanic_check'
       and conrelid = 'public.exercises'::regclass
  ) then
    alter table public.exercises
      add constraint exercises_mechanic_check
      check (mechanic is null or mechanic in ('compound', 'isolation'));
  end if;
end $$;

-- ----- Standard muscle groups (idempotent upsert) -------------------------

insert into public.muscle_groups (id, name, slug)
values
  (gen_random_uuid(), 'Abdominals', 'abdominals'),
  (gen_random_uuid(), 'Abductors', 'abductors'),
  (gen_random_uuid(), 'Adductors', 'adductors'),
  (gen_random_uuid(), 'Biceps', 'biceps'),
  (gen_random_uuid(), 'Calves', 'calves'),
  (gen_random_uuid(), 'Chest', 'chest'),
  (gen_random_uuid(), 'Forearms', 'forearms'),
  (gen_random_uuid(), 'Glutes', 'glutes'),
  (gen_random_uuid(), 'Hamstrings', 'hamstrings'),
  (gen_random_uuid(), 'Lats', 'lats'),
  (gen_random_uuid(), 'Lower Back', 'lower-back'),
  (gen_random_uuid(), 'Middle Back', 'middle-back'),
  (gen_random_uuid(), 'Neck', 'neck'),
  (gen_random_uuid(), 'Quadriceps', 'quadriceps'),
  (gen_random_uuid(), 'Shoulders', 'shoulders'),
  (gen_random_uuid(), 'Traps', 'traps'),
  (gen_random_uuid(), 'Triceps', 'triceps')
on conflict (slug) do update set name = excluded.name;
