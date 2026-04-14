-- =============================================================================
-- Migration 008: exercise-images storage bucket.
--
-- Used by the ExerciseDB importer (scripts/import-exercisedb.ts) to
-- rehost every exercise GIF in our own Supabase Storage. After the
-- one-time bulk import, the app loads images from this bucket and has
-- no dependency on the ExerciseDB API or its CDN.
--
-- Public read so the GIFs load directly via URL in expo-image. No
-- INSERT / UPDATE / DELETE policies for anon — only the service-role
-- key (used by the import script) bypasses RLS and can write.
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('exercise-images', 'exercise-images', true)
on conflict (id) do nothing;

drop policy if exists "exercise_images_public_read" on storage.objects;
create policy "exercise_images_public_read" on storage.objects
  for select using (bucket_id = 'exercise-images');
