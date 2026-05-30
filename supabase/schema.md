# DermaTrack — Supabase Schema Proposal

Status: **DRAFT, pending review.** Nothing in here has been applied to the database yet. Read through, push back on anything that doesn't fit, and once it's locked in I'll generate the corresponding `supabase/migrations/0001_init.sql` for you to run.

This proposal covers v1 only: account creation, profile management, and storing the results of a single scan. Longitudinal trend queries, routine/trigger tracking, and any social features are intentionally out of scope here so we don't over-design the foundation.

---

## High-level design choices

A few decisions are baked into the schema. Calling them out so they can be challenged before we lock anything in.

**1. `profiles` table is a 1:1 extension of `auth.users`.** Supabase's `auth.users` table stores authentication data (email, password hash, etc.) and is owned by the auth subsystem — you can't add columns to it. The standard pattern is a separate `public.profiles` table with the same `id` as the auth user, holding everything else. A trigger auto-creates this row on signup so the app never has to manage it explicitly.

**2. Lesion data lives as JSONB on the scan row, not in a separate table.** A scan typically produces 1-30 lesion detections. Storing them as a single JSONB column keeps queries simple (one row = one scan, no joins) and lets the schema absorb model changes (zukbx returns one shape, a future model might return a slightly different one) without migrations. Trade-off: per-lesion analytics (e.g., "show me all papules across all my scans") becomes a `jsonb_array_elements` query instead of a clean SQL join. For our use case — display + simple counts — JSONB is the right choice. We can normalize later if needed.

**3. Severity grade and label are stored explicitly, not computed at query time.** The detection model gives lesion counts; we derive a 0-8 Cook-style grade and a human-readable label client-side at scan time and store both. This means the dashboard chart doesn't have to recompute on every read, and the values stay stable even if our grading formula evolves later.

**4. Two separate storage buckets, not one.** Profile pictures and scan images have different access patterns and retention. Separate buckets means simpler RLS policies and clearer mental model.

**5. Soft-delete is NOT implemented for v1.** When a user deletes a scan, it's gone. Adding `deleted_at` with filtering everywhere is overhead we don't need yet. Can be added in a v2 migration if it becomes important.

---

## Tables

### `public.profiles`

Extends `auth.users` with app-specific fields.

| Column                   | Type          | Constraints                                  | Notes                                                                 |
| ------------------------ | ------------- | -------------------------------------------- | --------------------------------------------------------------------- |
| `id`                     | `uuid`        | PK, FK → `auth.users(id)` ON DELETE CASCADE  | Mirrors the auth user's id                                            |
| `username`               | `text`        | UNIQUE, NOT NULL, CHECK (length ≥ 3)         | Lower-cased version stored for case-insensitive uniqueness            |
| `display_name`           | `text`        | nullable                                     | Optional; defaults to username if not set                             |
| `profile_picture_path`   | `text`        | nullable                                     | Path within the `profile-pictures` storage bucket                     |
| `created_at`             | `timestamptz` | NOT NULL, default `now()`                    |                                                                       |
| `updated_at`             | `timestamptz` | NOT NULL, default `now()`                    | Updated by trigger on any column change                               |

**Indexes:** unique on `username`.

**Sample row:**
```json
{
  "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "username": "aj_g",
  "display_name": "AJ Guanga",
  "profile_picture_path": "aaaaaaaa-.../avatar.jpg",
  "created_at": "2026-05-16T08:30:00Z",
  "updated_at": "2026-05-16T08:30:00Z"
}
```

### `public.scans`

One row per scan submission. Holds derived severity data plus the per-lesion list as JSONB.

