import 'package:flutter_test/flutter_test.dart';
import 'package:kidsdreamland/crash_log.dart';

void main() {
  // No load(), so no file is ever opened: _flush falls straight back out and
  // the log is exercised purely in memory, which is where all of its rules are.
  setUp(CrashLog.instance.clear);

  group('what it keeps', () {
    test('starts empty and says so', () {
      expect(CrashLog.instance.isEmpty, isTrue);
      expect(CrashLog.instance.entries, isEmpty);
      expect(CrashLog.instance.report, contains('Nothing has gone wrong'));
    });

    test('keeps what it is given', () {
      CrashLog.instance.record('tracing an image', 'it went wrong');
      final entries = CrashLog.instance.entries;
      expect(entries, hasLength(1));
      expect(entries.single.what, 'tracing an image');
      expect(entries.single.detail, contains('it went wrong'));
    });

    test('hands them back newest first', () {
      // The one being asked about is the one that just happened, so it should
      // not be at the bottom of a list of forty.
      CrashLog.instance.record('first', 'a');
      CrashLog.instance.record('second', 'b');
      expect(CrashLog.instance.entries.first.what, 'second');
    });

    test('drops the oldest rather than growing without end', () {
      for (var i = 0; i < 60; i++) {
        CrashLog.instance.record('entry $i', 'detail $i');
      }
      final entries = CrashLog.instance.entries;
      expect(entries, hasLength(40));
      // Newest kept, oldest gone.
      expect(entries.first.what, 'entry 59');
      expect(entries.last.what, 'entry 20');
    });

    test('clearing empties it', () {
      CrashLog.instance.record('something', 'bad');
      CrashLog.instance.clear();
      expect(CrashLog.instance.isEmpty, isTrue);
    });

    test('a note is kept like a failure, because it is read the same way', () {
      CrashLog.instance.note('opening a pack', 'skipped 3: a; b; c');
      expect(CrashLog.instance.entries.single.detail, contains('skipped 3'));
    });
  });

  group('the stack', () {
    test('is trimmed to the frames that say what happened', () {
      // A full Flutter stack is hundreds of lines of framework plumbing, which
      // makes the report too long to paste into a message.
      final long = StackTrace.fromString(
        [for (var i = 0; i < 80; i++) '#$i  frame $i'].join('\n'),
      );
      CrashLog.instance.record('deep', 'boom', long);
      final stack = CrashLog.instance.entries.single.stack!;
      expect(stack.split('\n'), hasLength(18));
      expect(stack, contains('frame 0'));
      expect(stack, isNot(contains('frame 40')));
    });

    test('is absent rather than empty when there was none', () {
      CrashLog.instance.record('no stack', 'boom');
      expect(CrashLog.instance.entries.single.stack, isNull);
    });
  });

  group('the copied report', () {
    test('carries every entry and says which device', () {
      CrashLog.instance.record('tracing an image', 'bad PNG');
      CrashLog.instance.record('saving a trace', 'disk full');
      final report = CrashLog.instance.report;
      expect(report, contains('tracing an image'));
      expect(report, contains('bad PNG'));
      expect(report, contains('saving a trace'));
      expect(report, contains('device '));
      expect(report, contains('entries 2'));
    });

    test('puts the newest first, matching the screen', () {
      CrashLog.instance.record('older', 'a');
      CrashLog.instance.record('newer', 'b');
      final report = CrashLog.instance.report;
      expect(report.indexOf('newer'), lessThan(report.indexOf('older')));
    });
  });

  group('storage', () {
    test('an entry round-trips through json', () {
      final entry = CrashEntry(
        when: DateTime.utc(2026, 10, 5, 14, 30),
        what: 'tracing an image',
        detail: 'bad PNG',
        stack: '#0 frame',
      );
      final back = CrashEntry.fromJson(entry.toJson())!;
      expect(back.when, entry.when);
      expect(back.what, entry.what);
      expect(back.detail, entry.detail);
      expect(back.stack, entry.stack);
    });

    test('a malformed stored entry is stepped over, not fatal', () {
      // The log is read at start-up, so a bad line in it must not be the thing
      // that stops the app opening.
      expect(CrashEntry.fromJson(null), isNull);
      expect(CrashEntry.fromJson('nonsense'), isNull);
      expect(CrashEntry.fromJson({'what': 'no timestamp'}), isNull);
      expect(CrashEntry.fromJson({'when': 'not a date'}), isNull);
    });

    test('an entry missing its wording still loads', () {
      final back = CrashEntry.fromJson({'when': '2026-10-05T14:30:00.000Z'})!;
      expect(back.what, 'something');
      expect(back.detail, isEmpty);
    });
  });
}
