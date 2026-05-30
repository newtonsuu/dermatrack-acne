import 'package:flutter/foundation.dart';

/// Educational reference for one lesion class. Surfaced on the scan-detail
/// screen when the user taps a class row in the "Detected lesions" list.
///
/// Three reasons this exists, in priority order:
///   1. Builds user trust — the app shows its work instead of being a black
///      box that says "Papule" with no explanation of what a papule is.
///   2. Educational value — most users have never been taught the visual
///      difference between an inflammatory papule, an inflamed pustule, and
///      a non-inflammatory comedone.
///   3. Thesis defensibility — a panel asking "how does the app help users
///      understand the diagnosis?" has a concrete answer.
@immutable
class AcneReference {
  const AcneReference({
    required this.displayName,
    required this.bucket,
    required this.description,
    this.imageAsset,
    this.attribution,
  });

  /// Title-cased class name to show in the sheet header (e.g. "Papule").
  final String displayName;

  /// One of the schema's coarse buckets — `inflammatory`,
  /// `non_inflammatory`, `post_acne`. Drives the colored bucket chip.
  final String bucket;

  /// 1-2 sentence description. Plain language; medically accurate but not
  /// clinical jargon. Avoids prescriptive language ("you should...") in
  /// favor of descriptive ("this is when...").
  final String description;

  /// Path to a bundled Flutter asset image. Null means we haven't sourced
  /// one yet — the UI falls back to an icon placeholder in that case.
  final String? imageAsset;

  /// Attribution string (source + license) shown small at the bottom of
  /// the sheet. Required by DermNet NZ's CC-BY-NC-ND license.
  final String? attribution;
}
