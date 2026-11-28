import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/github/github_api.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  List<GhTreeItem> _items = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final target = ref.read(sessionTargetProvider);
    if (api == null || target == null) {
      if (!mounted) return;
      setState(() {
        _error = 'Select account + repository first.';
        _items = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final commitSha =
          await api.getBranchCommitSha(target.owner, target.repo, target.branch);
      final treeSha =
          await api.getCommitTreeSha(target.owner, target.repo, commitSha);
      final items =
          await api.getRecursiveTree(target.owner, target.repo, treeSha);
      final blobs = items.where((e) => e.type == 'blob').toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (!mounted) return;
      setState(() {
        _items = blobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = GitHubApi.friendlyError(e);
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_deleting) return;
    final api = ref.read(apiProvider);
    final target = ref.read(sessionTargetProvider);
    if (api == null || target == null || _selected.isEmpty) return;

    final msgCtrl = TextEditingController(
      text: 'Delete ${_selected.length} file(s) from mobile',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Delete selected?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_selected.length} file(s) will be removed in one commit.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgCtrl,
              decoration:
                  const InputDecoration(labelText: 'Commit message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      msgCtrl.dispose();
      return;
    }

    final confirmedMessage = msgCtrl.text.trim().isEmpty
        ? 'Delete files from mobile'
        : msgCtrl.text.trim();
    msgCtrl.dispose();

    setState(() => _deleting = true);
    _showBlockingProgress(true);

    try {
      await api.deletePathsSingleCommit(
        owner: target.owner,
        repo: target.repo,
        branch: target.branch,
        message: confirmedMessage,
        pathsToDelete: _selected.toList(),
      );
      if (!mounted) return;
      _showBlockingProgress(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${_selected.length} file(s)')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showBlockingProgress(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(GitHubApi.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showBlockingProgress(bool show) {
    if (!mounted) return;
    if (show) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((e) => e.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(sessionTargetProvider);
    ref.listen(sessionTargetProvider, (prev, next) {
      if (prev != next) _load();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse & Delete'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _toggleAll,
              child: Text(
                _selected.length == _items.length ? 'None' : 'All',
                style: const TextStyle(color: AppColors.accent),
              ),
            ),
          IconButton(
            onPressed: _loading || _deleting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _selected.isEmpty || _deleting
          ? null
          : FloatingActionButton.extended(
              onPressed: _deleteSelected,
              backgroundColor: AppColors.danger,
              icon: const Icon(Icons.delete_outline),
              label: Text('Delete (${_selected.length})'),
            ),
      body: Column(
        children: [
          if (target != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${target.fullName} · ${target.branch}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(
                            child: Text(
                              'No files on this branch',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final item = _items[i];
                              final checked =
                                  _selected.contains(item.path);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: AppColors.primary,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  item.path,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: item.size != null
                                    ? Text(
                                        '${item.size} bytes',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    : null,
                                onChanged: _deleting
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(item.path);
                                          } else {
                                            _selected.remove(item.path);
                                          }
                                        });
                                      },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
