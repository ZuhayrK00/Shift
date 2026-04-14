-- workout_plans and plan_exercises.
-- The local SQLite cache already has these tables (added in SCHEMA_VERSION = 7).
-- This migration brings Postgres into sync.

create table if not exists public.workout_plans (
  id          uuid        primary key,
  user_id     uuid        not null references auth.users(id) on delete cascade,
  name        text        not null,
  notes       text,
  created_at  timestamptz not null default now()
);

alter table public.workout_plans enable row level security;

create policy "Users can manage their own plans"
  on public.workout_plans
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.plan_exercises (
  id            uuid    primary key,
  plan_id       uuid    not null references public.workout_plans(id) on delete cascade,
  exercise_id   uuid    not null,
  position      integer not null,
  target_sets   integer not null,
  target_reps   integer,
  target_weight real,
  rest_seconds  integer
);

alter table public.plan_exercises enable row level security;

create policy "Users can manage exercises in their own plans"
  on public.plan_exercises
  for all
  using (
    exists (
      select 1 from public.workout_plans wp
      where  wp.id = plan_id
      and    wp.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workout_plans wp
      where  wp.id = plan_id
      and    wp.user_id = auth.uid()
    )
  );
