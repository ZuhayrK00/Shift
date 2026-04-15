-- Add group_id column to plan_exercises for superset grouping.
-- Matches the local SQLite schema which already has this column.

alter table public.plan_exercises
  add column if not exists group_id text;
