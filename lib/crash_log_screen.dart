/// The log, on screen, with a button that copies it.
///
/// Behind the grown-up gate with the rest of the art tool, and text for the
/// same reason that is: the audience for this is the person being asked "what
/// did it say?", not the child using the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crash_log.dart';
import 'theme.dart';

class CrashLogScreen extends StatefulWidget {
  const CrashLogScreen({super.key});

  @override
  State<CrashLogScreen> createState() => _CrashLogScreenState();
}

class _CrashLogScreenState extends State<CrashLogScreen> {
  @override
  Widget build(BuildContext context) {
    final entries = CrashLog.instance.entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        backgroundColor: Sky.card,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: CrashLog.instance.report),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied — paste it into a message')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy all'),
          ),
          if (entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                setState(CrashLog.instance.clear);
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing has gone wrong since this was last cleared.\n\n'
                  'If something does, it will be written here — including the '
                  'things the app recovers from quietly, which are usually the '
                  'ones worth knowing about.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Sky.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.what,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${entry.when.hour.toString().padLeft(2, '0')}:'
                            '${entry.when.minute.toString().padLeft(2, '0')} '
                            '${entry.when.day}/${entry.when.month}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Selectable, so one entry can be taken without the rest
                      // — the copy button is for the whole log, and sometimes
                      // only the newest line is wanted.
                      SelectableText(
                        entry.detail,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (entry.stack case final stack?) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          stack,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
