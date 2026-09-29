import 'dart:convert';

import 'package:flutter/services.dart';

import 'drawing_asset.dart';
import 'imported_art_store.dart';

/// One category of drawings, as the menu shows it.
class ArtCategory {
  const ArtCategory(this.id, this.title, this.icon);

  final String id;
  final String title;

  /// A key, not a glyph — the menu maps it to a drawn shape. Naming the
  /// picture rather than a font codepoint means the asset files survive a
  /// Flutter upgrade that renumbers the icon font.
  final String icon;
}

/// Loads the bundled art, plus anything imported onto this tablet.
///
/// Assets are parsed once and kept: a drawing is a few KB of JSON, ten of
/// them cost almost nothing to hold, and re-parsing on every visit to the
/// grid would make going back feel slower than going forward.
///
/// Imported drawings are merged in as equals rather than shelved
/// separately. A child does not know which animals came with the app, and
/// a "my imports" section would be a piece of filing to understand before
/// you can colour a fish.
class AssetLibrary {
  AssetLibrary._(this.categories, this._assets, this.importedIds);

  final List<ArtCategory> categories;
  final Map<String, DrawingAsset> _assets;

  /// Which drawings came from a bundle rather than from `assets/art/`.
  /// Only the editor cares — these are what can be deleted or re-exported.
  final Set<String> importedIds;

  static AssetLibrary? _cached;

  static Future<AssetLibrary> load() async {
    if (_cached != null) return _cached!;

    final indexJson = jsonDecode(
      await rootBundle.loadString('assets/art/index.json'),
    ) as Map<String, dynamic>;

    final categories = [
      for (final c in indexJson['categories'] as List)
        ArtCategory(
          (c as Map)['id'] as String,
          c['title'] as String,
          c['icon'] as String,
        ),
    ];

    final assets = <String, DrawingAsset>{};
    for (final entry in indexJson['assets'] as List) {
      final id = (entry as Map)['id'] as String;
      final raw = jsonDecode(
        await rootBundle.loadString('assets/art/$id.json'),
      ) as Map<String, dynamic>;
      assets[id] = DrawingAsset.fromJson(raw);
    }

    // Imported art is read through the same parser and dropped into the
    // same map. A failure here must never cost the shipped art: a tablet
    // with one bad import still opens to ten dinosaurs.
    final imported = <String>{};
    try {
      final store = await ImportedArtStore.open();
      for (final a in store.listAssets()) {
        assets[a.id] = a;
        imported.add(a.id);
      }
      final known = {for (final c in categories) c.id};
      for (final c in store.listCategories()) {
        if (known.add(c.id)) categories.add(c);
      }
      // A category with nothing left in it is a tile that opens onto an
      // empty grid, which reads as broken.
      categories.removeWhere(
        (c) => !assets.values.any((a) => a.category == c.id),
      );
    } catch (_) {
      // No imports, or no filesystem underneath. Neither is worth a screen.
    }

    return _cached = AssetLibrary._(categories, assets, imported);
  }

  /// Re-reads from disk after an import or a delete. The editor is the
  /// only caller — the child-facing screens never need to invalidate.
  static Future<AssetLibrary> reload() async {
    _cached = null;
    return load();
  }

  DrawingAsset? byId(String id) => _assets[id];

  List<DrawingAsset> inCategory(String categoryId) {
    final list = _assets.values
        .where((a) => a.category == categoryId)
        .toList()
      // Easiest first, so the first card a child meets is the one most
      // likely to end in a celebration rather than a giving-up.
      ..sort((a, b) {
        final d = a.difficulty.compareTo(b.difficulty);
        return d != 0 ? d : a.id.compareTo(b.id);
      });
    return list;
  }

  Iterable<DrawingAsset> get all => _assets.values;
}
