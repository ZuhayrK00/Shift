-- =============================================================================
-- Migration 004: tag each session_sets row with a set_type.
--
-- Used by the workout UI to render the badge as W (warmup), D (drop set),
-- F (failure) instead of the numeric set number. Defaults to 'normal'
-- so existing rows keep showing the number.
-- =============================================================================

alter table public.session_sets
  add column if not exists set_type text not null default 'normal';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'session_sets_set_type_check'
       and conrelid = 'public.session_sets'::regclass
  ) then
    alter table public.session_sets
      add constraint session_sets_set_type_check
      check (set_type in ('normal', 'warmup', 'drop', 'failure'));
  end if;
end $$;
