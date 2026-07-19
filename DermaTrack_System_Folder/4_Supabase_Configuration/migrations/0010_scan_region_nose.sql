-- DermaTrack — add 'nose' to the scan region CHECK constraint
-- ============================================
-- The guided per-region scan now captures FIVE facial zones:
--   forehead, left_cheek, right_cheek, chin, nose
-- (full_face stays valid — it's still written by the standalone "quick single
-- scan"). This widens the scans_region_valid CHECK to allow 'nose'; without
-- it, a nose capture is rejected at insert with a CHECK violation.
--
-- Run AFTER 0009_messages.sql. Safe to re-run (idempotent).
-- ============================================

ALTER TABLE public.scans
    DROP CONSTRAINT IF EXISTS scans_region_valid;
ALTER TABLE public.scans
    ADD CONSTRAINT scans_region_valid CHECK (
        region IN ('forehead', 'left_cheek', 'right_cheek', 'chin', 'nose', 'full_face')
    );

COMMENT ON COLUMN public.scans.region
    IS 'Anatomical zone captured. One of: forehead, left_cheek, right_cheek, chin, nose, full_face. The guided per-region session captures the five facial zones; full_face is the standalone quick scan.';

-- ============================================
-- Sanity check
-- ============================================
--   INSERT ... region = 'nose'   → succeeds
--   INSERT ... region = 'eyebrow' → ERROR: violates scans_region_valid
