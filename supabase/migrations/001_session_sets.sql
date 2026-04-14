-- =============================================================================
-- Migration 001: session_sets — add is_completed, make completed_at nullable
-- Run this in the Supabase SQL editor.
-- =============================================================================

alter table public.session_sets
  alter column completed_at drop not null,
  alter column completed_at drop default;

alter table public.session_sets
  add column if not exists is_completed boolean not null default false;
