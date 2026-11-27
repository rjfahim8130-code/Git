import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'github/github_api.dart';
import 'storage/account_store.dart';

final accountStoreProvider = Provider((_) => AccountStore());

final accountsProvider =
    StateNotifierProvider<AccountsNotifier, AsyncValue<List<GhAccount>>>((ref) {
  return AccountsNotifier(ref.read(accountStoreProvider))..load();
});

class AccountsNotifier extends StateNotifier<AsyncValue<List<GhAccount>>> {
  AccountsNotifier(this._store) : super(const AsyncValue.loading());
  final AccountStore _store;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final list = await _store.loadAccounts();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upsert(GhAccount account) async {
    final list = [...(state.valueOrNull ?? [])];
    final i = list.indexWhere((e) => e.id == account.id);
    if (i >= 0) {
      list[i] = account;
    } else {
      list.add(account);
    }
    await _store.saveAccounts(list);
    state = AsyncValue.data(list);
  }

  Future<void> remove(String id) async {
    final list = [...(state.valueOrNull ?? [])]..removeWhere((e) => e.id == id);
    await _store.saveAccounts(list);
    final active = await _store.getActiveId();
    if (active == id) await _store.setActiveId(list.isEmpty ? null : list.first.id);
    state = AsyncValue.data(list);
  }
}

final activeAccountIdProvider =
    StateNotifierProvider<ActiveAccountNotifier, String?>((ref) {
  return ActiveAccountNotifier(ref.read(accountStoreProvider))..load();
});

class ActiveAccountNotifier extends StateNotifier<String?> {
  ActiveAccountNotifier(this._store) : super(null);
  final AccountStore _store;

  Future<void> load() async {
    state = await _store.getActiveId();
  }

  Future<void> set(String? id) async {
    await _store.setActiveId(id);
    state = id;
  }
}

final activeAccountProvider = Provider<GhAccount?>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
  if (id == null) return accounts.isEmpty ? null : accounts.first;
  return accounts.cast<GhAccount?>().firstWhere(
        (e) => e?.id == id,
        orElse: () => accounts.isEmpty ? null : accounts.first,
      );
});

final apiProvider = Provider<GitHubApi?>((ref) {
  final acc = ref.watch(activeAccountProvider);
  if (acc == null || acc.token.isEmpty) return null;
  return GitHubApi(acc.token);
});

class SessionTarget {
  final String owner;
  final String repo;
  final String branch;
  String get fullName => '$owner/$repo';
  const SessionTarget({
    required this.owner,
    required this.repo,
    required this.branch,
  });
}

final sessionTargetProvider =
    StateNotifierProvider<SessionTargetNotifier, SessionTarget?>((ref) {
  return SessionTargetNotifier(ref.read(accountStoreProvider))..restore();
});

class SessionTargetNotifier extends StateNotifier<SessionTarget?> {
  SessionTargetNotifier(this._store) : super(null);
  final AccountStore _store;

  Future<void> restore() async {
    final full = await _store.getLastRepo();
    final branch = await _store.getLastBranch() ?? 'main';
    if (full == null || !full.contains('/')) return;
    final parts = full.split('/');
    state = SessionTarget(owner: parts[0], repo: parts[1], branch: branch);
  }

  Future<void> set({
    required String owner,
    required String repo,
    required String branch,
  }) async {
    state = SessionTarget(owner: owner, repo: repo, branch: branch);
    await _store.setLastRepo('$owner/$repo');
    await _store.setLastBranch(branch);
  }

  Future<void> setBranch(String branch) async {
    final s = state;
    if (s == null) return;
    state = SessionTarget(owner: s.owner, repo: s.repo, branch: branch);
    await _store.setLastBranch(branch);
  }
}
