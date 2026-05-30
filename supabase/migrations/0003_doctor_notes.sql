-- DermaTrack — doctor notes per scan
-- ============================================
-- Adds a 1:1 (zero-or-one) `doctor_notes` table keyed by scan_id. The
-- dermatologist (demo doctor account) can leave a clinical note on any
-- consenting patient's scan; the patient sees it on the scan detail screen
-- labelled "From your dermatologist".
--
-- Why a separate table instead of a column on `scans`:
--   - Postgres has column-level GRANT but not column-level RLS. With a
--     doctor_note column on scans, the patient's existing "Users can update
--     own scans" policy would let them edit the doctor's note. A separate
--     table with its own RLS keeps write authority cleanly with the doctor.
--   - The cascade-delete behavior we want (delete the scan → delete its
--     note) is the same with both designs.
--
-- Visibility rules:
--   - Patient can SELECT notes on their own scans (always — even after they
--     toggle sharing off, so previously-left notes don't disappear).
--   - Doctor can SELECT/INSERT/UPDATE/DELETE notes for scans whose owner
--     has shared_with_doctor = true. Turning sharing off freezes the
--     doctor's write access; existing notes remain visible to the patient.
--
-- Run AFTER 0002_doctor_demo.sql. Safe to re-run.
-- ============================================

-- ============================================
-- Table
-- ============================================
CREATE TABLE IF NOT EXISTS public.doctor_notes (
    -- PK == scan_id enforces the 1:1 (max one note per scan).
    scan_id     uuid        PRIMARY KEY REFERENCES public.scans(id) ON DELETE CASCADE,
    note        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT doctor_notes_not_blank CHECK (length(btrim(note)) > 0)
);

COMMENT ON TABLE public.doctor_notes
    IS 'Dermatologist-authored note for a single scan. PK is scan_id so each scan has at most one note.';
COMMENT ON COLUMN public.doctor_notes.note
    IS 'Free-text clinical observation from the demo doctor account. NOT NULL + non-blank check — clear/delete the row to remove a note.';


-- ============================================
-- updated_at trigger (re-use existing helper from 0001)
-- ============================================
DROP TRIGGER IF EXISTS doctor_notes_updated_at ON public.doctor_notes;
CREATE TRIGGER doctor_notes_updated_at
    BEFORE UPDATE ON public.doctor_notes
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.doctor_notes ENABLE ROW LEVEL SECURITY;

-- ---- Patient read ----
-- The owner of the scan can always see its doctor note (so revocation of
-- sharing doesn't make past notes vanish).
DROP POLICY IF EXISTS "Patient can read doctor notes on own scans" ON public.doctor_notes;
CREATE POLICY "Patient can read doctor notes on own scans"
    ON public.doctor_notes FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.scans s
            WHERE s.id = public.doctor_notes.scan_id
              AND s.user_id = auth.uid()
        )
    );

-- ---- Doctor read ----
-- The demo doctor can read notes for scans owned by consenting patients.
DROP POLICY IF EXISTS "Demo doctor can read notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can read notes for consenting patients"
    ON public.doctor_notes FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (insert) ----
DROP POLICY IF EXISTS "Demo doctor can add notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can add notes for consenting patients"
    ON public.doctor_notes FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (update) ----
DROP POLICY IF EXISTS "Demo doctor can edit notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can edit notes for consenting patients"
    ON public.doctor_notes FOR UPDATE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor write (delete) ----
DROP POLICY IF EXISTS "Demo doctor can delete notes for consenting patients" ON public.doctor_notes;
CREATE POLICY "Demo doctor can delete notes for consenting patients"
    ON public.doctor_notes FOR DELETE
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1
            FROM public.scans s
            JOIN public.profiles p ON p.id = s.user_id
            WHERE s.id = public.doctor_notes.scan_id
              AND p.shared_with_doctor = true
        )
    );

-- Patient deliberately has NO insert/update/delete policies — they cannot
-- author or modify doctor notes. PostgREST denies by default.


-- ============================================
-- Sanity-check queries
-- ============================================
-- Table present:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'doctor_notes';
--
-- RLS enabled:
--   SELECT relrowsecurity FROM pg_class WHERE relname = 'doctor_notes';
--
-- Policies present (expect five):
--   SELECT polname FROM pg_policy WHERE polrelid = 'public.doctor_notes'::regclass;
