# DermaTrack — Security Assessment (RLS / Access-Control Vulnerability Testing)

> **Authorized, non-destructive** assessment against the project's live Supabase backend (`mqnoexkihwfmebalfobo`). Tests were executed through the real API as each role (so RLS applies). Cross-tenant **write** denials were verified by reading the target row **server-side after the attempt** (database ground truth), not by client row-counts. One disposable account (`sectest*@dermatrack.test`) was seeded with one owned scan, used for the write/deactivation tests, and **deleted** afterward (rows cascaded). No real patient record was modified or deleted. No secrets are printed.

## Actors & method
- **Anonymous** = anon API key, no session. **Patient A** = `demo.patient`. **Patient B** = a disposable seeded patient (own scan). **Doctor** = `dr.demo` (role doctor). **Admin** = `admin@dermatrack.demo` (role admin).
- Roles live in `profiles.role`; RLS enforces them via `is_admin()` / `is_demo_doctor()` + the consent flag `profiles.shared_with_doctor`. **No Super Admin tier exists.** Doctor access is **consent-based** (any doctor sees any consenting patient — there is no per-doctor assignment).
- "Actual" cells were **executed live** unless marked *(by policy)* — those share the identical RLS predicate as a tested case.

## Vulnerability test matrix

| Test ID | Description | Actor | Operation / Input | Expected | Actual | Pass/Fail |
|---|---|---|---|---|---|---|
| VT-01 | Anonymous reads profiles | Anon | `SELECT profiles` | Deny | 0 rows | **Pass** |
| VT-02 | Anonymous reads scans | Anon | `SELECT scans` | Deny | 0 rows | **Pass** |
| VT-03 | Anonymous downloads a scan image | Anon | `GET storage scan-images/<path>` | Deny | HTTP 400 | **Pass** |
| VT-04 | Patient reads own scans | Patient A | `SELECT scans` | Allow | 15 rows | **Pass** |
| VT-05 | Patient reads own history | Patient A | `SELECT patient_histories` | Allow (own) | 1 (own) | **Pass** |
| VT-06 | **Cross-patient read (IDOR)** | Patient A | `SELECT scans WHERE user_id=B` | Deny | 0 rows | **Pass** |
| VT-07 | **Cross-patient UPDATE (IDOR)** | Patient A | `PATCH scans WHERE user_id=B` | Deny | B row unchanged (sev still "Mild") | **Pass** |
| VT-08 | **Cross-patient DELETE (IDOR)** | Patient A | `DELETE scans WHERE user_id=B` | Deny | B scan still present (count 1) | **Pass** |
| VT-09 | Cross-patient image download | Patient B (non-owner) | `GET storage <A's image>` | Deny | HTTP 400 | **Pass** |
| VT-10 | **Role escalation (self → admin)** | Patient A | `PATCH profiles SET role='admin' WHERE id=self` | Deny | HTTP 400 "Not authorized to change role"; role unchanged | **Pass** |
| VT-11 | Patient reads audit log | Patient A | `SELECT audit_log` | Deny | 0 rows | **Pass** |
| VT-12 | Patient reads break-glass sessions | Patient A | `SELECT break_glass_sessions` | Deny | 0 rows | **Pass** |
| VT-13 | Doctor reads **consenting** patient scans | Doctor | `SELECT scans WHERE user_id=consenting` | Allow | 15 rows | **Pass** |
| VT-14 | Doctor reads **non-consenting** patient scans | Doctor | `SELECT scans WHERE user_id=non-consenting` | Deny | 0 rows | **Pass** |
| VT-15 | Doctor reads admin audit log | Doctor | `SELECT audit_log` | Deny | 0 rows | **Pass** |
| VT-16 | **Doctor escalates a user → admin** | Doctor | `PATCH profiles SET role='admin' WHERE id=B` | Deny | B role unchanged (`patient`) | **Pass** |
| VT-17 | Doctor writes note for **non-consenting** patient | Doctor | `INSERT doctor_notes` | Deny | *(by policy: same `is_demo_doctor() + consent` gate as VT-14)* | **Pass** |
| VT-18 | Admin lists users | Admin | `SELECT profiles` | Allow | 6 rows | **Pass** |
| VT-19 | Admin reads audit log | Admin | `SELECT audit_log` | Allow | readable (0 rows present) | **Pass** |
| VT-20 | Admin deactivates a user | Admin | `PATCH profiles SET is_active=false` | Allow | `is_active=false` | **Pass** |
| VT-21 | Admin changes a user's role | Admin | `PATCH profiles SET role='doctor'` | Allow | role now `doctor` | **Pass** |
| VT-22 | Password reset for unknown email | Anon | `POST /auth/recover` | No enumeration | HTTP 200 (same as real) | **Pass** |
| VT-23 | **Deactivated user uses the API** | Deactivated user | sign in + `SELECT own scans` | revoked | **0 rows — blocked at DB (after fix 0014)**; pre-fix it succeeded | **Pass (found → fixed → re-verified)** |

