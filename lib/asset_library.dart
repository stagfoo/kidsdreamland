import 'dart:convert';

import 'package:flutter/services.dart';

import 'drawing_asset.dart';

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

/// Loads the bundled art.
///
/// Assets are parsed once and kept: a drawing is a few KB of JSON, ten of
/// them cost almost nothing to hold, and re-parsing on every visit to the
/// grid would make going back feel slower than going forward.
class AssetLibrary {
  AssetLibrary._(this.categories, this._assets);

  final List<ArtCategory> categories;
  final Map<String, DrawingAsset> _assets;

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

    return _cached = AssetLibrary._(categories, assets);
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
