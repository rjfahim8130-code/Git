import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/github/github_api.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class ReposScreen extends ConsumerStatefulWidget {
  const ReposScreen({super.key});

  @override
  ConsumerState<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends ConsumerState<ReposScreen> {
  List<GhRepo> _repos = [];
  List<String> _branches = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  String? _selectedFullName;
  String? _selectedBranch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRepos());
  }

  Future<void> _loadRepos() async {
    final api = ref.read(apiProvider);
    if (api == null) {
      setState(() {
        _error = 'Add & select a GitHub account first.';
        _repos = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listRepos();
      final session = ref.read(sessionTargetProvider);
      setState(() {
        _repos = list;
        _loading = false;
        if (session != null) {
          _selectedFullName = session.fullName;
          _selectedBranch = session.branch;
        }
      });
      if (_selectedFullName != null) {
        await _loadBranches(_selectedFullName!);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = api.friendlyError(e);
      });
    }
  }

  Future<void> _loadBranches(String fullName) async {
    final api = ref.read(apiProvider);
    if (api == null) return;
    final parts = fullName.split('/');
    if (parts.length != 2) return;
    try {
      final branches = await api.listBranches(parts[0], parts[1]);
      final repo = _repos.cast<GhRepo?>().firstWhere(
            (r) => r?.fullName == fullName,
            orElse: () => null,
          );
      setState(() {
        _branches = branches;
        _selectedBranch = branches.contains(_selectedBranch)
            ? _selectedBranch
            : (repo?.defaultBranch ?? branches.first);
      });
    } catch (_) {}
  }

  List<GhRepo> get _filtered {
    if (_query.trim().isEmpty) return _repos;
    final q = _query.toLowerCase();
    return _repos.where((r) => r.fullName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeAccountProvider, (_, __) => _loadRepos());
    final active = ref.watch(activeAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Repositories'),
            if (active != null)
              Text(
                active.login ?? active.label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadRepos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search repos…',
              ),
            ),
          ),
          if (_selectedFullName != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.25),
                    AppColors.accent.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_selectedFullName @ ${_selectedBranch ?? "-"}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_branches.isNotEmpty)
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _branches.contains(_selectedBranch)
                            ? _selectedBranch
                            : _branches.first,
                        dropdownColor: AppColors.cardDark,
                        items: _branches
                            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                            .toList(),
                        onChanged: (b) async {
                          if (b == null || _selectedFullName == null) return;
                          setState(() => _selectedBranch = b);
                          final parts = _selectedFullName!.split('/');
                          await ref.read(sessionTargetProvider.notifier).set(
                                owner: parts[0],
                                repo: parts[1],
                                branch: b,
                              );
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final r = _filtered[i];
                          final selected = r.fullName == _selectedFullName;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: AppColors.cardDark,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  setState(() {
                                    _selectedFullName = r.fullName;
                                    _selectedBranch = r.defaultBranch;
                                  });
                                  await ref.read(sessionTargetProvider.notifier).set(
                                        owner: r.owner,
                                        repo: r.name,
                                        branch: r.defaultBranch,
                                      );
                                  await _loadBranches(r.fullName);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderDark,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        r.private ? Icons.lock_outline : Icons.public,
                                        size: 18,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.fullName,
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                            if (r.description != null &&
                                                r.description!.isNotEmpty)
                                              Text(
                                                r.description!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(Icons.check, color: AppColors.primary),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
