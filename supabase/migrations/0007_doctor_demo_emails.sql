-- DermaTrack — additional demo doctor email
-- ============================================
-- Widens is_demo_doctor() to recognize more than one demo dermatologist
-- account. Mirrors kDoctorDemoEmails in app/lib/services/auth_service.dart:
-- the client uses that set to route to the doctor shell; this function is the
-- server-side RLS gate that actually grants the doctor read access to
-- consenting patients. The two MUST list the same emails or a "doctor" can
-- reach the UI but see no data (RLS returns nothing).
--
-- Still DEMO-GRADE (hardcoded emails). Post-thesis this whole approach is
-- replaced by a proper role table — see 0002_doctor_demo.sql.
--
-- Run AFTER 0002_doctor_demo.sql (and any time you add a demo doctor email).
-- Safe to re-run.
-- ============================================

CREATE OR REPLACE FUNCTION public.is_demo_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    -- Lower-case both sides: Supabase stores emails lower-cased but the JWT
    -- claim can vary by how the account was created.
    SELECT LOWER(COALESCE(auth.jwt() ->> 'email', '')) IN (
        'doctor@dermatrack.demo',
        'dr.demo@dermatrack.demo'
    );
$$;

COMMENT ON FUNCTION public.is_demo_doctor()
    IS 'Returns true iff the current request''s JWT belongs to a demo doctor account. Keep in sync with kDoctorDemoEmails in auth_service.dart.';

-- ============================================
-- Sanity check
-- ============================================
-- SELECT prosrc FROM pg_proc WHERE proname = 'is_demo_doctor';
