-- DermaTrack — patient <-> dermatologist chat
-- ============================================
-- A simple one-thread-per-patient message log. Each row is one message in
-- the conversation between a patient and the demo dermatologist. patient_id
-- identifies the thread (always the patient, never the doctor); sender_id +
-- sender_role say who wrote it.
--
-- Visibility:
--   • Patient can read + send messages in their own thread (patient_id = self).
--   • Demo doctor can read + send in threads of consenting patients.
--   • Messages are immutable (no update/delete policies).
--
-- Realtime: the table is added to the supabase_realtime publication so the
-- Flutter client can stream new messages live.
--
-- Run AFTER 0002_doctor_demo.sql. Safe to re-run.
-- ============================================

CREATE TABLE IF NOT EXISTS public.messages (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The patient whose conversation thread this message belongs to.
    patient_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Who actually wrote the message.
    sender_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_role text        NOT NULL CHECK (sender_role IN ('patient', 'doctor')),
    body        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT messages_not_blank CHECK (length(btrim(body)) > 0)
);

CREATE INDEX IF NOT EXISTS messages_thread_idx
    ON public.messages (patient_id, created_at);

COMMENT ON TABLE public.messages
    IS 'Patient<->dermatologist chat. patient_id = thread; sender_role says who wrote it.';


-- ============================================
-- RLS
-- ============================================
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- ---- Patient: read own thread ----
DROP POLICY IF EXISTS "Patient can read own thread" ON public.messages;
CREATE POLICY "Patient can read own thread"
    ON public.messages FOR SELECT
    TO authenticated
    USING (auth.uid() = patient_id);

-- ---- Patient: send into own thread (as patient) ----
DROP POLICY IF EXISTS "Patient can send in own thread" ON public.messages;
CREATE POLICY "Patient can send in own thread"
    ON public.messages FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = patient_id
        AND auth.uid() = sender_id
        AND sender_role = 'patient'
    );

-- ---- Doctor: read consenting patients' threads ----
DROP POLICY IF EXISTS "Demo doctor can read consenting threads" ON public.messages;
CREATE POLICY "Demo doctor can read consenting threads"
    ON public.messages FOR SELECT
    TO authenticated
    USING (
        public.is_demo_doctor()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.messages.patient_id
              AND p.shared_with_doctor = true
        )
    );

-- ---- Doctor: send into consenting patients' threads (as doctor) ----
DROP POLICY IF EXISTS "Demo doctor can send in consenting threads" ON public.messages;
CREATE POLICY "Demo doctor can send in consenting threads"
    ON public.messages FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_demo_doctor()
        AND auth.uid() = sender_id
        AND sender_role = 'doctor'
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = public.messages.patient_id
              AND p.shared_with_doctor = true
        )
    );

-- No UPDATE/DELETE policies — messages are immutable once sent.


-- ============================================
-- Realtime
-- ============================================
-- Add to the realtime publication so clients can stream inserts. Guarded so
-- re-running is safe.
DO $$
BEGIN
    -- Supabase provisions the supabase_realtime publication by default, but
    -- create it if a fresh/edge-case project is missing it so the ADD below
    -- can't fail.
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;
END $$;


-- ============================================
-- Sanity check
-- ============================================
-- SELECT polname FROM pg_policy WHERE polrelid = 'public.messages'::regclass;  -- expect 4
