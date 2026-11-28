import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GhAccount {
  final String id;
  final String label;
  final String token;
  final String? login;
  final String? avatarUrl;

  const GhAccount({
    required this.id,
    required this.label,
    required this.token,
    this.login,
    this.avatarUrl,
  });

  GhAccount copyWith({
    String? label,
    String? token,
    String? login,
    String? avatarUrl,
  }) {
    return GhAccount(
      id: id,
      label: label ?? this.label,
      token: token ?? this.token,
      login: login ?? this.login,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'token': token,
        'login': login,
        'avatarUrl': avatarUrl,
      };

  factory GhAccount.fromJson(Map<String, dynamic> j) => GhAccount(
        id: j['id'] as String,
        label: j['label'] as String? ?? 'Account',
        token: j['token'] as String,
        login: j['login'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
      );
}

class AccountStore {
  AccountStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _secure;

  static const _keyAccounts = 'gh_accounts_v1';
  static const _keyActive = 'gh_active_id';
  static const _keyLastRepo = 'gh_last_repo';
  static const _keyLastBranch = 'gh_last_branch';

  Future<List<GhAccount>> loadAccounts() async {
    try {
      final raw = await _secure.read(key: _keyAccounts);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => GhAccount.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAccounts(List<GhAccount> accounts) async {
    final encoded = jsonEncode(accounts.map((e) => e.toJson()).toList());
    await _secure.write(key: _keyAccounts, value: encoded);
  }

  Future<String?> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActive);
  }

  Future<void> setActiveId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyActive);
    } else {
      await prefs.setString(_keyActive, id);
    }
  }

  Future<void> setLastRepo(String fullName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRepo, fullName);
  }

  Future<String?> getLastRepo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastRepo);
  }

  Future<void> setLastBranch(String branch) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastBranch, branch);
  }

  Future<String?> getLastBranch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastBranch);
  }

  Future<void> clearAll() async {
    await _secure.delete(key: _keyAccounts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActive);
    await prefs.remove(_keyLastRepo);
    await prefs.remove(_keyLastBranch);
  }
}