| Column                    | Type           | Constraints                                       | Notes                                                                                       |
| ------------------------- | -------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `id`                      | `uuid`         | PK, default `gen_random_uuid()`                   |                                                                                             |
| `user_id`                 | `uuid`         | NOT NULL, FK → `auth.users(id)` ON DELETE CASCADE | Owns the scan                                                                               |
| `taken_at`                | `timestamptz`  | NOT NULL, default `now()`                         | When the user took the photo (set client-side, can be edited later if user notes wrong date) |
| `image_path`              | `text`         | NOT NULL                                          | Path in the `scan-images` storage bucket                                                    |
| `cook_grade`              | `integer`      | nullable, CHECK between -1 and 8                  | -1 = Clear Skin (from skintelligent), 0–8 = Cook-style severity grade                       |
| `severity_label`          | `text`         | nullable                                          | Human-readable: `'Clear'`, `'Mild'`, `'Moderate'`, `'Severe'`, `'Very Severe'`              |
| `inflammatory_count`      | `integer`      | NOT NULL, default 0                               | Sum of papules + pustules + nodules + cysts                                                 |
| `non_inflammatory_count`  | `integer`      | NOT NULL, default 0                               | Sum of comedones + whiteheads + blackheads                                                  |
| `post_acne_count`         | `integer`      | NOT NULL, default 0                               | Dark spots, scars, etc. — NOT active acne                                                   |
| `lesions`                 | `jsonb`        | NOT NULL, default `'[]'::jsonb`                   | See "Lesions JSONB shape" below                                                             |
| `source_metadata`         | `jsonb`        | NOT NULL, default `'{}'::jsonb`                   | Provenance: which model(s) produced the data. See below.                                    |
| `notes`                   | `text`         | nullable                                          | User-added notes (mood, products applied, etc.) — for v2 routine tracking                   |
| `created_at`              | `timestamptz`  | NOT NULL, default `now()`                         |                                                                                             |

**Indexes:**
- `(user_id, taken_at DESC)` — primary access pattern: gallery + dashboard recent scans
- `(user_id, cook_grade)` — for severity trend queries

#### Lesions JSONB shape

Array of objects, each representing one detected lesion. Keys are stable; consumers should treat unknown keys as ignored.

```json
[
  {
    "class": "papules",
    "bucket": "inflammatory",
    "confidence": 0.832,
    "bbox": { "x": 354.5, "y": 757.0, "w": 43.0, "h": 46.0 },
    "image_size": { "w": 736, "h": 981 }
  },
  {
    "class": "comedone",
    "bucket": "non_inflammatory",
    "confidence": 0.991,
    "bbox": { "x": 120, "y": 200, "w": 30, "h": 28 },
    "image_size": { "w": 736, "h": 981 }
  }
]
```

`image_size` lives on each lesion (not on the scan row) because if we ever support multiple images per scan, each could have different dimensions. Costs a few bytes per lesion; gives us a clean rendering pipeline in Flutter.

#### Source metadata JSONB shape

```json
{
  "detection_model": "acne-detection-zukbx/4",
  "classifier_model": "imfarzanansari/skintelligent-acne",
  "detection_latency_ms": 1850,
  "classifier_latency_ms": 145,
  "confidence_threshold": 0.4,
  "raw_responses": {
    "detection": { /* full Roboflow response, redacted for size if huge */ },
    "classification": { /* full classifier response */ }
  }
}
```

