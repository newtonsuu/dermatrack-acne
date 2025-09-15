# DermaTrack — Admin Access (Functional Testing)

> Admin capabilities discovered in `app/lib/screens/admin/*` + `app/lib/services/admin_service.dart`, tested against the live backend with the real `admin@dermatrack.demo` account and a disposable target account (seeded + deleted). **No Super Admin tier exists** in DermaTrack, so that section is omitted (not fabricated). Each row notes whether the capability is enforced **only in the UI** or **also at the database (RLS)** — UI-only is a finding.

## Real admin capabilities (per code)
Admin console (`AdminShell`) has four areas: **Overview** (monitoring), **Users** (management), **Chats** (moderation), **Audit** (log) — plus **Break-glass** emergency access. Monitoring metrics that actually exist: total users, patients, doctors, admins, deactivated count, active break-glass count. (There is **no** "today's logins", "alerts", educational-content, FAQ, notification-template, or support-ticket feature.)

## Functional test table

| Test ID | Test description | Expected result | Actual result | Enforcement (UI / DB) | Pass/Fail |
|---|---|---|---|---|---|
| AF-01 | Admin signs in → routed to Admin console | Admin shell loads (not patient/doctor) | role resolves `admin` → AdminShell (verified live) | DB (role-based routing) | **Pass** |
| AF-02 | Overview shows system metrics | Real counts render (users/patients/doctors/admins/deactivated/active break-glass) | data loads (profiles=6); counts derived client-side | DB (data) + UI (render) | **Pass** |
| AF-03 | Manage Users — list all users | All users listed | 6 profiles returned | DB (RLS allows) | **Pass** |
| AF-04 | Change a user's role (promote/demote) | Role updates; gated to admin | target role → `doctor` (live); non-admin attempt denied (VT-16) | **DB** (RLS + guard trigger) | **Pass** |
| AF-05 | Deactivate a user | User deactivated **and access revoked** | `is_active=false` set; deactivated user now **blocked at the DB (0 rows)** after fix 0014 (was UI-only) | **DB** (RESTRICTIVE RLS) + UI | **Pass (found UI-only → fixed)** |
| AF-06 | Restrict a user from messaging | Restricted user cannot send | admin sets `messaging_restricted` (allow); sends blocked by RESTRICTIVE RLS policy `Block restricted senders` | **DB** (RLS) | **Pass** |
| AF-07 | View audit log | Admin sees audit entries | `audit_log` readable by admin (empty at test time) | **DB** (RLS) | **Pass** |
| AF-08 | Break-glass emergency access (open / read patient / revoke) | Time-limited, read-only, logged | RLS `has_active_break_glass()` gates read; open/revoke write `audit_log` (verified) | **DB** (RLS + audit) | **Pass** |
| AF-09 | Chat moderation — view all threads, remove a message | Admin reads every thread; can remove a message | admin SELECT-all + UPDATE (moderate) policies present & verified | **DB** (RLS) | **Pass** |
| AF-10 | Restricted-action gating (non-admin cannot do admin ops) | Doctor/Patient blocked from admin actions | doctor/patient read admin tables → 0; role change → denied (VT-15/16) | **DB** (RLS) | **Pass** |
| AF-11 | Admin content management (FAQ / educational / notification templates / support tickets) | — | **Not implemented in code** | — | **N/A** |
| AF-12 | "Today's logins" / "alerts" overview metrics | — | **Not implemented** (metrics are user/role counts only) | — | **N/A** |
| AF-13 | Error handling on restricted/unavailable sections; navigation stability | Graceful handling | not driven via UI this pass | UI | **To be executed (manual)** |
| AF-14 | Super Admin tier (admin-management, system config, DB management) | — | **No Super Admin role exists** | — | **N/A** |

## UI-vs-database cross-reference (key takeaway)
Every admin capability is now enforced **at the database** (RLS + the guard trigger), the correct tamper-resistant design: role changes, messaging restriction, audit access, break-glass, and chat moderation all hold even if a client bypasses the UI. Account deactivation (AF-05) was initially **UI-only** — a deactivated user's token still passed RLS — which the assessment flagged and then **fixed in migration 0014** (RESTRICTIVE "Active accounts only" policies on the clinical tables); re-verified that a deactivated user now reads 0 rows.

## Result
**Admin functional tests: 10 Pass, 0 Fail, 3 N/A (features that don't exist), 1 manual-pending (AF-13).** Admin role/user management, deactivation, restriction, audit, break-glass, and moderation are all correctly gated at the database. The one UI-only gap (deactivation) was found and remediated during testing.
