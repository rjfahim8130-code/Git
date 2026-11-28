import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class GhRepo {
  final String fullName;
  final String name;
  final String owner;
  final bool private;
  final String defaultBranch;
  final String? description;

  const GhRepo({
    required this.fullName,
    required this.name,
    required this.owner,
    required this.private,
    required this.defaultBranch,
    this.description,
  });

  factory GhRepo.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] as Map<String, dynamic>?;
    return GhRepo(
      fullName: j['full_name'] as String? ?? '',
      name: j['name'] as String? ?? '',
      owner: owner?['login'] as String? ?? '',
      private: j['private'] as bool? ?? false,
      defaultBranch: j['default_branch'] as String? ?? 'main',
      description: j['description'] as String?,
    );
  }
}

class GhTreeItem {
  final String path;
  final String type;
  final String? sha;
  final int? size;

  const GhTreeItem({
    required this.path,
    required this.type,
    this.sha,
    this.size,
  });

  factory GhTreeItem.fromJson(Map<String, dynamic> j) => GhTreeItem(
        path: j['path'] as String? ?? '',
        type: j['type'] as String? ?? '',
        sha: j['sha'] as String?,
        size: (j['size'] as num?)?.toInt(),
      );
}

class PushFile {
  final String path;
  final Uint8List bytes;
  const PushFile({required this.path, required this.bytes});
}

class GitHubApi {
  GitHubApi(String token)
      : token = token.trim(),
        _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.github.com',
            headers: {
              // Classic + fine-grained PATs
              'Authorization': 'Bearer ${token.trim()}',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              // GitHub requires a User-Agent
              'User-Agent': 'Gito-Android-App',
            },
            connectTimeout: const Duration(seconds: 45),
            receiveTimeout: const Duration(seconds: 90),
            sendTimeout: const Duration(seconds: 90),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

  final String token;
  final Dio _dio;

