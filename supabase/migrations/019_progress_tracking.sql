-- Body measurements table
CREATE TABLE IF NOT EXISTS public.body_measurements (
    id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    unit TEXT NOT NULL DEFAULT 'cm',
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.body_measurements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own measurements" ON public.body_measurements;
CREATE POLICY "Users can read own measurements"
    ON public.body_measurements FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own measurements" ON public.body_measurements;
CREATE POLICY "Users can insert own measurements"
    ON public.body_measurements FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own measurements" ON public.body_measurements;
CREATE POLICY "Users can update own measurements"
    ON public.body_measurements FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own measurements" ON public.body_measurements;
CREATE POLICY "Users can delete own measurements"
    ON public.body_measurements FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_body_measurements_user_type
    ON public.body_measurements (user_id, type, recorded_at);

-- Progress photos table
CREATE TABLE IF NOT EXISTS public.progress_photos (
    id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.progress_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own photos" ON public.progress_photos;
CREATE POLICY "Users can read own photos"
    ON public.progress_photos FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own photos" ON public.progress_photos;
CREATE POLICY "Users can insert own photos"
    ON public.progress_photos FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own photos" ON public.progress_photos;
CREATE POLICY "Users can update own photos"
    ON public.progress_photos FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own photos" ON public.progress_photos;
CREATE POLICY "Users can delete own photos"
    ON public.progress_photos FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_progress_photos_user
    ON public.progress_photos (user_id, recorded_at);

-- Progress photos storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('progress-photos', 'progress-photos', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for progress photos
DROP POLICY IF EXISTS "progress_photos_public_read" ON storage.objects;
CREATE POLICY "progress_photos_public_read"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'progress-photos');

DROP POLICY IF EXISTS "progress_photos_user_write" ON storage.objects;
CREATE POLICY "progress_photos_user_write"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "progress_photos_user_update" ON storage.objects;
CREATE POLICY "progress_photos_user_update"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS "progress_photos_user_delete" ON storage.objects;
CREATE POLICY "progress_photos_user_delete"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'progress-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
