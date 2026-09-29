-- Metadata and compatibility layer. Content import is prepared separately,
-- never published as a redistributable dataset in this repository.
begin;
alter table public.exercises
  add column if not exists catalogue_source text,
  add column if not exists source_id text,
  add column if not exists primary_muscles text[],
  add column if not exists secondary_muscles text[],
  add column if not exists form_tips text[],
  add column if not exists secondary_equipment text[],
  add column if not exists is_archived boolean not null default false;
alter table public.exercises drop constraint if exists exercises_level_check;
alter table public.exercises add constraint exercises_level_check
  check (level is null or level in ('beginner','intermediate','advanced','expert'));
alter table public.exercises drop constraint if exists exercises_force_check;
alter table public.exercises add constraint exercises_force_check
  check (force is null or force in ('push','pull','static','dynamic'));

create table if not exists public.exercise_catalogue_redirects (
  old_id uuid primary key,
  new_id uuid not null references public.exercises(id)
);
alter table public.exercise_catalogue_redirects enable row level security;
grant select on public.exercise_catalogue_redirects to authenticated;
drop policy if exists "read exercise redirects" on public.exercise_catalogue_redirects;
create policy "read exercise redirects" on public.exercise_catalogue_redirects
  for select to authenticated using (true);

-- Old TestFlight clients/offline queues can still send a retired ID. Resolve
-- confirmed equivalents before the foreign key is checked. No heuristic swaps.
create or replace function public.redirect_catalogue_exercise()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.exercise_id := coalesce((select r.new_id from public.exercise_catalogue_redirects r
                               where r.old_id = new.exercise_id), new.exercise_id);
  return new;
end;
$$;
revoke all on function public.redirect_catalogue_exercise() from public;
drop trigger if exists redirect_catalogue_exercise on public.plan_exercises;
create trigger redirect_catalogue_exercise before insert or update of exercise_id on public.plan_exercises
  for each row execute function public.redirect_catalogue_exercise();
drop trigger if exists redirect_catalogue_exercise on public.session_sets;
create trigger redirect_catalogue_exercise before insert or update of exercise_id on public.session_sets
  for each row execute function public.redirect_catalogue_exercise();
drop trigger if exists redirect_catalogue_exercise on public.exercise_goals;
create trigger redirect_catalogue_exercise before insert or update of exercise_id on public.exercise_goals
  for each row execute function public.redirect_catalogue_exercise();
create index if not exists idx_exercises_catalogue_active
  on public.exercises(catalogue_source, is_archived, name) where is_built_in;
commit;