`raw_responses` is bulky but invaluable for debugging — if a user reports a weird result months later, you can re-derive everything from the original API output. Trade-off: bigger row size. We can prune this to a smaller summary if storage becomes an issue (it won't in v1).

---

## Storage buckets

### `profile-pictures` (private)

- Path convention: `{user_id}/avatar.jpg`
- Single object per user; uploading overwrites
- Read access: owner only
- Public URL never used — Flutter fetches via signed URL through Supabase SDK

### `scan-images` (private)

- Path convention: `{user_id}/{scan_id}.jpg`
- Read access: owner only
- Written at the same time as the `scans` row is inserted; if upload fails, the row insert should roll back (handle in the Flutter `ScanService` later)

Both buckets are **private** by default. Public URLs are never enabled — every read goes through Supabase's signed-URL flow, which respects RLS.

---

## Row-Level Security policies

RLS is enabled on every table. Without policies, RLS denies everything by default. The policies below grant exactly the access each user needs and nothing more.

### `profiles`

```sql
-- Anyone authenticated can read any profile (needed for future social features;
-- if we want strict privacy, change this to user_id = auth.uid()).
CREATE POLICY "Profiles are viewable by authenticated users"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

-- Users can update their own profile only.
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- INSERT is handled by the on_auth_user_created trigger. No INSERT policy needed
-- for the trigger because it runs as SECURITY DEFINER. Direct INSERTs from the
-- client are denied by default — that's desired.
```

**Open question:** Should profiles be readable by other authenticated users (for future "share scan with friend" features), or strictly private? Default is "readable by any authenticated user" but we can lock it to owner-only with a one-line change. Flag if you want it locked down.

### `scans`

```sql
-- Users can read their own scans.
CREATE POLICY "Users can read own scans"
  ON public.scans FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Users can insert scans where they own the row.
CREATE POLICY "Users can insert own scans"
  ON public.scans FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own scans (for editing notes / taken_at).
CREATE POLICY "Users can update own scans"
  ON public.scans FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- Users can delete their own scans.
CREATE POLICY "Users can delete own scans"
  ON public.scans FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
```

### Storage RLS

Storage has its own RLS layer. Policies operate on the `storage.objects` table.

```sql
-- profile-pictures: owner can read/write within their own folder.
CREATE POLICY "Own profile picture read"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'profile-pictures' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Own profile picture write"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'profile-pictures' AND (storage.foldername(name))[1] = auth.uid()::text);

-- (Same pattern for UPDATE and DELETE.)

-- scan-images: identical pattern, swap bucket_id.
```

`(storage.foldername(name))[1]` extracts the first path segment, so the policy enforces "the folder name must equal your user_id."

---

## Triggers and functions

### Auto-create profile on signup

The standard Supabase pattern. When `auth.users` gets a new row, we insert a corresponding `profiles` row using the metadata the app passed in during signup.

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name)
  VALUES (
    NEW.id,
    LOWER(COALESCE(NEW.raw_user_meta_data->>'username', SPLIT_PART(NEW.email, '@', 1))),
    COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'username')
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
```

This means the Flutter `signUp()` call passes `username` and (optionally) `display_name` in the user metadata, and the trigger handles the `profiles` row. The Flutter side never touches `profiles` during signup — it just sees a successful auth session and the profile already exists.

If the username collides with an existing one, the INSERT into `profiles` will fail due to the UNIQUE constraint, which surfaces as a Postgres error in the Flutter signup flow. We handle that the same way we already handle other auth errors (map to `AuthError(field: AuthField.username, ...)`).

### Auto-update `updated_at`

```sql
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at();
```

---

## What's NOT in this proposal

Calling these out so we don't accidentally over-build:

- **Annotated/boxed images.** The detection API returns an annotated JPEG (`image` field in zukbx's response). We can either re-render bounding boxes client-side in Flutter (lighter; what `scan_thumbnail.dart` already conceptually does) or store the annotated image in a third bucket. Going with client-side rendering for now to keep storage costs and complexity down.
- **Trend aggregations.** Things like 7-day rolling severity average are computed in Flutter from the raw scans, not stored as derived tables. Add a materialized view later if perf becomes an issue.
- **Routine/trigger journal.** The dermatologist's longitudinal-tracking ask (food, sleep, products, hormonal cycle correlated with severity) needs its own table. Defer to v2.
- **Multi-image scans.** Each scan = one selfie. If we want side / front / back angles per scan, we'd add a `scan_images` child table.
- **Soft delete.** Calling this out again because someone always asks. No.

---

## Open questions to resolve before SQL gets generated

1. **Profile visibility:** other authenticated users readable, or strictly owner-only?
2. **Username case-sensitivity:** I have it lower-cased for uniqueness. OK?
3. **`display_name` separate from `username`:** worth the extra field, or just one name field?
4. **`taken_at` editable by the user:** yes (in case they upload an old photo) or no (always equals scan-time)?
5. **`notes` field on scans:** include in v1 (room for v2 features to grow into it) or defer entirely?
6. **`raw_responses` in `source_metadata`:** keep full responses for debug value, or only summary fields to save bytes?

Once we settle those, I'll generate `supabase/migrations/0001_init.sql` with everything above as runnable SQL, and we'll move on to wiring up `AuthService` in Flutter.
