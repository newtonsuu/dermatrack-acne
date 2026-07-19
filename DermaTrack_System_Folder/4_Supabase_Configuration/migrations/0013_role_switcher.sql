-- DermaTrack — Role switcher for designated accounts + close self-role-change hole
-- ============================================================================
-- Problem found: the "Users can update own profile" policy had WITH CHECK = null
-- (falls back to USING auth.uid()=id), letting ANY user change their own
-- `role` -> privilege escalation. This migration:
--   * Adds profiles.can_switch_roles (admin-granted) for "super" demo accounts.
--   * Adds a BEFORE UPDATE trigger that blocks non-admins from changing
--     role / is_active / messaging_restricted / can_switch_roles, EXCEPT an
--     account flagged can_switch_roles may change its OWN role (for the
--     in-app role switcher). Trusted server/migration context (auth.uid() IS
--     NULL) is allowed.
--
-- Run AFTER 0012. Idempotent.
-- ============================================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS can_switch_roles boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.profiles.can_switch_roles
    IS 'When true, the account may switch its own role between patient/doctor/admin (demo/dev super account).';

-- Reads the flag for the current user (SECURITY DEFINER to bypass RLS read).
CREATE OR REPLACE FUNCTION public.can_switch_roles()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT can_switch_roles FROM public.profiles WHERE id = auth.uid()),
        false);
$$;

-- Guard: privileged columns may only change under the right authority.
CREATE OR REPLACE FUNCTION public.guard_profile_privileged_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Trusted server / migration / SQL-editor context has no JWT user.
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- role: admins (any profile) or a can-switch account (its own) may change.
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT (public.is_admin() OR public.can_switch_roles()) THEN
            RAISE EXCEPTION 'Not authorized to change role';
        END IF;
    END IF;

    -- status / privilege flags: admins only.
    IF (NEW.is_active IS DISTINCT FROM OLD.is_active)
        OR (NEW.messaging_restricted IS DISTINCT FROM OLD.messaging_restricted)
        OR (NEW.can_switch_roles IS DISTINCT FROM OLD.can_switch_roles) THEN
        IF NOT public.is_admin() THEN
            RAISE EXCEPTION 'Not authorized to change account status fields';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_privileged ON public.profiles;
CREATE TRIGGER profiles_guard_privileged
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.guard_profile_privileged_fields();

-- ============================================================================
-- Sanity checks
--   (patient) UPDATE profiles SET role='admin' WHERE id = auth.uid();  -> ERROR
--   (can_switch account) UPDATE profiles SET role='doctor' WHERE id = auth.uid(); -> OK
--   (admin) UPDATE profiles SET role='doctor' WHERE id = <other>;      -> OK
-- ============================================================================
