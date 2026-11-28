import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/github/github_api.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/zip_import.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  List<PushFile> _files = [];
  String? _sourceName;
  final _msgCtrl = TextEditingController(text: 'Update from mobile');
  bool _stripRoot = true;
  bool _busy = false;
  String _progress = '';
  double? _progressValue;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickZip() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _toast('Could not read ZIP');
      return;
    }
    try {
      final result = ZipImporter.fromBytes(
        Uint8List.fromList(bytes),
        stripRootFolder: _stripRoot,
      );
      setState(() {
        _files = result.files;
        _sourceName = f.name;
      });
      if (result.skippedJunk > 0) {
        _toast('Skipped ${result.skippedJunk} junk files');
      }
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final list = <PushFile>[];
    for (final f in res.files) {
      if (f.bytes == null || f.name.isEmpty) continue;
      list.add(PushFile(path: f.name, bytes: Uint8List.fromList(f.bytes!)));
    }
    if (list.isEmpty) {
      _toast('No readable files');
      return;
    }
    setState(() {
      _files = list;
      _sourceName = '${list.length} file(s)';
    });
  }

  Future<void> _pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;
    final root = Directory(dirPath);
    if (!await root.exists()) {
      _toast('Folder not found');
      return;
    }
    final list = <PushFile>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: dirPath).replaceAll('\\', '/');
      if (rel.contains('..')) continue;
      final name = p.basename(rel).toLowerCase();
      if (name == '.ds_store' || name == 'thumbs.db') continue;
      if (rel.contains('__MACOSX/')) continue;
      try {
        final bytes = await entity.readAsBytes();
        list.add(PushFile(path: rel, bytes: Uint8List.fromList(bytes)));
      } catch (_) {}
    }
    list.sort((a, b) => a.path.compareTo(b.path));
    if (list.isEmpty) {
      _toast('Folder is empty');
      return;
    }
    setState(() {
      _files = list;
      _sourceName = p.basename(dirPath);
    });
  }

  Future<void> _push() async {
    final api = ref.read(apiProvider);
    final target = ref.read(sessionTargetProvider);
    if (api == null) {
      _toast('Select a GitHub account');
      return;
    }
    if (target == null) {
      _toast('Select a repository first');
      return;
    }
    if (_files.isEmpty) {
      _toast('Pick ZIP, files, or folder first');
      return;
    }
    final msg =
        _msgCtrl.text.trim().isEmpty ? 'Update from mobile' : _msgCtrl.text.trim();

    setState(() {
      _busy = true;
      _progress = 'Starting…';
      _progressValue = 0;
    });

    try {
      final sha = await api.pushFilesSingleCommit(
        owner: target.owner,
        repo: target.repo,
        branch: target.branch,
        message: msg,
        files: _files,
        onProgress: (s) {
          if (!mounted) return;
          setState(() {
            _progress = s;
            final m = RegExp(r'blob (\d+)/(\d+)').firstMatch(s);
            if (m != null) {
              final a = int.parse(m.group(1)!);
              final b = int.parse(m.group(2)!);
              _progressValue = a / b;
            }
          });
        },
      );
      if (!mounted) return;
      _toast('Pushed · ${sha.substring(0, 7)} · ${_files.length} files');
      setState(() {
        _files = [];
        _sourceName = null;
        _progress = '';
        _progressValue = null;
      });
    } catch (e) {
      _toast(GitHubApi.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(sessionTargetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Push')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TargetBanner(target: target),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 48, color: AppColors.accent.withValues(alpha: 0.9)),
                const SizedBox(height: 12),
                Text(
                  _sourceName ?? 'Nothing selected',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _files.isEmpty
                      ? 'ZIP · multiple files · whole folder'
                      : '${_files.length} files ready',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickZip,
                        icon: const Icon(Icons.folder_zip_outlined, size: 18),
                        label: const Text('ZIP'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickFiles,
                        icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
                        label: const Text('Files'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _pickFolder,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Folder'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Strip root folder (ZIP)', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'If ZIP has one top folder, remove it',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  value: _stripRoot,
                  activeColor: AppColors.primary,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                            _stripRoot = v;
                            if (_sourceName != null &&
                                (_sourceName!.toLowerCase().endsWith('.zip'))) {
                              _files = [];
                              _sourceName = null;
                            }
                          }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _msgCtrl,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Commit message',
              prefixIcon: Icon(Icons.commit),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(
              value: _progressValue,
              backgroundColor: AppColors.borderDark,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(_progress,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _busy || _files.isEmpty || target == null ? null : _push,
            icon: const Icon(Icons.cloud_upload),
            label: Text(_busy ? 'Pushing…' : 'Commit & Push'),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Files in commit', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._files.take(100).map(
                  (f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.path,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                        Text(
                          _fmtSize(f.bytes.length),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            if (_files.length > 100)
              Text('+ ${_files.length - 100} more…',
                  style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  String _fmtSize(int n) {
    if (n < 1024) return '${n}B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _TargetBanner extends StatelessWidget {
  final SessionTarget? target;
  const _TargetBanner({required this.target});

  @override
  Widget build(BuildContext context) {
    if (target == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: const Text(
          'Select a repository on the Repos tab first.',
          style: TextStyle(color: AppColors.warning),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${target!.fullName}  ·  ${target!.branch}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
