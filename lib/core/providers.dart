
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'github/github_api.dart';
import 'storage/account_store.dart';

final accountStoreProvider = Provider<AccountStore>((ref) {
  return AccountStore();
});

final accountsProvider =
    StateNotifierProvider<AccountsNotifier, AsyncValue<List<GhAccount>>>(
  (ref) {
    return AccountsNotifier(ref.read(accountStoreProvider))..load();
  },
);

class AccountsNotifier extends StateNotifier<AsyncValue<List<GhAccount>>> {
  AccountsNotifier(this._store) : super(const AsyncValue.loading());

  final AccountStore _store;

  Future<void> load() async {
    state = const AsyncValue.loading();

    try {
      final List<GhAccount> list = await _store.loadAccounts();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upsert(GhAccount account) async {
    final List<GhAccount> current =
        state.valueOrNull ?? <GhAccount>[];

    final List<GhAccount> list =
        List<GhAccount>.from(current);

    final int index = list.indexWhere(
      (item) => item.id == account.id,
    );

    if (index >= 0) {
      list[index] = account;
    } else {
      list.add(account);
    }

    await _store.saveAccounts(list);

    state = AsyncValue.data(list);
  }

  Future<void> remove(String id) async {
    final List<GhAccount> current =
        state.valueOrNull ?? <GhAccount>[];

    final List<GhAccount> list =
        List<GhAccount>.from(current);

    list.removeWhere((item) => item.id == id);

    await _store.saveAccounts(list);

    final String? activeId = await _store.getActiveId();

    if (activeId == id) {
      await _store.setActiveId(
        list.isEmpty ? null : list.first.id,
      );
    }

    state = AsyncValue.data(list);
  }
}

final activeAccountIdProvider =
    StateNotifierProvider<ActiveAccountNotifier, String?>(
  (ref) {
    return ActiveAccountNotifier(
      ref.read(accountStoreProvider),
    )..load();
  },
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

final activeAccountProvider = Provider<GhAccount?>((ref) {
  final String? activeId = ref.watch(activeAccountIdProvider);

  final List<GhAccount> accounts =
      ref.watch(accountsProvider).valueOrNull ?? <GhAccount>[];

  if (accounts.isEmpty) {
    return null;
  }

  if (activeId == null) {
    return accounts.first;
  }

  for (final GhAccount account in accounts) {
    if (account.id == activeId) {
      return account;
    }
  }

  return accounts.first;
});

final apiProvider = Provider<GitHubApi?>((ref) {
  final GhAccount? account = ref.watch(activeAccountProvider);

  if (account == null || account.token.isEmpty) {
    return null;
  }

  return GitHubApi(account.token);
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
    StateNotifierProvider<SessionTargetNotifier, SessionTarget?>(
  (ref) {
    return SessionTargetNotifier(
      ref.read(accountStoreProvider),
    )..restore();
  },
);

class SessionTargetNotifier extends StateNotifier<SessionTarget?> {
  SessionTargetNotifier(this._store) : super(null);

  final AccountStore _store;

  Future<void> restore() async {
    final String? fullName = await _store.getLastRepo();
    final String branch =
        await _store.getLastBranch() ?? 'main';

    if (fullName == null || !fullName.contains('/')) {
      return;
    }

    final List<String> parts = fullName.split('/');

    if (parts.length != 2) {
      return;
    }

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
    state = SessionTarget(
      owner: owner,
      repo: repo,
      branch: branch,
    );

    await _store.setLastRepo('$owner/$repo');
    await _store.setLastBranch(branch);
  }

  Future<void> setBranch(String branch) async {
    final SessionTarget? current = state;

    if (current == null) {
      return;
    }

    state = SessionTarget(
      owner: current.owner,
      repo: current.repo,
      branch: branch,
    );

    await _store.setLastBranch(branch);
  }
}
