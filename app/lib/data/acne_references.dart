import '../models/acne_reference.dart';

/// Static reference data for each lesion class the Roboflow detection
/// model emits. Keyed by lowercase singular form.
///
/// Image sourcing: DermNet NZ has a CC BY-NC-ND atlas suitable for
/// non-commercial educational use with attribution. Reference page:
///   https://dermnetnz.org/topics/acne-vulgaris
/// For PIH (dark_spot):
///   https://dermnetnz.org/topics/post-inflammatory-hyperpigmentation
///
/// To add real images later, drop the JPEGs into `assets/references/`
/// matching the `imageAsset` paths below. Until then, the scan-detail
/// reference sheet renders a placeholder icon via Image.asset's
/// errorBuilder — no crash.
///
/// Descriptions use plain language. Reviewed for accuracy against
/// standard dermatology references; phrasing should be retunable after
/// the Monday dermatologist meeting if she wants stricter or gentler
/// language.
const Map<String, AcneReference> _references = {
  'papule': AcneReference(
    displayName: 'Papule',
    bucket: 'inflammatory',
    description:
        'A small, raised, red bump under 5 mm across. Caused by '
        'inflammation around a clogged pore, without a visible pus tip. '
        'Tender to the touch but usually heals within a week or two.',
    imageAsset: 'assets/references/papule.jpg',
    attribution: 'Image: DermNet NZ — dermnetnz.org/topics/acne-vulgaris '
        '(CC BY-NC-ND)',
  ),
  'pustule': AcneReference(
    displayName: 'Pustule',
    bucket: 'inflammatory',
    description:
        'A papule with a visible white or yellow centre filled with pus. '
        'Inflammatory — squeezing risks scarring or spreading bacteria '
        'into the surrounding skin.',
    imageAsset: 'assets/references/pustule.jpg',
    attribution: 'Image: DermNet NZ — dermnetnz.org/topics/acne-vulgaris '
        '(CC BY-NC-ND)',
  ),
  'nodule': AcneReference(
    displayName: 'Nodule',
    bucket: 'inflammatory',
    description:
        'A large, hard, painful lump that sits deep beneath the skin. '
        'Can take weeks to resolve and often leaves scarring. Persistent '
        'nodular acne usually warrants a dermatologist visit.',
    imageAsset: 'assets/references/nodule.jpg',
    attribution: 'Image: DermNet NZ — dermnetnz.org/topics/acne-vulgaris '
        '(CC BY-NC-ND)',
  ),
  'comedone': AcneReference(
    displayName: 'Comedone',
    bucket: 'non_inflammatory',
    description:
        'A clogged pore without inflammation. When open at the surface, '
        'the plug oxidises and appears dark — a "blackhead". When covered '
        'by skin, it appears as a small flesh-coloured bump — a '
        '"whitehead".',
    imageAsset: 'assets/references/comedone.jpg',
    attribution: 'Image: DermNet NZ — dermnetnz.org/topics/acne-vulgaris '
        '(CC BY-NC-ND)',
  ),
  'dark_spot': AcneReference(
    displayName: 'Dark spot',
    bucket: 'post_acne',
    description:
        'Post-inflammatory hyperpigmentation (PIH) — a flat dark patch '
        'left after an acne lesion heals. Not active acne; the spot '
        'fades over weeks to months. Daily sunscreen prevents it from '
        'darkening further.',
    imageAsset: 'assets/references/dark_spot.jpg',
    attribution: 'Image: DermNet NZ — '
        'dermnetnz.org/topics/post-inflammatory-hyperpigmentation '
        '(CC BY-NC-ND)',
  ),
};

/// Look up the reference for a class name straight from the detection
/// model output. Handles common variants:
///   * plurals  ("papules" → "papule")
///   * casing   ("Comedone" / "COMEDONE" → "comedone")
///   * spelling ("dark-spot" / "dark spot" / "darkspot" → "dark_spot")
///   * abbreviations ("pih" → "dark_spot")
///
/// Returns null for classes we don't have a reference for — the caller
/// (scan-detail reference sheet) treats this as a soft "no info yet"
/// state rather than an error.
AcneReference? lookupAcneReference(String rawClassName) {
  final cleaned = rawClassName
      .toLowerCase()
      .trim()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  // Strip trailing 's' for plural normalization — model emits "papules",
  // we store under "papule".
  final singular = cleaned.endsWith('s') && cleaned.length > 1
      ? cleaned.substring(0, cleaned.length - 1)
      : cleaned;

  const aliases = <String, String>{
    'darkspot': 'dark_spot',
    'dark_spot': 'dark_spot',
    'pih': 'dark_spot',
    'hyperpigmentation': 'dark_spot',
    'whitehead': 'comedone',
    'blackhead': 'comedone',
  };
  final key = aliases[singular] ?? singular;

  return _references[key];
}
