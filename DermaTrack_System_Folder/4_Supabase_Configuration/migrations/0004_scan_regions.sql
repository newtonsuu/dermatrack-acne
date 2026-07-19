-- DermaTrack — scan regions + guided session grouping
-- ============================================
-- Adds two columns to public.scans:
--   region      — anatomical zone the scan captured. Five values:
--                   forehead, left_cheek, right_cheek, chin, full_face.
--                 This is the basis of the daily 5-step guided capture
--                 (forehead → left cheek → right cheek → chin → full face)
--                 that came out of the dermatologist consult on 2026-05-25.
--   session_id  — groups the five scans of one guided capture into a
--                 coherent snapshot the UI can render as a unit. NULL for
--                 ad-hoc single-region scans and for legacy rows predating
--                 region tracking.
--
-- Pre-migration scans are silently tagged as 'full_face' via the column
-- DEFAULT — they were full-face captures, so this is accurate, and
-- nothing in the existing UI breaks.
--
-- Run AFTER 0003_doctor_notes.sql. Safe to re-run.
-- ============================================

-- ============================================
-- Columns
-- ============================================
ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS region     text NOT NULL DEFAULT 'full_face',
    ADD COLUMN IF NOT EXISTS session_id uuid;

-- Enum-style CHECK constraint. Preferred over a Postgres ENUM type because
-- if the dermatologist later asks for finer zones (forehead-left vs
-- forehead-right, jawline, nose, neck, etc.), updating a CHECK is a single
-- ALTER while updating an ENUM type requires ALTER TYPE + dependent code
-- changes. Same type safety either way at the row-write boundary.
ALTER TABLE public.scans
    DROP CONSTRAINT IF EXISTS scans_region_valid;
ALTER TABLE public.scans
    ADD CONSTRAINT scans_region_valid CHECK (
        region IN ('forehead', 'left_cheek', 'right_cheek', 'chin', 'full_face')
    );

COMMENT ON COLUMN public.scans.region
    IS 'Anatomical zone captured. One of: forehead, left_cheek, right_cheek, chin, full_face. Daily guided capture produces all five.';
COMMENT ON COLUMN public.scans.session_id
    IS 'Groups the 5 scans of one guided daily-capture session. NULL for standalone single-region scans and for legacy rows predating session tracking.';


-- ============================================
-- Indexes
-- ============================================

-- Fast "scans in this session" lookup. Partial index — session_id is NULL
-- on legacy rows and standalone scans, no reason to index them.
CREATE INDEX IF NOT EXISTS scans_user_session_idx
    ON public.scans (user_id, session_id)
    WHERE session_id IS NOT NULL;

-- Fast "this user's most-recent forehead scans" lookup, which the future
-- per-region trend chart will hit on dashboard load. Includes taken_at DESC
-- so the planner can use index-only scans for the typical "last N scans of
-- this region" query.
CREATE INDEX IF NOT EXISTS scans_user_region_taken_at_idx
    ON public.scans (user_id, region, taken_at DESC);


-- ============================================
-- Sanity-check queries
-- ============================================
-- Columns present + defaults applied to existing rows:
--   SELECT region, count(*) FROM public.scans GROUP BY region;
--   -- expected: all existing rows → 'full_face'
--
-- Constraint enforced:
--   INSERT INTO public.scans (...) VALUES (..., 'eyebrow', ...);
--   -- expected: ERROR — new row violates CHECK constraint scans_region_valid
--
-- Indexes exist:
--   SELECT indexname FROM pg_indexes
--   WHERE tablename = 'scans' AND indexname LIKE 'scans_user_%';
--   -- expected: scans_user_taken_at_idx, scans_user_cook_grade_idx,
--               scans_user_session_idx, scans_user_region_taken_at_idx
