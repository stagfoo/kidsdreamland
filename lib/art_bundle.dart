/// The transfer format: a pack of drawings as one file.
///
/// One JSON file rather than a zip, on purpose. The app renders drawings
/// from vector paths and never needs the source PNG at runtime, so there
/// is nothing binary to carry — and a plain text file needs no archive
/// dependency, unpacks nowhere, survives being emailed to yourself, and
/// can be opened and read when something looks wrong on the tablet.
///
/// Reading is deliberately forgiving, the same way loading a saved drawing
/// is: one malformed animal costs you that animal, never the other nine.
/// A bundle arriving from a future build with fields this one has never
/// heard of still opens.
library;

import 'dart:convert';

import 'asset_library.dart';
import 'drawing_asset.dart';

/// Stamped into every bundle so a file picked by hand can be recognised
/// as one before anything tries to parse it as a drawing.
const String kBundleFormat = 'kidsdreamland.art';

/// Bumped only for a change that older builds could not read correctly.
/// Adding a field does not count — unknown fields are ignored on the way
/// in, which is what makes the format additive.
const int kBundleVersion = 1;

/// The extension bundles are written with. Ends in `.json` so Android's
/// file picker offers it without a custom MIME type, and so tapping it on
/// a desktop opens something readable.
const String kBundleExtension = '.kdart.json';

/// A pack of drawings, on its way in or out.
class ArtBundle {
  const ArtBundle({
    required this.name,
    required this.categories,
    required this.assets,
  });

  /// What the pack is called, for the import summary. Never shown to a
  /// child.
  final String name;

  final List<ArtCategory> categories;

  /// Raw asset JSON rather than parsed `DrawingAsset`s: a bundle is a
  /// carrier, and re-encoding through the parser on the way out would
  /// quietly drop any field this build does not know about.
  final List<Map<String, dynamic>> assets;

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': kBundleFormat,
        'version': kBundleVersion,
        'name': name,
        'categories': [
          for (final c in categories)
            {'id': c.id, 'title': c.title, 'icon': c.icon},
        ],
        'assets': assets,
      });

  /// Reads a bundle, keeping whatever is usable.
  ///
  /// Throws only when the file is not a bundle at all. Everything else —
  /// a drawing with a broken path, a category with no id — is reported in
  /// [BundleReadResult.skipped] and left behind.
  static BundleReadResult decode(String source) {
    final Object? root;
    try {
      root = jsonDecode(source);
    } on FormatException {
      throw const BundleFormatException('not a JSON file');
    }
    if (root is! Map) {
      throw const BundleFormatException('not a bundle');
    }
    if (root['format'] != kBundleFormat) {
      throw const BundleFormatException('not a King Kids Dream Land pack');
    }

    final categories = <ArtCategory>[];
    for (final raw in (root['categories'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! String || id.isEmpty) continue;
      categories.add(ArtCategory(
        id,
        raw['title'] as String? ?? id,
        raw['icon'] as String? ?? 'star',
      ));
    }

    final assets = <Map<String, dynamic>>[];
    final parsed = <DrawingAsset>[];
    final skipped = <String>[];

    for (final raw in (root['assets'] as List? ?? const [])) {
      if (raw is! Map) {
        skipped.add('a drawing that was not an object');
        continue;
      }
      final json = raw.cast<String, dynamic>();
      try {
        // Parsed here and not just on load, so a bundle that would break
        // the grid is caught while the person who made it is still
        // holding the tablet.
        parsed.add(DrawingAsset.fromJson(json));
        assets.add(json);
      } on AssetFormatException catch (e) {
        skipped.add('${json['id'] ?? 'a drawing'}: ${e.message}');
      } catch (e) {
        skipped.add('${json['id'] ?? 'a drawing'}: $e');
      }
    }

    // A drawing whose category is missing would load fine and then appear
    // on no screen at all, which reads as the import having silently done
    // nothing. Give it a home instead.
    final known = {for (final c in categories) c.id};
    for (final a in parsed) {
      if (known.add(a.category)) {
        categories.add(ArtCategory(a.category, a.category, 'star'));
      }
    }

    return BundleReadResult(
      bundle: ArtBundle(
        name: root['name'] as String? ?? 'pack',
        categories: categories,
        assets: assets,
      ),
      drawings: parsed,
      skipped: skipped,
      fromNewerBuild: (root['version'] as num? ?? 0) > kBundleVersion,
    );
  }
}

/// What came back from reading a file, including what did not survive.
class BundleReadResult {
  const BundleReadResult({
    required this.bundle,
    required this.drawings,
    required this.skipped,
    required this.fromNewerBuild,
  });

  final ArtBundle bundle;

  /// The drawings that parsed, already usable.
  final List<DrawingAsset> drawings;

  /// One line per drawing that did not, for the adult doing the import.
  final List<String> skipped;

  /// The pack declares a version this build does not know. It was read
  /// anyway — fields are additive — but anything new in it was ignored.
  final bool fromNewerBuild;
}

class BundleFormatException implements Exception {
  const BundleFormatException(this.message);
  final String message;

  @override
  String toString() => 'BundleFormatException: $message';
}
