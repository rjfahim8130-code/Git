import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/github/github_api.dart';
import '../../core/providers.dart';
import '../../core/storage/account_store.dart';
import '../../core/theme/app_theme.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool _saving = false;

  Future<void> _showAccountDialog({GhAccount? account}) async {
    if (_saving) return;
    final isEditing = account != null;

    final labelController = TextEditingController(text: account?.label ?? '');
    final tokenController = TextEditingController(text: account?.token ?? '');
    bool obscureToken = true;
    bool validating = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> saveAccount() async {
              if (validating) return;
              final label = labelController.text.trim();
              final token = tokenController.text.trim();

              if (token.isEmpty) {
                _snack(context, 'GitHub Token required.');
                return;
              }

              setDialogState(() => validating = true);

              try {
                final api = GitHubApi(token);
                final user = await api.getUser();
                final login = user['login']?.toString();
                final avatar = user['avatar_url']?.toString();

                if (login == null || login.isEmpty) {
                  throw Exception('GitHub account info unavailable.');
                }

                final newAccount = GhAccount(
                  id: account?.id ?? const Uuid().v4(),
                  label: label.isEmpty ? login : label,
                  token: token,
                  login: login,
                  avatarUrl: avatar,
                );

                await ref.read(accountsProvider.notifier).upsert(newAccount);

                if (!isEditing) {
                  await ref
                      .read(activeAccountIdProvider.notifier)
                      .set(newAccount.id);
                }

                if (!mounted) return;
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();

                _snack(
                  this.context,
                  isEditing ? 'Account updated.' : 'Account added.',
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() => validating = false);
                _snack(dialogContext, GitHubApi.friendlyError(e));
              }
            }

            return AlertDialog(
              title: Text(isEditing ? 'Edit Account' : 'Add GitHub Account'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      enabled: !validating,
                      decoration: const InputDecoration(
                        labelText: 'Account Name',
                        hintText: 'Personal / Work',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: tokenController,
                      enabled: !validating,
                      obscureText: obscureToken,
                      maxLines: 1,
                      decoration: InputDecoration(
                        labelText: 'GitHub Personal Access Token',
                        hintText: 'ghp_...',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(
                              () => obscureToken = !obscureToken),
                          icon: Icon(
                            obscureToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Token will be validated against /user API. '
                      'Stored securely on device.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: validating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: validating ? null : saveAccount,
                  icon: validating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    validating
                        ? 'Verifying…'
                        : isEditing
                            ? 'Update'
                            : 'Add Account',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    labelController.dispose();
    tokenController.dispose();
  }

  Future<void> _deleteAccount(GhAccount account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text(
          'Remove ${account.login ?? account.label} from Gito?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(accountsProvider.notifier).remove(account.id);
      if (!mounted) return;
      _snack(context, 'Account removed.');
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Delete failed: $e');
    }
  }

  Future<void> _selectAccount(GhAccount account) async {
    await ref.read(activeAccountIdProvider.notifier).set(account.id);
    if (!mounted) return;
    _snack(context, '${account.login ?? account.label} is now active.');
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _accountAvatar(GhAccount account) {
    final avatar = account.avatarUrl;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 25,
        backgroundColor: AppColors.surfaceDark,
        backgroundImage: NetworkImage(avatar),
        onBackgroundImageError: (_, __) {},
      );
    }
    return const CircleAvatar(
      radius: 25,
      backgroundColor: AppColors.surfaceDark,
      child: Icon(Icons.person, color: AppColors.textSecondary),
    );
  }

  Widget _accountCard(GhAccount account, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.borderDark,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                _accountAvatar(account),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.login ?? account.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 13,
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isActive ? 'Active Account' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showAccountDialog(account: account);
                    } else if (value == 'delete') {
                      _deleteAccount(account);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          SizedBox(width: 10),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isActive
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Currently Selected'),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _selectAccount(account),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Set as Active Account'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsState = ref.watch(accountsProvider);
    final activeId = ref.watch(activeAccountIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GitHub Accounts'),
            Text(
              'Manage your GitHub connections',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(accountsProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _showAccountDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
      body: accountsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 42, color: AppColors.danger),
                const SizedBox(height: 12),
                const Text('Unable to load accounts',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(accountsProvider.notifier).load(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.account_circle_outlined,
                        size: 52,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No GitHub Accounts',
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add a GitHub account to access your repositories '
                      'and upload project files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _showAccountDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add GitHub Account'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${accounts.length} GitHub account'
                        '${accounts.length == 1 ? '' : 's'} connected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'YOUR ACCOUNTS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...accounts.map(
                (account) => _accountCard(
                  account,
                  account.id == activeId ||
                      (activeId == null && accounts.first.id == account.id),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Only one account can be active at a time. '
                'Repositories and upload use the active account.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
