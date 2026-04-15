-- Add notes column to session_sets for per-exercise workout notes.
-- Stored on the first set of each exercise in a session.

alter table public.session_sets
  add column if not exists notes text;
