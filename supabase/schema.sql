-- =============================================================================
-- Shift — gym tracker schema
-- Run this in the Supabase SQL editor (Dashboard → SQL → New query → paste → Run)
-- =============================================================================

-- Extensions ------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- Profiles --------------------------------------------------------------------
-- Mirrors auth.users with the bits we want to expose to the app.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  unit_system text not null default 'metric' check (unit_system in ('metric','imperial')),
  created_at timestamptz not null default now()
);

-- Auto-create a profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Muscle groups ---------------------------------------------------------------
create table if not exists public.muscle_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique
);

-- Exercises -------------------------------------------------------------------
create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  instructions text,
  primary_muscle_id uuid not null references public.muscle_groups(id),
  secondary_muscle_ids uuid[] not null default '{}',
  equipment text,
  is_built_in boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  unique (slug, created_by)
);

create index if not exists idx_exercises_primary_muscle on public.exercises(primary_muscle_id);

-- Workout plans ---------------------------------------------------------------
create table if not exists public.workout_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.plan_exercises (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.workout_plans(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id),
  position int not null,
  target_sets int not null default 3,
  target_reps int,
  target_weight numeric,
  rest_seconds int
);

create index if not exists idx_plan_exercises_plan on public.plan_exercises(plan_id);

-- Workout sessions ------------------------------------------------------------
create table if not exists public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid references public.workout_plans(id) on delete set null,
  name text not null,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  notes text
);

create index if not exists idx_sessions_user_started on public.workout_sessions(user_id, started_at desc);

create table if not exists public.session_sets (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id),
  set_number int not null,
  reps int not null,
  weight numeric,
  rpe numeric,
  completed_at timestamptz not null default now()
);

create index if not exists idx_sets_session on public.session_sets(session_id);

-- =============================================================================
-- Row-level security
-- =============================================================================

alter table public.profiles enable row level security;
alter table public.muscle_groups enable row level security;
alter table public.exercises enable row level security;
alter table public.workout_plans enable row level security;
alter table public.plan_exercises enable row level security;
alter table public.workout_sessions enable row level security;
alter table public.session_sets enable row level security;

-- Profiles: each user sees + edits their own row.
drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read" on public.profiles
  for select using (auth.uid() = id);
drop policy if exists "profiles self write" on public.profiles;
create policy "profiles self write" on public.profiles
  for update using (auth.uid() = id);

-- Muscle groups: readable by anyone signed in (built-in reference data).
drop policy if exists "muscle groups read all" on public.muscle_groups;
create policy "muscle groups read all" on public.muscle_groups
  for select using (auth.role() = 'authenticated');

-- Exercises: built-in readable by all authenticated users.
-- Custom (created_by = me) readable + writable by me.
drop policy if exists "exercises read" on public.exercises;
create policy "exercises read" on public.exercises
  for select using (
    auth.role() = 'authenticated' and (is_built_in or created_by = auth.uid())
  );
drop policy if exists "exercises insert own" on public.exercises;
create policy "exercises insert own" on public.exercises
  for insert with check (created_by = auth.uid() and is_built_in = false);
drop policy if exists "exercises update own" on public.exercises;
create policy "exercises update own" on public.exercises
  for update using (created_by = auth.uid());
drop policy if exists "exercises delete own" on public.exercises;
create policy "exercises delete own" on public.exercises
  for delete using (created_by = auth.uid());

-- Workout plans: owner-only.
drop policy if exists "plans owner all" on public.workout_plans;
create policy "plans owner all" on public.workout_plans
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "plan exercises owner all" on public.plan_exercises;
create policy "plan exercises owner all" on public.plan_exercises
  for all using (
    exists (select 1 from public.workout_plans p where p.id = plan_id and p.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.workout_plans p where p.id = plan_id and p.user_id = auth.uid())
  );

-- Sessions + sets: owner-only.
drop policy if exists "sessions owner all" on public.workout_sessions;
create policy "sessions owner all" on public.workout_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "sets owner all" on public.session_sets;
create policy "sets owner all" on public.session_sets
  for all using (
    exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = auth.uid())
  );

-- =============================================================================
-- Seed data
-- =============================================================================

