-- DermaTrack — Messaging: edit/unsend + admin moderation + behavior restriction
-- ============================================================================
-- Builds on 0009_messages.sql and the RBAC from 0011.
--   * messages: edit (edited_at), unsend (deleted_at, soft delete), and
--     admin removal (removed_by_admin).
--   * profiles.messaging_restricted: admin moderation flag that blocks a user
--     from sending (enforced by a RESTRICTIVE insert policy).
--   * RLS: sender can edit/unsend OWN messages; admin can read all + moderate.
--
-- Run AFTER 0011. Idempotent / safe to re-run.
-- ============================================================================

-- 1) messages: edit / unsend / admin-removal columns
ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS edited_at        timestamptz,
    ADD COLUMN IF NOT EXISTS deleted_at       timestamptz,
    ADD COLUMN IF NOT EXISTS removed_by_admin boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.messages.edited_at
    IS 'Set when the sender edits the message (Messenger-style edit).';
COMMENT ON COLUMN public.messages.deleted_at
    IS 'Set when unsent (soft delete). Body retained for moderation; hidden in normal UI.';
COMMENT ON COLUMN public.messages.removed_by_admin
    IS 'True when an admin/moderator removed the message.';

-- 2) profiles: messaging restriction (moderation)
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS messaging_restricted boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.profiles.messaging_restricted
    IS 'Admin moderation flag: when true the user cannot send chat messages.';

-- 3) Helper: is the calling user restricted from messaging?
CREATE OR REPLACE FUNCTION public.is_messaging_restricted()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT messaging_restricted FROM public.profiles WHERE id = auth.uid()),
        false);
$$;

-- 4) Sender can edit / unsend their OWN messages. WITH CHECK forbids touching a
--    message an admin already removed (so a user can't undo moderation).
DROP POLICY IF EXISTS "Sender can update own message" ON public.messages;
CREATE POLICY "Sender can update own message"
    ON public.messages FOR UPDATE
    TO authenticated
    USING (sender_id = auth.uid())
    WITH CHECK (sender_id = auth.uid() AND removed_by_admin = false);

-- 5) Admin moderation: read every thread + remove any message.
DROP POLICY IF EXISTS "Admin can read all messages" ON public.messages;
CREATE POLICY "Admin can read all messages"
    ON public.messages FOR SELECT
    TO authenticated
    USING (public.is_admin());

DROP POLICY IF EXISTS "Admin can moderate messages" ON public.messages;
CREATE POLICY "Admin can moderate messages"
    ON public.messages FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- 6) Block restricted users from SENDING. RESTRICTIVE => ANDs with the existing
--    permissive patient/doctor insert policies, so a restricted user is denied.
DROP POLICY IF EXISTS "Block restricted senders" ON public.messages;
CREATE POLICY "Block restricted senders"
    ON public.messages
    AS RESTRICTIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (NOT public.is_messaging_restricted());

-- ============================================================================
-- Sanity checks
--   UPDATE messages SET edited_at = now() WHERE id = '<own msg>';      -- sender OK
--   UPDATE messages SET deleted_at = now() WHERE id = '<own msg>';     -- unsend OK
--   (restricted user) INSERT INTO messages ... -> violates RLS
--   (admin) SELECT * FROM messages;                                    -- all threads
-- ============================================================================
