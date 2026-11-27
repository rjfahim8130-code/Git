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

  GhRepo({
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
      fullName: j['full_name'] as String,
      name: j['name'] as String,
      owner: owner?['login'] as String? ?? '',
      private: j['private'] as bool? ?? false,
      defaultBranch: j['default_branch'] as String? ?? 'main',
      description: j['description'] as String?,
    );
  }
}

class GhTreeItem {
  final String path;
  final String type; // blob | tree
  final String? sha;
  final int? size;

  GhTreeItem({
    required this.path,
    required this.type,
    this.sha,
    this.size,
  });

  factory GhTreeItem.fromJson(Map<String, dynamic> j) => GhTreeItem(
        path: j['path'] as String,
        type: j['type'] as String,
        sha: j['sha'] as String?,
        size: j['size'] as int?,
      );
}

class PushFile {
  final String path;
  final Uint8List bytes;
  PushFile({required this.path, required this.bytes});
}

class GitHubApi {
  final String token;
  late final Dio _dio;

  GitHubApi(this.token) {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.github.com',
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
  }

  Future> getUser() async {
    final r = await _dio.get('/user');
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<List<GhRepo>> listRepos({int perPage = 100}) async {
    final out = <GhRepo>[];
    var page = 1;
    while (true) {
      final r = await _dio.get(
        '/user/repos',
        queryParameters: {
          'per_page': perPage,
          'page': page,
          'sort': 'updated',
          'affiliation': 'owner,collaborator,organization_member',
        },
      );
      final list = r.data as List;
      if (list.isEmpty) break;
      out.addAll(
        list.map((e) => GhRepo.fromJson(Map<String, dynamic>.from(e as Map))),
      );
      if (list.length < perPage) break;
      page++;
      if (page > 10) break;
    }
    return out;
  }

  Future<List<String>> listBranches(String owner, String repo) async {
    final r = await _dio.get(
      '/repos/$owner/$repo/branches',
      queryParameters: {'per_page': 100},
    );
    final list = r.data as List;
    return list
        .map((e) => (e as Map)['name'] as String)
        .toList();
  }

  Future<String> getBranchCommitSha(String owner, String repo, String branch) async {
    final r = await _dio.get('/repos/$owner/$repo/git/ref/heads/$branch');
    final data = r.data as Map;
    final object = data['object'] as Map;
    return object['sha'] as String;
  }

  Future<String> getCommitTreeSha(String owner, String repo, String commitSha) async {
    final r = await _dio.get('/repos/$owner/$repo/git/commits/$commitSha');
    final tree = (r.data as Map)['tree'] as Map;
    return tree['sha'] as String;
  }

  Future<List<GhTreeItem>> getRecursiveTree(
    String owner,
    String repo,
    String treeSha,
  ) async {
    final r = await _dio.get(
      '/repos/$owner/$repo/git/trees/$treeSha',
      queryParameters: {'recursive': '1'},
    );
    final tree = (r.data as Map)['tree'] as List? ?? [];
    return tree
        .map((e) => GhTreeItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> createBlob(
    String owner,
    String repo,
    Uint8List bytes,
  ) async {
    final content = base64Encode(bytes);
    final r = await _dio.post(
      '/repos/$owner/$repo/git/blobs',
      data: {
        'content': content,
        'encoding': 'base64',
      },
    );
    return (r.data as Map)['sha'] as String;
  }

  Future<String> createTree({
    required String owner,
    required String repo,
    required String baseTreeSha,
    required List> tree,
  }) async {
    final r = await _dio.post(
      '/repos/$owner/$repo/git/trees',
      data: {
        'base_tree': baseTreeSha,
        'tree': tree,
      },
    );
    return (r.data as Map)['sha'] as String;
  }

  Future<String> createCommit({
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required String parentSha,
  }) async {
    final r = await _dio.post(
      '/repos/$owner/$repo/git/commits',
      data: {
        'message': message,
        'tree': treeSha,
        'parents': [parentSha],
      },
    );
    return (r.data as Map)['sha'] as String;
  }

  Future<void> updateRef({
    required String owner,
    required String repo,
    required String branch,
    required String commitSha,
    bool force = false,
  }) async {
    await _dio.patch(
      '/repos/$owner/$repo/git/refs/heads/$branch',
      data: {
        'sha': commitSha,
        'force': force,
      },
    );
  }

  /// Push multiple files in ONE commit (create or overwrite paths).
  Future<String> pushFilesSingleCommit({
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<PushFile> files,
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('Reading branch…');
    final parentSha = await getBranchCommitSha(owner, repo, branch);
    final baseTreeSha = await getCommitTreeSha(owner, repo, parentSha);

    final treeEntries = >[];
    var i = 0;
    for (final f in files) {
      i++;
      onProgress?.call('Uploading blob $i/${files.length}:${f.path}');
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
      force: false,
    );

    onProgress?.call('Done');
    return commitSha;
  }

  /// Delete selected paths in ONE commit (omit from tree by sha null mode).
  Future<String> deletePathsSingleCommit({
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<String> pathsToDelete,
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('Reading branch…');
    final parentSha = await getBranchCommitSha(owner, repo, branch);
    final baseTreeSha = await getCommitTreeSha(owner, repo, parentSha);

    // GitHub: path + mode + type + sha:null removes file from tree when using base_tree
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
    return commitSha;
  }

  String friendlyError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final msg = data is Map ? (data['message']?.toString() ?? e.message) : e.message;
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return 'Permission denied. Check token scopes (repo / Contents write).';
      }
      if (status == 404) {
        return 'Not found. Check repo name and token access.';
      }
      if (status == 409) {
        return 'Conflict on branch. Pull/remote changed — try again.';
      }
      return msg ?? 'Network error';
    }
    return e.toString();
  }
}
