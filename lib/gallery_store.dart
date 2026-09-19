import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'artwork.dart';
import 'artwork_painter.dart';
import 'drawing_asset.dart';
import 'theme.dart';
import 'trace_guide.dart';

/// One finished piece in the gallery.
class SavedPiece {
  const SavedPiece({
    required this.id,
    required this.assetId,
    required this.savedAt,
    required this.pngPath,
  });

  final String id;
  final String assetId;
  final DateTime savedAt;
  final String pngPath;
}

/// Where finished drawings live.
///
/// Each piece is a PNG (what the gallery shows, and what gets exported)
/// plus the artwork JSON beside it. Keeping the JSON means a drawing can
/// be reopened and added to; keeping the PNG means the gallery draws
/// instantly rather than re-rendering ten drawings to show ten thumbnails.
class GalleryStore {
  GalleryStore._(this._dir);

  final Directory _dir;
  static GalleryStore? _cached;

  static Future<GalleryStore> open() async {
    if (_cached != null) return _cached!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/gallery');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cached = GalleryStore._(dir);
  }

  /// Newest first — the thing just finished is the thing worth seeing.
  Future<List<SavedPiece>> list() async {
    final pieces = <SavedPiece>[];
    for (final f in _dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final id = json['id'] as String;
        final png = File('${_dir.path}/$id.png');
        if (!png.existsSync()) continue;
        pieces.add(SavedPiece(
          id: id,
          assetId: json['assetId'] as String,
          savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
          pngPath: png.path,
        ));
      } catch (_) {
        // A half-written file from an interrupted save. Skipping it keeps
        // the rest of the gallery openable.
        continue;
      }
    }
    pieces.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return pieces;
  }

  /// Saves [artwork] over [asset], returning the stored piece.
  Future<SavedPiece> save({
    required DrawingAsset asset,
    required Artwork artwork,
    required int savedAtMs,
  }) async {
    // The asset id plus a timestamp: a child colouring the same T-Rex
    // twice has made two drawings, not overwritten one.
    final id = '${asset.id}_$savedAtMs';
    final png = await renderPng(asset: asset, artwork: artwork);

    final pngFile = File('${_dir.path}/$id.png');
    await pngFile.writeAsBytes(png, flush: true);

    await File('${_dir.path}/$id.json').writeAsString(
      jsonEncode({
        'id': id,
        'assetId': asset.id,
        'savedAt': savedAtMs,
        'artwork': artwork.toJson(),
      }),
      flush: true,
    );

    return SavedPiece(
      id: id,
      assetId: asset.id,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      pngPath: pngFile.path,
    );
  }

  Future<Artwork?> reopen(String id) async {
    final f = File('${_dir.path}/$id.json');
    if (!f.existsSync()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Artwork.fromJson(
          (json['artwork'] as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    for (final ext in ['png', 'json']) {
      final f = File('${_dir.path}/$id.$ext');
      if (f.existsSync()) await f.delete();
    }
  }

  /// Puts a finished piece in the device's own photo gallery.
  ///
  /// Returns false rather than throwing when permission is refused: a
  /// child tapping export and getting a crash is far worse than a child
  /// tapping export and nothing visible happening.
  static Future<bool> exportToDeviceGallery(String pngPath) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return false;
      }
      await Gal.putImage(pngPath, album: 'King Kids Dream Land');
      return true;
    } catch (e) {
      debugPrint('gallery export failed: $e');
      return false;
    }
  }

  /// Renders a drawing to PNG bytes at the asset's own resolution.
  ///
  /// Rendered off the widget tree, so it is exactly the drawing and not
  /// whatever chrome happened to be on screen.
  static Future<List<int>> renderPng({
    required DrawingAsset asset,
    required Artwork artwork,
  }) async {
    final size = Size(asset.canvasSize.x, asset.canvasSize.y);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // An exported PNG needs its own ground: transparency reads as black
    // in most photo viewers, which would make every drawing look ruined.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Sky.background,
    );

    ArtworkPainter(
      asset: asset,
      artwork: artwork,
      progress: TraceProgress(const []),
      // No dashes and no checkpoints in the saved picture — those are
      // scaffolding, and what gets kept is the drawing.
      showGuide: false,
      revision: 0,
    ).paint(canvas, size);

    final image = await recorder
        .endRecording()
        .toImage(size.width.round(), size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
