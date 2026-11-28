import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'github/github_api.dart';
import 'storage/account_store.dart';

final accountStoreProvider = Provider<AccountStore>((ref) {
  return AccountStore();
});

class AccountsNotifier extends StateNotifier<AsyncValue<List<GhAccount>>> {
  AccountsNotifier(this._store) : super(const AsyncValue.loading());

  final AccountStore _store;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _store.loadAccounts());
  }

  Future<void> upsert(GhAccount account) async {
    final current = state.valueOrNull ?? const <GhAccount>[];
    final list = List<GhAccount>.from(current);
    final idx = list.indexWhere((x) => x.id == account.id);
    if (idx >= 0) {
      list[idx] = account;
    } else {
      list.add(account);
    }
    await _store.saveAccounts(list);
    state = AsyncValue.data(list);
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? const <GhAccount>[];
    final list = List<GhAccount>.from(current)
      ..removeWhere((x) => x.id == id);
    await _store.saveAccounts(list);

    final activeId = await _store.getActiveId();
    if (activeId == id) {
      await _store.setActiveId(list.isEmpty ? null : list.first.id);
    }
    state = AsyncValue.data(list);
  }
}

final accountsProvider =
    StateNotifierProvider<AccountsNotifier, AsyncValue<List<GhAccount>>>(
  (ref) => AccountsNotifier(ref.read(accountStoreProvider))..load(),
);

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

final activeAccountIdProvider =
    StateNotifierProvider<ActiveAccountNotifier, String?>(
  (ref) => ActiveAccountNotifier(ref.read(accountStoreProvider))..load(),
);

final activeAccountProvider = Provider<GhAccount?>((ref) {
  final activeId = ref.watch(activeAccountIdProvider);
  final accounts =
      ref.watch(accountsProvider).valueOrNull ?? const <GhAccount>[];
  if (accounts.isEmpty) return null;
  if (activeId == null) return accounts.first;
  for (final a in accounts) {
    if (a.id == activeId) return a;
  }
  return accounts.first;
});

final apiProvider = Provider<GitHubApi?>((ref) {
  final account = ref.watch(activeAccountProvider);
  if (account == null || account.token.isEmpty) return null;
  return GitHubApi(account.token);
});

class SessionTarget {
  final String owner;
  final String repo;
  final String branch;

  const SessionTarget({
    required this.owner,
    required this.repo,
    required this.branch,
  });

  String get fullName => '$owner/$repo';
}

class SessionTargetNotifier extends StateNotifier<SessionTarget?> {
  SessionTargetNotifier(this._store) : super(null);

  final AccountStore _store;

  Future<void> restore() async {
    final fullName = await _store.getLastRepo();
    final branch = await _store.getLastBranch() ?? 'main';
    if (fullName == null || !fullName.contains('/')) return;
    final parts = fullName.split('/');
    if (parts.length != 2) return;
    state = SessionTarget(
      owner: parts[0],
      repo: parts[1],
      branch: branch,
    );
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
    final current = state;
    if (current == null) return;
    state = SessionTarget(
      owner: current.owner,
      repo: current.repo,
      branch: branch,
    );
    await _store.setLastBranch(branch);
  }

  Future<void> clear() async {
    state = null;
  }
}

final sessionTargetProvider =
    StateNotifierProvider<SessionTargetNotifier, SessionTarget?>(
  (ref) => SessionTargetNotifier(ref.read(accountStoreProvider))..restore(),
);
