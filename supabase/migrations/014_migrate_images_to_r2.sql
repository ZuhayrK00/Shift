-- =============================================================================
-- Migration 014: Repoint exercise image URLs from Supabase Storage to Cloudflare R2.
--
-- All GIFs have been migrated to R2 with identical filenames.
-- This UPDATE swaps the base URL prefix so the app fetches from R2 instead.
-- =============================================================================

UPDATE exercises
SET image_url = REPLACE(
    image_url,
    'https://dtzlfvuazdrgyyutjysm.supabase.co/storage/v1/object/public/exercise-images',
    'https://pub-2e5f6ec0348f4117a4c8e90f5057fbc3.r2.dev'
)
WHERE image_url LIKE 'https://dtzlfvuazdrgyyutjysm.supabase.co/storage/v1/object/public/exercise-images%';