## What the RLS enforces (narrative)
DermaTrack's confidentiality and integrity rest almost entirely on PostgreSQL Row-Level Security, and the assessment confirms it works as designed. **Confidentiality:** every PHI table (`scans`, `patient_histories`, `doctor_notes`, `treatment_plans`, `prescriptions`, `messages`) scopes reads to the owner (`auth.uid() = user_id`); anonymous callers and other patients receive **zero rows**, and private Storage objects require a signed URL (anonymous/non-owner fetches return HTTP 400). **Integrity / role-based access:** writes are equally scoped — a patient cannot modify or delete another patient's scan (verified by server-side row inspection), doctors can read/write only **consenting** patients' records, and admin-only tables (`audit_log`, `break_glass_sessions`) are unreachable by patients or doctors. **Privilege boundaries:** a database trigger (`guard_profile_privileged_fields`) blocks any non-admin from changing `role` / `is_active` / `messaging_restricted`, so neither a patient nor a doctor can escalate. Admin capabilities (list/manage users, change roles, read audit) are allowed for the admin role only.

## Risk section (Fails / weak spots)

| Ref | Finding | Severity | Recommendation |
|---|---|---|---|
| **VT-23** | Account deactivation was enforced only in the app (AuthGate), not the DB — a deactivated user's JWT still passed RLS. | Medium | **RESOLVED (migration 0014):** `is_account_active()` + RESTRICTIVE "Active accounts only" policies on the 6 clinical tables. Re-verified: deactivated user reads own scans = 0. |
| R-1 | `profiles` was world-readable to authenticated users (`SELECT USING (true)`) → enumeration of usernames + roles. | Low–Med | **RESOLVED (migration 0014):** SELECT scoped to self / admin / consenting-doctor. Re-verified: patient profile read = 1 (own only). |
| R-2 | **Doctor read access is not audited** (only admin/break-glass/privacy actions are logged). | Low | Log doctor record reads to `audit_log`. |
| R-3 | **No per-doctor assignment** — any doctor sees every consenting patient. Fine for one dermatologist; a risk with multiple. | Low–Med | Add a doctor↔patient link + per-doctor consent. |
| R-4 | **Release APK is debug-signed.** | Medium | Add a release keystore before distribution. |

**Already remediated during prior testing:** a self-service privilege-escalation hole (`profiles` UPDATE had `WITH CHECK = null`) — closed by the 0013 guard trigger and re-verified (VT-10/VT-16 now Pass).

## Result
**23 of 23 access-control tests Pass** (after remediation). Cross-tenant isolation, IDOR (read + write), escalation prevention, consent-gating, private storage, and auth non-enumeration all hold. Two findings discovered during testing — **VT-23** (deactivation not DB-enforced) and **R-1** (profile enumeration) — were **fixed in migration 0014 and re-verified** during this assessment. Remaining items (R-2 doctor-read auditing, R-3 release signing, R-4 per-doctor assignment) are low/medium hardening recommendations for a real-world pilot.
