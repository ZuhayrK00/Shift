-- =============================================================================
-- Migration 016: Weight entries for body weight tracking over time.
-- =============================================================================

CREATE TABLE IF NOT EXISTS weight_entries (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    weight      DOUBLE PRECISION NOT NULL,
    unit        TEXT NOT NULL DEFAULT 'kg',
    source      TEXT NOT NULL DEFAULT 'manual',
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_weight_entries_user ON weight_entries (user_id, recorded_at DESC);

-- RLS: users can only access their own entries
ALTER TABLE weight_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own weight entries"
    ON weight_entries
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
