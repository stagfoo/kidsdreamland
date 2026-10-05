/// What went wrong, kept so it can be read off the tablet.
///
/// This app is used on a device with no console attached and no cable in it,
/// so an error that is only printed is an error nobody will ever see. Every
/// failure worth explaining is written here instead, survives the crash that
/// caused it, and can be copied out as text.
///
/// Deliberately small: a file of lines, capped, with no dependency beyond the
/// one the app already has for saving drawings. A crash reporter that needs a
/// network, an account or a build step is a crash reporter that will not be
/// working on the day it is needed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One thing that went wrong.
class CrashEntry {
  const CrashEntry({
    required this.when,
    required this.what,
    required this.detail,
    this.stack,
  });

  final DateTime when;

  /// Where it happened, in a few words: "tracing an image", "saving".
  final String what;

  final String detail;
  final String? stack;

  Map<String, dynamic> toJson() => {
        'when': when.toIso8601String(),
        'what': what,
        'detail': detail,
        if (stack != null) 'stack': stack,
      };

  static CrashEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final when = DateTime.tryParse('${json['when']}');
    if (when == null) return null;
    return CrashEntry(
      when: when,
      what: '${json['what'] ?? 'something'}',
      detail: '${json['detail'] ?? ''}',
      stack: json['stack'] as String?,
    );
  }

  /// One entry as the text that gets pasted into a message.
  String get asText {
    final buffer = StringBuffer()
      ..writeln('[${when.toIso8601String()}] $what')
      ..writeln(detail);
    final trace = stack;
    if (trace != null && trace.isNotEmpty) buffer.writeln(trace);
    return buffer.toString();
  }
}

class CrashLog {
  CrashLog._();

  static final CrashLog instance = CrashLog._();

  /// Kept in memory as well as on disk so the screen can draw without waiting,
  /// and so a failure to write does not also lose the entry.
  final List<CrashEntry> _entries = [];

  File? _file;

  /// Old entries are dropped rather than kept forever. The useful one is
  /// always the most recent, and an unbounded log on a tablet is a slow leak.
  static const _keep = 40;

  /// Loads what previous runs left behind. Safe to call more than once.
  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/crash_log.json');
      _file = file;
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      _entries
        ..clear()
        ..addAll([
          for (final entry in decoded) ?CrashEntry.fromJson(entry),
        ]);
    } catch (e) {
      // A log that cannot be read is not worth taking the app down for. The
      // in-memory list still works for this run.
    }
  }

  List<CrashEntry> get entries => List.unmodifiable(_entries.reversed);

  bool get isEmpty => _entries.isEmpty;

  /// Writes down one failure.
  ///
  /// Synchronous on purpose. This is called from error handlers, and the
  /// process may be about to die: an async write that has not flushed is an
  /// entry that never existed, which is exactly the case the log is for.
  void record(String what, Object error, [StackTrace? stack]) {
    final entry = CrashEntry(
      when: DateTime.now(),
      what: what,
      detail: error.toString(),
      // Trimmed: the first frames say what happened, and the rest is framework
      // plumbing that makes the text too long to paste into a message.
      stack: stack?.toString().split('\n').take(18).join('\n'),
    );
    _entries.add(entry);
    while (_entries.length > _keep) {
      _entries.removeAt(0);
    }
    _flush();
  }

  /// Writes down something notable that was not an error.
  void note(String what, String detail) {
    record(what, detail);
  }

  void _flush() {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        jsonEncode([for (final entry in _entries) entry.toJson()]),
        flush: true,
      );
    } catch (e) {
      // Out of space, or no permission. The entries are still in memory for
      // this run, which is better than failing inside an error handler.
    }
  }

  void clear() {
    _entries.clear();
    _flush();
  }

  /// The whole log as the text that gets pasted into a message.
  String get report {
    final buffer = StringBuffer()
      ..writeln('King Kids Dream Land — log')
      ..writeln('copied ${DateTime.now().toIso8601String()}')
      ..writeln('device ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('entries ${_entries.length}')
      ..writeln();
    if (_entries.isEmpty) {
      buffer.writeln('Nothing has gone wrong since the log was last cleared.');
      return buffer.toString();
    }
    // Newest first, matching the screen: the one being asked about is the one
    // that just happened.
    for (final entry in _entries.reversed) {
      buffer
        ..writeln(entry.asText)
        ..writeln('—');
    }
    return buffer.toString();
  }

  /// Catches what the framework and the engine would otherwise only print.
  ///
  /// Both handlers, because they catch different things: [FlutterError.onError]
  /// takes errors thrown while building, laying out and painting, and
  /// [PlatformDispatcher.onError] takes the asynchronous ones that never pass
  /// through the framework at all.
  void install() {
    final framework = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        details.context == null ? 'drawing the screen' : '${details.context}',
        details.exception,
        details.stack,
      );
      framework?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record('in the background', error, stack);
      // False: this is a log, not a handler. Claiming the error was dealt with
      // would hide it from the console during development as well.
      return false;
    };
  }
}