  Future<Map<String, dynamic>> getUser() async {
    final r = await _dio.get<Map<String, dynamic>>('/user');
    final code = r.statusCode ?? 0;
    if (code == 401 || code == 403) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        type: DioExceptionType.badResponse,
        message: code == 401 ? 'Unauthorized' : 'Forbidden',
      );
    }
    if (code < 200 || code >= 300) {
      throw DioException(
        requestOptions: r.requestOptions,
        response: r,
        type: DioExceptionType.badResponse,
        message: 'HTTP $code',
      );
    }
    return Map<String, dynamic>.from(r.data ?? const {});
  }

  Future<List<GhRepo>> listRepos({int perPage = 100}) async {
    final out = <GhRepo>[];
    var page = 1;
    const maxPages = 10;
    while (page <= maxPages) {
      final r = await _dio.get<List<dynamic>>(
        '/user/repos',
        queryParameters: {
          'per_page': perPage,
          'page': page,
          'sort': 'updated',
          'affiliation': 'owner,collaborator,organization_member',
        },
      );
      final list = r.data ?? const [];
      if (list.isEmpty) break;
      out.addAll(
        list.map((e) => GhRepo.fromJson(Map<String, dynamic>.from(e as Map))),
      );
      if (list.length < perPage) break;
      page++;
    }
    return out;
  }

  Future<List<String>> listBranches(String owner, String repo) async {
    final r = await _dio.get<List<dynamic>>(
      '/repos/$owner/$repo/branches',
      queryParameters: {'per_page': 100},
    );
    final list = r.data ?? const [];
    return list
        .map((e) => (e as Map)['name'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<String> getBranchCommitSha(
      String owner, String repo, String branch) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/ref/heads/$branch',
    );
    final object = r.data?['object'] as Map?;
    final sha = object?['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw Exception('Branch SHA not found for $branch');
    }
    return sha;
  }

  Future<String> getCommitTreeSha(
      String owner, String repo, String commitSha) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/commits/$commitSha',
    );
    final tree = r.data?['tree'] as Map?;
    final sha = tree?['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw Exception('Commit tree SHA not found');
    }
    return sha;
  }

  Future<List<GhTreeItem>> getRecursiveTree(
      String owner, String repo, String treeSha) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/trees/$treeSha',
      queryParameters: {'recursive': '1'},
    );
    final tree = r.data?['tree'] as List? ?? const [];
    return tree
        .map((e) => GhTreeItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> createBlob(
      String owner, String repo, Uint8List bytes) async {
    final content = base64Encode(bytes);
    final r = await _dio.post<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/blobs',
      data: {'content': content, 'encoding': 'base64'},
    );
    final sha = r.data?['sha'] as String?;
    if (sha == null) throw Exception('Blob creation failed');
    return sha;
  }

  Future<String> createTree({
    required String owner,
    required String repo,
    required String baseTreeSha,
    required List<Map<String, dynamic>> tree,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/trees',
      data: {'base_tree': baseTreeSha, 'tree': tree},
    );
    final sha = r.data?['sha'] as String?;
    if (sha == null) throw Exception('Tree creation failed');
    return sha;
  }

  Future<String> createCommit({
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required String parentSha,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/repos/$owner/$repo/git/commits',
      data: {
        'message': message,
        'tree': treeSha,
        'parents': [parentSha],
      },
    );
    final sha = r.data?['sha'] as String?;
    if (sha == null) throw Exception('Commit creation failed');
    return sha;
  }

  Future<void> updateRef({
    required String owner,
    required String repo,
    required String branch,
    required String commitSha,
    bool force = false,
  }) async {
    await _dio.patch<void>(
      '/repos/$owner/$repo/git/refs/heads/$branch',
      data: {'sha': commitSha, 'force': force},
    );
  }

  Future<String> pushFilesSingleCommit({
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<PushFile> files,
    void Function(String step)? onProgress,
  }) async {
    if (files.isEmpty) {
      throw Exception('No files to push');
    }

    onProgress?.call('Reading branch…');
    final parentSha = await getBranchCommitSha(owner, repo, branch);
    final baseTreeSha = await getCommitTreeSha(owner, repo, parentSha);

    final treeEntries = <Map<String, dynamic>>[];
    var i = 0;
    for (final f in files) {
      i++;
      onProgress?.call('Uploading blob $i/${files.length}: ${f.path}');
      final blobSha = await createBlob(owner, repo, f.bytes);
      treeEntries.add({
        'path': f.path,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }

    onProgress?.call('Creating tree…');
    final newTreeSha = await createTree(
      owner: owner,
      repo: repo,
      baseTreeSha: baseTreeSha,
      tree: treeEntries,
    );

    onProgress?.call('Creating commit…');
    final commitSha = await createCommit(
      owner: owner,
      repo: repo,
      message: message,
      treeSha: newTreeSha,
      parentSha: parentSha,
    );

    onProgress?.call('Updating branch…');
    await updateRef(
      owner: owner,
      repo: repo,
      branch: branch,
      commitSha: commitSha,
    );

    onProgress?.call('Done');
    return commitSha;
  }

  Future<String> deletePathsSingleCommit({
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<String> pathsToDelete,
    void Function(String step)? onProgress,
  }) async {
    if (pathsToDelete.isEmpty) {
      throw Exception('No paths to delete');
    }

    onProgress?.call('Reading branch…');
    final parentSha = await getBranchCommitSha(owner, repo, branch);
    final baseTreeSha = await getCommitTreeSha(owner, repo, parentSha);

    final tree = pathsToDelete
        .map((path) => {
              'path': path,
              'mode': '100644',
              'type': 'blob',
              'sha': null,
            })
        .toList();

    onProgress?.call('Creating tree…');
    final newTreeSha = await createTree(
      owner: owner,
      repo: repo,
      baseTreeSha: baseTreeSha,
      tree: tree,
    );

    onProgress?.call('Creating commit…');
    final commitSha = await createCommit(
      owner: owner,
      repo: repo,
      message: message,
      treeSha: newTreeSha,
      parentSha: parentSha,
    );

    onProgress?.call('Updating branch…');
    await updateRef(
      owner: owner,
      repo: repo,
      branch: branch,
      commitSha: commitSha,
    );

    onProgress?.call('Done');
    return commitSha;
  }

  static String friendlyError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = data is Map
          ? (data['message']?.toString() ?? e.message ?? 'Network error')
          : (e.message ?? 'Network error');
      final status = e.response?.statusCode;
      final blob = ('${e.type} ${e.message} $msg').toLowerCase();

      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.unknown ||
          blob.contains('failed host lookup') ||
          blob.contains('socketexception') ||
          blob.contains('network is unreachable') ||
          blob.contains('connection errored') ||
          blob.contains('timed out')) {
        return 'নেটওয়ার্ক/DNS সমস্যা: api.github.com-এ পৌঁছানো যাচ্ছে না। '
            'Wi‑Fi বা মোবাইল ডেটা চালু আছে কিনা দেখুন, VPN/Private DNS বন্ধ করুন, '
            'আর অ্যাপকে ইন্টারনেট পারমিশন আছে কিনা নিশ্চিত করুন।';
      }
      if (status == 401) {
        return 'টোকেন সঠিক নয়। নতুন PAT বানিয়ে আবার দিন (repo scope)।';
      }
      if (status == 403) {
        return 'অনুমতি নেই। Token-এ repo অথবা Contents: Read and write লাগবে।';
      }
      if (status == 404) {
        return 'রিপো/রিসোর্স পাওয়া যায়নি। নাম ও টোকেন অ্যাক্সেস চেক করুন।';
      }
      if (status == 409) {
        return 'ব্রাঞ্চ কনফ্লিক্ট — রিমোট বদলেছে। আবার চেষ্টা করুন।';
      }
      if (status == 422) {
        return 'অবৈধ রিকোয়েস্ট: $msg';
      }
      if (status != null && status >= 500) {
        return 'GitHub সার্ভার এরর ($status)। একটু পর চেষ্টা করুন।';
      }
      // 4xx with body message from GitHub
      if (status != null && status >= 400) {
        return msg;
      }
      return msg;
    }
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') || s.contains('socketexception')) {
      return 'নেটওয়ার্ক/DNS সমস্যা — api.github.com resolve হচ্ছে না। '
          'ইন্টারনেট ও অ্যাপ পারমিশন চেক করুন।';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }
}
