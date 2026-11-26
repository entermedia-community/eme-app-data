import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/values.dart';
import 'models.dart';

/// Query definition for a module search.
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.page = 1,
    this.hitsPerPage = 36,
    this.sortField,
    this.sortAscending = true,
    this.filters = const {},
    this.categoryId,
    this.terms = const [],
  });

  final String text;
  final int page;
  final int hitsPerPage;
  final String? sortField;
  final bool sortAscending;

  /// Facet field id -> selected option ids.
  final Map<String, Set<String>> filters;

  /// Restricts asset searches to one folder.
  final String? categoryId;

  /// Extra raw terms (e.g. used by the column view).
  final List<Json> terms;

  SearchQuery copyWith({
    String? text,
    int? page,
    int? hitsPerPage,
    String? Function()? sortField,
    bool? sortAscending,
    Map<String, Set<String>>? filters,
    String? Function()? categoryId,
    List<Json>? terms,
  }) => SearchQuery(
    text: text ?? this.text,
    page: page ?? this.page,
    hitsPerPage: hitsPerPage ?? this.hitsPerPage,
    sortField: sortField != null ? sortField() : this.sortField,
    sortAscending: sortAscending ?? this.sortAscending,
    filters: filters ?? this.filters,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    terms: terms ?? this.terms,
  );

  int get activeFilterCount => filters.values.fold(0, (a, s) => a + s.length);

  Json toRequest(String searchType) {
    final t = <Json>[
      if (text.trim().isNotEmpty)
        {'field': 'description', 'operation': 'freeform', 'value': text.trim()},
      if (categoryId != null)
        {'field': 'category', 'operation': 'exact', 'value': categoryId},
      for (final e in filters.entries)
        if (e.value.isNotEmpty)
          {'field': e.key, 'operation': 'orsgroup', 'values': e.value.toList()},
      ...terms,
    ];
    if (t.isEmpty) t.add({'field': 'id', 'operation': 'matches', 'value': '*'});
    return {
      'page': '$page',
      'hitsperpage': '$hitsPerPage',
      'showfilters': 'true',
      'query': {'terms': t},
      if (sortField != null)
        '${searchType}sortby': '$sortField${sortAscending ? 'Up' : 'Down'}',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      other.page == page &&
      other.hitsPerPage == hitsPerPage &&
      other.sortField == sortField &&
      other.sortAscending == sortAscending &&
      other.categoryId == categoryId &&
      _filtersKey(other.filters) == _filtersKey(filters) &&
      other.terms.toString() == terms.toString();

  @override
  int get hashCode => Object.hash(
    text,
    page,
    hitsPerPage,
    sortField,
    sortAscending,
    categoryId,
    _filtersKey(filters),
    terms.toString(),
  );

  static String _filtersKey(Map<String, Set<String>> f) =>
      (f.entries
              .where((e) => e.value.isNotEmpty)
              .map((e) => '${e.key}=${(e.value.toList()..sort()).join(',')}')
              .toList()
            ..sort())
          .join('&');
}

class EmeRepository {
  EmeRepository(this.api);
  final ApiClient api;

  /// Modules whose `module/<id>/search` does not exist; use `lists/search/<id>` instead.
  static final _listsOnly = <String>{
    'emeprofile',
    'entitytopic',
    'bankaccount',
    'collectiveproduct',
  };

  static const _all = {
    'page': '1',
    'hitsperpage': '500',
    'query': {
      'terms': [
        {'field': 'id', 'operation': 'matches', 'value': '*'},
      ],
    },
  };

  Future<List<ModuleInfo>> modules() async {
    final res = await api.postJson('lists/search/module', _all);
    final list = [
      for (final r in res['results'] as List? ?? const [])
        ModuleInfo(r as Json),
    ];
    list.sort(
      (a, b) => a.name().toLowerCase().compareTo(b.name().toLowerCase()),
    );
    return list;
  }

  Future<List<AppSection>> appSections() async {
    final res = await api.postJson('lists/search/appsection', _all);
    final list = [
      for (final r in res['results'] as List? ?? const [])
        if (r is Json) AppSection.fromJson(r),
    ]..removeWhere((s) => s.moduleId.isEmpty);
    list.sort((a, b) => a.ordering.compareTo(b.ordering));
    return list;
  }

  Future<SearchResult> search(String module, SearchQuery q) async {
    final body = q.toRequest(module);
    Json res;
    if (_listsOnly.contains(module)) {
      res = await api.postJson('lists/search/$module', body);
    } else {
      try {
        res = await api.postJson('module/$module/search', body);
      } on ApiException catch (e) {
        if (e.statusCode != 404 && e.statusCode != 500) rethrow;
        _listsOnly.add(module);
        res = await api.postJson('lists/search/$module', body);
      }
    }
    final r = res['response'] as Map? ?? const {};
    final hits = [
      for (final h in res['results'] as List? ?? const [])
        if (h is Json) h,
    ];
    if (module != 'asset') await _attachThumbnails(hits);
    return SearchResult(
      hits: hits,
      total: int.tryParse('${r['totalhits']}') ?? hits.length,
      page: int.tryParse('${r['page']}') ?? q.page,
      pages: int.tryParse('${r['pages']}') ?? 1,
      facets: [
        for (final f in res['filteroptions'] as List? ?? const [])
          if (f is Json) Facet.fromJson(f),
      ]..removeWhere((f) => f.options.isEmpty),
    );
  }

  /// Entities point at assets by id (primarymedia / primaryimage); resolve their
  /// sourcepaths in one search and store them as `_thumbpath`.
  Future<void> _attachThumbnails(List<Json> hits) async {
    String? refOf(Json h) =>
        valueIds(h['primarymedia']).firstOrNull ??
        valueIds(h['primaryimage']).firstOrNull;
    final ids = {for (final h in hits) ?refOf(h)};
    if (ids.isEmpty) return;
    try {
      final res = await api.postJson('module/asset/search', {
        'page': '1',
        'hitsperpage': '${ids.length}',
        'query': {
          'terms': [
            {'field': 'id', 'operation': 'orsgroup', 'values': ids.toList()},
          ],
        },
      });
      final paths = {
        for (final a in res['results'] as List? ?? const [])
          if (a is Json && a['sourcepath'] != null)
            a.id: a['sourcepath'] as String,
      };
      for (final h in hits) {
        final p = paths[refOf(h)];
        if (p != null) h['_thumbpath'] = p;
      }
    } catch (_) {
      // Thumbnails are decoration; never fail the search over them.
    }
  }

  /// Server-relative thumbnail path of an asset, or null when it has none.
  Future<String?> assetPreviewPath(String assetId) async {
    final res = await api.getJson(
      'settings/datamanager/asset/preview',
      query: {'assetid': assetId},
    );
    final p = res['path'];
    return p is String && p.isNotEmpty ? p : null;
  }

  Future<List<FieldDef>> fields(String searchType) async {
    final res = await api.getJson(
      'settings/datamanager/fields/listfields',
      query: {'searchtype': searchType},
    );
    return [
      for (final r in res['results'] as List? ?? const [])
        if (r is Json) FieldDef(r),
    ];
  }

  Future<List<Json>> listOptions(String listId, {String text = ''}) async {
    final res = await api.postJson('lists/search/$listId', {
      'page': '1',
      'hitsperpage': '200',
      'query': {
        'terms': [
          text.isEmpty
              ? {'field': 'id', 'operation': 'matches', 'value': '*'}
              : {
                  'field': 'name',
                  'operation': 'contains',
                  'value': text.toLowerCase(),
                },
        ],
      },
    });
    return [
      for (final r in res['results'] as List? ?? const [])
        if (r is Json) r,
    ];
  }

  Future<CategoryNode> categoryTree() async {
    final res = await api.postJson('module/category/tree', {
      'categoryid': 'index',
    });
    return CategoryNode(
      id: '${res['id'] ?? 'index'}',
      name: localized(res['name']).isNotEmpty ? localized(res['name']) : 'All',
      path: '',
      children: CategoryNode.fromJson(res).children,
    );
  }

  Future<Json> load(String searchType, String id) async {
    final path = searchType == 'asset'
        ? 'module/asset/data/$id'
        : 'lists/data/$searchType/$id';
    final res = await api.getJson(path);
    final data = res['data'];
    if (data is! Json) throw ApiException('Record not found');
    if (searchType != 'asset') await _attachThumbnails([data]);
    return data;
  }

  /// Updates (or creates, when [id] is null) a record. Returns the record id.
  Future<String> save(String searchType, String? id, Json values) async {
    if (id == null) {
      final res = await api
          .postJson('module/$searchType/create', values)
          .catchError(
            (_) =>
                // Fallback: PUT to an unknown id creates a row with a generated id.
                api.putJson('lists/data/$searchType/new', values),
          );
      final r = res['response'] as Map? ?? const {};
      final newId = r['id'] ?? (res['data'] as Map?)?['id'];
      if (newId == null)
        throw ApiException('The server did not return the new record id');
      return '$newId';
    }
    final path = searchType == 'asset'
        ? 'module/asset/data/$id'
        : 'lists/data/$searchType/$id';
    await api.putJson(path, values);
    return id;
  }

  Future<void> deleteRecord(String searchType, String id) async {
    if (searchType == 'asset') {
      await api.postJson('module/asset/deleteassets', {'assetid': id});
    } else {
      await api.delete('lists/data/$searchType/$id');
    }
  }

  Future<List<Json>> versions(String assetId) async {
    final res = await api.postJson('module/asset/versions/getrevisions', {
      'assetid': assetId,
    });
    return [
      for (final r in res['results'] as List? ?? const [])
        if (r is Json) r,
    ];
  }

  /// Multipart upload into [folder] (a category path such as "Users/Ann/2026").
  Future<Json> uploadAsset({
    required String fileName,
    required Stream<List<int>> Function() stream,
    required int length,
    required String folder,
    Json extra = const {},
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final cleanFolder = folder.replaceAll(RegExp(r'^/+|/+$'), '');
    final sourcepath = cleanFolder.isEmpty
        ? fileName
        : '$cleanFolder/$fileName';
    final meta = {
      'sourcepath': sourcepath,
      if (cleanFolder.isNotEmpty) 'categorypath': cleanFolder,
      ...extra,
    };
    final res = await api.postMultipart(
      'module/asset/create',
      () => FormData.fromMap({
        'sourcepath': sourcepath,
        'jsonrequest': jsonEncode(meta),
        'file': MultipartFile.fromStream(stream, length, filename: fileName),
      }),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return (res['data'] as Json?) ?? res;
  }
}

final repositoryProvider = Provider<EmeRepository>(
  (ref) => EmeRepository(ref.watch(apiClientProvider)),
);
