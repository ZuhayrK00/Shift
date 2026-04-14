-- =============================================================================
-- Migration 003: reconcile public.profiles columns.
--
-- The remote already had a `public.profiles` table when migration 002 ran
-- (created earlier via the dashboard or a Supabase quickstart), so the
-- `CREATE TABLE IF NOT EXISTS` in 002 was a no-op and the new columns
-- weren't applied. This migration adds them idempotently.
-- =============================================================================

alter table public.profiles
  add column if not exists name text,
  add column if not exists age integer,
  add column if not exists weight real,
  add column if not exists profile_picture_url text,
  add column if not exists settings jsonb,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- Backfill any rows missing the new fields with sensible defaults so the
-- NOT NULL constraints below don't blow up.
update public.profiles
set settings = '{
  "weight_unit": "kg",
  "default_weight_increment": 2.5,
  "distance_unit": "km",
  "week_starts_on": "monday",
  "theme": "dark"
}'::jsonb
where settings is null;

update public.profiles set created_at = now() where created_at is null;
update public.profiles set updated_at = now() where updated_at is null;

-- Defaults + NOT NULL on the bookkeeping columns, matching what 002 wanted.
alter table public.profiles
  alter column settings set default '{
    "weight_unit": "kg",
    "default_weight_increment": 2.5,
    "distance_unit": "km",
    "week_starts_on": "monday",
    "theme": "dark"
  }'::jsonb,
  alter column settings set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

-- Range / positivity checks. Wrapped in DO block so they're idempotent.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'profiles_age_check'
       and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_age_check
      check (age is null or (age between 0 and 150));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'profiles_weight_check'
       and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_weight_check
      check (weight is null or weight > 0);
  end if;
end $$;
