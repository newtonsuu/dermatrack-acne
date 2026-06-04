-- DermaTrack — Harden account deactivation (VT-23) + restrict profile enumeration (R-1)
-- ============================================================================
-- Findings from the security assessment:
--   VT-23/AF-05: account deactivation was enforced only in the app; a
--     deactivated user's JWT still passed RLS. Fix: block deactivated users
--     from clinical data at the database via a RESTRICTIVE policy.
--   R-1: profiles.SELECT was USING(true) -> any authenticated user could
--     enumerate all usernames/roles. Fix: scope SELECT to self, admin, or a
--     doctor for consenting patients.
--
-- Run AFTER 0013. Idempotent.
-- ============================================================================

-- is_account_active(): the caller's own active flag (default true if missing).
-- SECURITY DEFINER so it can read profiles even under the new restrictive rule.
CREATE OR REPLACE FUNCTION public.is_account_active()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((SELECT is_active FROM public.profiles WHERE id = auth.uid()), true);
$$;

-- VT-23 fix: a deactivated user is blocked from all clinical data. RESTRICTIVE
-- => ANDs with the existing permissive policies. profiles is intentionally
-- EXCLUDED so the app can still read the caller's own row to detect/show the
-- deactivated state. The check is on the CALLER's status, so an active
-- doctor/admin reading a (deactivated) patient's data is unaffected.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['scans','patient_histories','treatment_plans','prescriptions','doctor_notes','messages']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "Active accounts only" ON public.%I;', t);
    EXECUTE format('CREATE POLICY "Active accounts only" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (public.is_account_active()) WITH CHECK (public.is_account_active());', t);
  END LOOP;
END $$;

-- R-1 fix: profiles no longer world-readable.
DROP POLICY IF EXISTS "Profiles viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Profiles readable by self, doctor or admin" ON public.profiles;
CREATE POLICY "Profiles readable by self, doctor or admin"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR public.is_admin()
        OR (public.is_demo_doctor() AND shared_with_doctor = true)
    );

-- ============================================================================
-- Sanity checks
--   (deactivated user) SELECT own scans            -> 0 rows (blocked)
--   (patient)          SELECT profiles             -> only own row
--   (doctor)           SELECT profiles consenting  -> allowed
--   (admin)            SELECT profiles             -> all
-- ============================================================================
