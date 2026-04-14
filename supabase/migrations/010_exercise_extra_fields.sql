-- =============================================================================
-- Migration 010: capture more of the ExerciseDB metadata.
--
-- ExerciseDB returns a `bodyPart` (anatomical region — waist, back,
-- upper legs, etc.), a separate `category` (movement type — strength,
-- cardio, stretching), a `description` (prose intro), and a
-- `difficulty` (beginner / intermediate / advanced).
--
-- The previous import was conflating bodyPart and category into the
-- single `category` column and dropping description + difficulty
-- entirely. This migration adds the missing columns. The transformer
-- and sync layer pick them up; the upcoming re-run of the import
-- script will populate them.
--
-- Difficulty maps onto the existing `level` column (whose check
-- constraint already permits beginner/intermediate/expert — the
-- transformer maps "advanced" → "expert").
-- =============================================================================

alter table public.exercises
  add column if not exists body_part text,
  add column if not exists description text;
