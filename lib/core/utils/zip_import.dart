import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../github/github_api.dart';

class ZipImportResult {
  final List<PushFile> files;
  final int skippedJunk;
  const ZipImportResult({required this.files, this.skippedJunk = 0});
}

class ZipImporter {
  ZipImporter._();

  static const _junkNames = {
    '.ds_store',
    'thumbs.db',
    'desktop.ini',
  };

  static ZipImportResult fromBytes(
    Uint8List zipBytes, {
    bool stripRootFolder = true,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    } catch (e) {
      throw Exception('Invalid or corrupted ZIP file');
    }

    final entries = <String, Uint8List>{};
    var junk = 0;

    for (final file in archive.files) {
      if (!file.isFile) continue;
      var name = file.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains('..')) {
        throw Exception('Unsafe path in ZIP blocked: ${file.name}');
      }
      final base = p.basename(name).toLowerCase();
      if (_junkNames.contains(base) || name.contains('__MACOSX/')) {
        junk++;
        continue;
      }
      final content = file.content;
      if (content is! List<int>) continue;
      entries[name] = Uint8List.fromList(content);
    }

    final paths = entries.keys.toList();
    if (stripRootFolder && paths.isNotEmpty) {
      final firstSegs = paths
          .map((e) => e.split('/').first)
          .where((e) => e.isNotEmpty)
          .toSet();
      if (firstSegs.length == 1) {
        final root = firstSegs.first;
        final allUnder =
            paths.every((e) => e == root || e.startsWith('$root/'));
        if (allUnder) {
          final rebuilt = <String, Uint8List>{};
          for (final e in entries.entries) {
            if (e.key == root) continue;
            final stripped = e.key.startsWith('$root/')
                ? e.key.substring(root.length + 1)
                : e.key;
            if (stripped.isEmpty) continue;
            rebuilt[stripped] = e.value;
          }
          entries
            ..clear()
            ..addAll(rebuilt);
        }
      }
    }

    final files = entries.entries
        .map((e) => PushFile(path: e.key, bytes: e.value))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      throw Exception('ZIP has no usable files');
    }

    return ZipImportResult(files: files, skippedJunk: junk);
  }

  static Future<ZipImportResult> fromFile(
    File file, {
    bool stripRootFolder = true,
  }) async {
    final bytes = await file.readAsBytes();
    return fromBytes(Uint8List.fromList(bytes),
        stripRootFolder: stripRootFolder);
  }
}
