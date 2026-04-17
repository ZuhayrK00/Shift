-- =============================================================================
-- Migration 021: add height column (stored in total inches) to profiles.
-- =============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS height REAL;
