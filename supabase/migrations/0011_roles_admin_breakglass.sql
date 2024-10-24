-- DermaTrack — Role-based access control: roles, admin, break-glass, audit log
-- ============================================================================
-- Full RBAC overhaul, applied SAFELY so the existing demo keeps working:
--   * Adds a `role` column to profiles (patient | doctor | admin) and an
--     `is_active` flag for admin activation/deactivation.
--   * Backfills the existing demo doctor account(s) to role='doctor', so the
--     doctor side keeps working unchanged.
--   * Redefines is_demo_doctor() to be ROLE-BASED instead of email-based —
--     every existing doctor RLS policy now keys off the role column with no
--     policy rewrites.
--   * Adds is_admin() + admin management policies on profiles.
--   * Adds an audit_log table (doctor/admin/break-glass/privacy actions).
--   * Adds break_glass_sessions (time-limited, read-only emergency admin
--     access) + has_active_break_glass() + read policies gated on it.
--
-- Run AFTER 0010_scan_region_nose.sql. Idempotent / safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Role + account status on profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'patient',
    ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_valid;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_role_valid CHECK (role IN ('patient', 'doctor', 'admin'));

-- Backfill: the existing demo doctor account(s) become role='doctor' so the
-- doctor experience is unchanged after the switch from email- to role-based.
UPDATE public.profiles p
SET role = 'doctor'
FROM auth.users u
WHERE u.id = p.id
  AND LOWER(u.email) IN ('doctor@dermatrack.demo', 'dr.demo@dermatrack.demo')
  AND p.role <> 'doctor';

COMMENT ON COLUMN public.profiles.role
    IS 'Access role: patient | doctor | admin. Basis for is_demo_doctor()/is_admin() and all role-based RLS.';
COMMENT ON COLUMN public.profiles.is_active
    IS 'Admin-controlled account status. Deactivated accounts are blocked at the app layer.';

-- ---------------------------------------------------------------------------
-- 2) Role helper functions (SECURITY DEFINER: read role without tripping RLS)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_user_role() = 'admin', false);
$$;

-- Redefine the (historically email-based) doctor check to be ROLE-based.
-- Same signature, so every existing policy that calls it now keys off role.
CREATE OR REPLACE FUNCTION public.is_demo_doctor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(public.current_user_role() = 'doctor', false);
$$;

COMMENT ON FUNCTION public.is_demo_doctor()
    IS 'True iff the current user has role=''doctor'' (role-based since 0011).';

-- ---------------------------------------------------------------------------
-- 3) Admin management of profiles (user/role management, activate/deactivate)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;
CREATE POLICY "Admins can update any profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- 4) Audit log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_role     text,
    action         text NOT NULL,
    target_user_id uuid,
    detail         text,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_created_idx ON public.audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_target_idx ON public.audit_log (target_user_id);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can write their own audit entries (the app logs
-- doctor/admin/break-glass/privacy actions as they happen).
DROP POLICY IF EXISTS "Audit: insert own entries" ON public.audit_log;
CREATE POLICY "Audit: insert own entries"
    ON public.audit_log FOR INSERT
    TO authenticated
    WITH CHECK (actor_id = auth.uid());

-- Admins read everything; a user can read entries they performed or that
-- target them.
DROP POLICY IF EXISTS "Audit: read admin or self" ON public.audit_log;
CREATE POLICY "Audit: read admin or self"
    ON public.audit_log FOR SELECT
    TO authenticated
    USING (public.is_admin() OR actor_id = auth.uid() OR target_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5) Break-glass emergency access (time-limited, read-only by default)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.break_glass_sessions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_patient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reason            text NOT NULL CHECK (length(btrim(reason)) > 0),
    duration_minutes  integer NOT NULL CHECK (duration_minutes IN (15, 30, 60)),
    read_only         boolean NOT NULL DEFAULT true,
    granted_at        timestamptz NOT NULL DEFAULT now(),
    expires_at        timestamptz NOT NULL,
    revoked           boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS bg_admin_idx ON public.break_glass_sessions (admin_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS bg_target_idx ON public.break_glass_sessions (target_patient_id);

ALTER TABLE public.break_glass_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Break-glass: admin insert" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin insert"
    ON public.break_glass_sessions FOR INSERT
    TO authenticated
    WITH CHECK (public.is_admin() AND admin_id = auth.uid());

DROP POLICY IF EXISTS "Break-glass: admin read" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin read"
    ON public.break_glass_sessions FOR SELECT
    TO authenticated
    USING (public.is_admin());

DROP POLICY IF EXISTS "Break-glass: admin revoke" ON public.break_glass_sessions;
CREATE POLICY "Break-glass: admin revoke"
    ON public.break_glass_sessions FOR UPDATE
    TO authenticated
    USING (public.is_admin() AND admin_id = auth.uid())
    WITH CHECK (public.is_admin() AND admin_id = auth.uid());

-- True iff the calling admin holds an active (non-revoked, non-expired)
-- break-glass session for patient p.
CREATE OR REPLACE FUNCTION public.has_active_break_glass(p uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.break_glass_sessions b
        WHERE b.admin_id = auth.uid()
          AND b.target_patient_id = p
          AND b.revoked = false
          AND b.expires_at > now()
    );
$$;

-- Read-only break-glass access to a patient's clinical data while a session
-- is active. (No write policies — break-glass is read-only.)
DROP POLICY IF EXISTS "Break-glass: admin read scans" ON public.scans;
CREATE POLICY "Break-glass: admin read scans"
    ON public.scans FOR SELECT
    TO authenticated
    USING (public.is_admin() AND public.has_active_break_glass(user_id));

DROP POLICY IF EXISTS "Break-glass: admin read histories" ON public.patient_histories;
CREATE POLICY "Break-glass: admin read histories"
    ON public.patient_histories FOR SELECT
    TO authenticated
    USING (public.is_admin() AND public.has_active_break_glass(user_id));

-- ---------------------------------------------------------------------------
-- Sanity checks
-- ---------------------------------------------------------------------------
--   SELECT role, count(*) FROM public.profiles GROUP BY role;
--   SELECT public.is_demo_doctor();   -- true only for role='doctor' callers
--   SELECT public.is_admin();         -- true only for role='admin' callers
