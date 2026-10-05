/// The adult's side of the app: get drawings in, get packs out.
///
/// Four things happen here and nothing else — trace a PNG, open a pack
/// somebody sent, send a pack somebody wants, and throw away a drawing
/// that did not work. Everything a child touches is on the other side of
/// [GrownupGate].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'art_bundle.dart';
import 'asset_library.dart';
import 'crash_log.dart';
import 'crash_log_screen.dart';
import 'artwork_painter.dart';
import 'drawing_asset.dart';
import 'imported_art_store.dart';
import 'png_decode.dart';
import 'theme.dart';
import 'trace_editor_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.library});

  final AssetLibrary library;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late AssetLibrary _library = widget.library;
  bool _busy = false;

  List<DrawingAsset> get _imported => [
        for (final id in _library.importedIds)
          if (_library.byId(id) != null) _library.byId(id)!,
      ]..sort((a, b) => a.id.compareTo(b.id));

  @override
  Widget build(BuildContext context) {
    final imported = _imported;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Art tool'),
        backgroundColor: Sky.card,
        actions: [
          // The way to the log. Here rather than on the menu because it is
          // text, and everything with text in it lives behind the gate.
          IconButton(
            tooltip: 'Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CrashLogScreen()),
            ),
            icon: Badge(
              // The count, so a problem announces itself rather than waiting
              // to be gone looking for.
              isLabelVisible: !CrashLog.instance.isEmpty,
              label: Text('${CrashLog.instance.entries.length}'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _tracePng,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Trace a PNG'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importBundle,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Open a pack'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || imported.isEmpty ? null : _exportAll,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text('Export all (${imported.length})'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: imported.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nothing imported yet.\n\n'
                        'Trace a transparent PNG of line art, or open a '
                        'pack exported from another tablet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: imported.length,
                    itemBuilder: (context, i) => _ImportedCard(
                      asset: imported[i],
                      onExport: () => _exportOne(imported[i].id),
                      onDelete: () => _delete(imported[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _tracePng() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Pick a transparent PNG',
      type: FileType.image,
    );
    if (files.isEmpty) return;

    setState(() => _busy = true);
    DecodedImage? decoded;
    try {
      decoded = await decodeImageForTracing(await files.first.readAsBytes());
    } catch (e, stack) {
      CrashLog.instance.record('reading an image', e, stack);
      setState(() => _busy = false);
      _say('Could not read that image: $e');
      return;
    }
    setState(() => _busy = false);
    if (!mounted) {
      decoded.dispose();
      return;
    }

    final name = files.first.name.replaceAll(RegExp(r'\.[^.]*$'), '');
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TraceEditorScreen(
          image: decoded!,
          suggestedName: name,
          knownCategories: _library.categories,
        ),
      ),
    );
    decoded.dispose();

    if (saved == true) await _refresh();
  }

  Future<void> _importBundle() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Pick a pack',
      type: FileType.any,
    );
    if (files.isEmpty) return;

    setState(() => _busy = true);
    try {
      final text = utf8.decode(await files.first.readAsBytes());
      final result = ArtBundle.decode(text);
      final store = await ImportedArtStore.open();
      final count = await store.importBundle(result);
      await _refresh();

      // Said plainly, including what did not come through. An import that
      // silently drops three drawings is worse than one that refuses.
      final parts = <String>['Imported $count drawing(s).'];
      if (result.skipped.isNotEmpty) {
        parts.add('Skipped ${result.skipped.length}: '
            '${result.skipped.take(3).join('; ')}');
        // Every one of them, not the three the message has room for.
        CrashLog.instance.note(
          'opening a pack',
          'skipped ${result.skipped.length}: ${result.skipped.join('; ')}',
        );
      }
      if (result.fromNewerBuild) {
        parts.add('That pack was made by a newer build.');
      }
      _say(parts.join(' '));
    } on BundleFormatException catch (e, stack) {
      CrashLog.instance.record('opening a pack', e, stack);
      _say('Not a pack: ${e.message}');
    } catch (e, stack) {
      CrashLog.instance.record('opening a pack', e, stack);
      _say('Could not open that pack: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAll() async {
    final store = await ImportedArtStore.open();
    await _write(store.exportAll(), 'kingkids-pack');
  }

  Future<void> _exportOne(String id) async {
    final store = await ImportedArtStore.open();
    await _write(store.exportOne(id), id);
  }

  Future<void> _write(ArtBundle bundle, String basename) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save pack',
        fileName: '$basename$kBundleExtension',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
      );
      // A cancelled save is a decision, not a failure, and saying nothing
      // is the right response to it.
      if (uri != null) _say('Saved ${bundle.assets.length} drawing(s).');
    } catch (e) {
      _say('Could not save: $e');
    }
  }

  Future<void> _delete(DrawingAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${asset.title}?'),
        content: const Text(
          'Drawings a child already finished stay in the gallery. This '
          'only removes the thing they can colour in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final store = await ImportedArtStore.open();
    await store.delete(asset.id);
    await _refresh();
  }

  Future<void> _refresh() async {
    final library = await AssetLibrary.reload();
    if (mounted) setState(() => _library = library);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ImportedCard extends StatelessWidget {
  const _ImportedCard({
    required this.asset,
    required this.onExport,
    required this.onDelete,
  });

  final DrawingAsset asset;
  final VoidCallback onExport, onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Sky.card,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: CustomPaint(
                size: Size.infinite,
                painter: ThumbnailPainter(asset),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              asset.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${asset.category} · ${asset.regions.length} regions · '
            '${asset.guideDots.length} dots',
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.upload_rounded, size: 18),
                tooltip: 'Export this one',
                onPressed: onExport,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