insert into public.muscle_groups (name, slug) values
  ('Chest', 'chest'),
  ('Back', 'back'),
  ('Shoulders', 'shoulders'),
  ('Biceps', 'biceps'),
  ('Triceps', 'triceps'),
  ('Forearms', 'forearms'),
  ('Quads', 'quads'),
  ('Hamstrings', 'hamstrings'),
  ('Glutes', 'glutes'),
  ('Calves', 'calves'),
  ('Core', 'core')
on conflict (slug) do nothing;

-- Helper: insert exercises by muscle slug
do $$
declare
  m_chest uuid := (select id from public.muscle_groups where slug = 'chest');
  m_back uuid := (select id from public.muscle_groups where slug = 'back');
  m_shoulders uuid := (select id from public.muscle_groups where slug = 'shoulders');
  m_biceps uuid := (select id from public.muscle_groups where slug = 'biceps');
  m_triceps uuid := (select id from public.muscle_groups where slug = 'triceps');
  m_quads uuid := (select id from public.muscle_groups where slug = 'quads');
  m_hams uuid := (select id from public.muscle_groups where slug = 'hamstrings');
  m_glutes uuid := (select id from public.muscle_groups where slug = 'glutes');
  m_calves uuid := (select id from public.muscle_groups where slug = 'calves');
  m_core uuid := (select id from public.muscle_groups where slug = 'core');
begin
  insert into public.exercises (name, slug, primary_muscle_id, equipment, is_built_in) values
    ('Barbell Bench Press', 'barbell-bench-press', m_chest, 'Barbell', true),
    ('Incline Dumbbell Press', 'incline-dumbbell-press', m_chest, 'Dumbbell', true),
    ('Push-Up', 'push-up', m_chest, 'Bodyweight', true),
    ('Cable Fly', 'cable-fly', m_chest, 'Cable', true),
    ('Deadlift', 'deadlift', m_back, 'Barbell', true),
    ('Pull-Up', 'pull-up', m_back, 'Bodyweight', true),
    ('Barbell Row', 'barbell-row', m_back, 'Barbell', true),
    ('Lat Pulldown', 'lat-pulldown', m_back, 'Cable', true),
    ('Seated Cable Row', 'seated-cable-row', m_back, 'Cable', true),
    ('Overhead Press', 'overhead-press', m_shoulders, 'Barbell', true),
    ('Dumbbell Shoulder Press', 'dumbbell-shoulder-press', m_shoulders, 'Dumbbell', true),
    ('Lateral Raise', 'lateral-raise', m_shoulders, 'Dumbbell', true),
    ('Face Pull', 'face-pull', m_shoulders, 'Cable', true),
    ('Barbell Curl', 'barbell-curl', m_biceps, 'Barbell', true),
    ('Dumbbell Curl', 'dumbbell-curl', m_biceps, 'Dumbbell', true),
    ('Hammer Curl', 'hammer-curl', m_biceps, 'Dumbbell', true),
    ('Tricep Pushdown', 'tricep-pushdown', m_triceps, 'Cable', true),
    ('Skullcrusher', 'skullcrusher', m_triceps, 'Barbell', true),
    ('Dips', 'dips', m_triceps, 'Bodyweight', true),
    ('Back Squat', 'back-squat', m_quads, 'Barbell', true),
    ('Front Squat', 'front-squat', m_quads, 'Barbell', true),
    ('Leg Press', 'leg-press', m_quads, 'Machine', true),
    ('Leg Extension', 'leg-extension', m_quads, 'Machine', true),
    ('Romanian Deadlift', 'romanian-deadlift', m_hams, 'Barbell', true),
    ('Lying Leg Curl', 'lying-leg-curl', m_hams, 'Machine', true),
    ('Hip Thrust', 'hip-thrust', m_glutes, 'Barbell', true),
    ('Bulgarian Split Squat', 'bulgarian-split-squat', m_glutes, 'Dumbbell', true),
    ('Standing Calf Raise', 'standing-calf-raise', m_calves, 'Machine', true),
    ('Plank', 'plank', m_core, 'Bodyweight', true),
    ('Hanging Leg Raise', 'hanging-leg-raise', m_core, 'Bodyweight', true)
  on conflict (slug, created_by) do nothing;
end $$;
