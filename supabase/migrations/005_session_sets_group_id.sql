-- =============================================================================
-- Migration 005: tag session_sets with a group_id so multiple exercises
-- can be grouped as a superset / tri-set / giant set.
--
-- Sets sharing the same group_id belong to the same group. NULL is the
-- default — an individual exercise that stands on its own.
-- =============================================================================

alter table public.session_sets
  add column if not exists group_id text;

create index if not exists idx_session_sets_group_id
  on public.session_sets(group_id);
