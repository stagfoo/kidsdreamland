/// Where drawings that did not ship with the app live.
///
/// One JSON file per drawing, exactly the same shape as the files in
/// `assets/art/` — so an imported drawing is not a second kind of thing
/// the rest of the app has to know about. It parses through the same
/// `DrawingAsset.fromJson`, renders through the same painter, and can be
/// copied straight into `assets/art/` later if it earns a place in the
/// shipped set.
///
/// Category titles live in one small file beside them, because a category
/// is the one piece of information no single drawing owns.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'art_bundle.dart';
import 'asset_library.dart';
import 'drawing_asset.dart';

class ImportedArtStore {
  ImportedArtStore._(this._dir);

  final Directory _dir;
  static ImportedArtStore? _cached;

  static Future<ImportedArtStore> open() async {
    if (_cached != null) return _cached!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/imported');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cached = ImportedArtStore._(dir);
  }

  File _assetFile(String id) => File('${_dir.path}/$id.json');
  File get _categoriesFile => File('${_dir.path}/categories.json');

  /// Every drawing that still parses.
  ///
  /// A file that does not is left on disk and skipped rather than deleted:
  /// it is somebody's work, and the drawing grid refusing to open is a
  /// far worse outcome than one animal missing from it.
  List<DrawingAsset> listAssets() {
    final out = <DrawingAsset>[];
    for (final f in _dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      if (f.path.endsWith('categories.json')) continue;
      try {
        out.add(DrawingAsset.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
        ));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  /// The raw JSON, for putting a drawing back into a bundle unchanged.
  List<Map<String, dynamic>> listRaw() {
    final out = <Map<String, dynamic>>[];
    for (final f in _dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      if (f.path.endsWith('categories.json')) continue;
      try {
        out.add(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    return out;
  }

  List<ArtCategory> listCategories() {
    if (!_categoriesFile.existsSync()) return const [];
    try {
      final raw = jsonDecode(_categoriesFile.readAsStringSync()) as List;
      return [
        for (final c in raw)
          if (c is Map && c['id'] is String)
            ArtCategory(
              c['id'] as String,
              c['title'] as String? ?? c['id'] as String,
              c['icon'] as String? ?? 'star',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Writes one drawing, replacing any drawing with the same id.
  ///
  /// Same id means the same drawing re-imported or re-traced, and keeping
  /// both would fill the grid with near-duplicates nobody can tell apart
  /// from a thumbnail.
  Future<void> saveAsset(
    Map<String, dynamic> assetJson, {
    ArtCategory? category,
  }) async {
    final id = assetJson['id'] as String;
    _assetFile(id).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(assetJson),
    );
    if (category != null) await _mergeCategory(category);
  }

  /// Takes everything readable out of a bundle.
  Future<int> importBundle(BundleReadResult result) async {
    for (final c in result.bundle.categories) {
      await _mergeCategory(c);
    }
    for (final a in result.bundle.assets) {
      await saveAsset(a);
    }
    return result.bundle.assets.length;
  }

  Future<void> _mergeCategory(ArtCategory category) async {
    final existing = listCategories();
    final merged = <String, ArtCategory>{
      for (final c in existing) c.id: c,
      category.id: category,
    };
    _categoriesFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert([
        for (final c in merged.values)
          {'id': c.id, 'title': c.title, 'icon': c.icon},
      ]),
    );
  }

  Future<void> delete(String id) async {
    final f = _assetFile(id);
    if (f.existsSync()) f.deleteSync();
  }

  /// Everything imported, packed up to move to another tablet.
  ArtBundle exportAll({String name = 'my drawings'}) {
    final assets = listRaw();
    final used = {for (final a in assets) a['category'] as String?};
    return ArtBundle(
      name: name,
      categories: [
        for (final c in listCategories())
          if (used.contains(c.id)) c,
      ],
      assets: assets,
    );
  }

  /// One drawing on its own, which is the usual thing to send someone.
  ArtBundle exportOne(String id) {
    final assets = [
      for (final a in listRaw())
        if (a['id'] == id) a,
    ];
    final categoryId = assets.isEmpty ? null : assets.first['category'];
    return ArtBundle(
      name: id,
      categories: [
        for (final c in listCategories())
          if (c.id == categoryId) c,
      ],
      assets: assets,
    );
  }
}
