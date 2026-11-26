import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/settings.dart';
import '../features/auth/auth_controller.dart';
import 'models.dart';
import 'repository.dart';

/// Invalidated by sign-in changes so per-user data reloads.
final _sessionKeyProvider = Provider<String>(
  (ref) => ref.watch(authProvider.select((s) => s.userId)),
);

final modulesProvider = FutureProvider<List<ModuleInfo>>((ref) {
  ref.watch(_sessionKeyProvider);
  return ref.watch(repositoryProvider).modules();
});

final moduleByIdProvider = Provider.family<ModuleInfo?, String>((ref, id) {
  final list = ref.watch(modulesProvider).value ?? const [];
  for (final m in list) {
    if (m.id == id) return m;
  }
  return null;
});

/// "Data Entity Manager" sidebar: entity modules, alphabetical.
final entityModulesProvider = Provider<AsyncValue<List<ModuleInfo>>>((ref) {
  return ref
      .watch(modulesProvider)
      .whenData((l) => l.where((m) => m.isEntity).toList());
});

final appSectionsProvider = FutureProvider<List<AppSection>>((ref) {
  ref.watch(_sessionKeyProvider);
  return ref.watch(repositoryProvider).appSections();
});

final fieldsProvider = FutureProvider.family<List<FieldDef>, String>((
  ref,
  searchType,
) async {
  ref.watch(_sessionKeyProvider);
  try {
    return await ref.watch(repositoryProvider).fields(searchType);
  } on ApiException {
    // Needs the api-manage-list permission; callers fall back to keys found in results.
    return const [];
  }
});

final listOptionsProvider = FutureProvider.family<List<Json>, String>((
  ref,
  listId,
) {
  return ref.watch(repositoryProvider).listOptions(listId);
});

final categoryTreeProvider = FutureProvider<CategoryNode>((ref) {
  ref.watch(_sessionKeyProvider);
  return ref.watch(repositoryProvider).categoryTree();
});

final recordProvider = FutureProvider.family<Json, ({String type, String id})>((
  ref,
  key,
) {
  return ref.watch(repositoryProvider).load(key.type, key.id);
});

final versionsProvider = FutureProvider.family<List<Json>, String>((
  ref,
  assetId,
) {
  return ref.watch(repositoryProvider).versions(assetId);
});

enum ViewMode { table, grid, column }

class ModuleViewState {
  const ModuleViewState({
    required this.query,
    required this.viewMode,
    this.selected = const {},
    this.hiddenColumns,
    this.showSummary = true,
  });

  final SearchQuery query;
  final ViewMode viewMode;
  final Set<String> selected;

  /// Null means "use the default column set".
  final Set<String>? hiddenColumns;
  final bool showSummary;

  ModuleViewState copyWith({
    SearchQuery? query,
    ViewMode? viewMode,
    Set<String>? selected,
    Set<String>? hiddenColumns,
    bool? showSummary,
  }) => ModuleViewState(
    query: query ?? this.query,
    viewMode: viewMode ?? this.viewMode,
    selected: selected ?? this.selected,
    hiddenColumns: hiddenColumns ?? this.hiddenColumns,
    showSummary: showSummary ?? this.showSummary,
  );
}

class ModuleViewController extends Notifier<ModuleViewState> {
  ModuleViewController(this.moduleId);
  final String moduleId;

  @override
  ModuleViewState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final saved = prefs.getString('view.$moduleId');
    final module = ref.read(moduleByIdProvider(moduleId));
    final mode =
        ViewMode.values.where((v) => v.name == saved).firstOrNull ??
        (const {
              'brickvertical',
              'grid',
              'gallery',
            }.contains(module?.resultsView)
            ? ViewMode.grid
            : ViewMode.table);
    final hidden = prefs.getStringList('columns.$moduleId');
    return ModuleViewState(
      query: SearchQuery(hitsPerPage: prefs.getInt('pagesize') ?? 36),
      viewMode: mode,
      hiddenColumns: hidden?.toSet(),
      showSummary: prefs.getBool('summary') ?? true,
    );
  }

  void setViewMode(ViewMode mode) {
    ref.read(sharedPrefsProvider).setString('view.$moduleId', mode.name);
    state = state.copyWith(viewMode: mode);
  }

  void setText(String text) => state = state.copyWith(
    query: state.query.copyWith(text: text, page: 1),
    selected: {},
  );

  void setPage(int page) => state = state.copyWith(
    query: state.query.copyWith(page: page),
    selected: {},
  );

  void setPageSize(int size) {
    ref.read(sharedPrefsProvider).setInt('pagesize', size);
    state = state.copyWith(
      query: state.query.copyWith(hitsPerPage: size, page: 1),
    );
  }

  void sortBy(String field) {
    final q = state.query;
    final asc = q.sortField == field ? !q.sortAscending : true;
    state = state.copyWith(
      query: q.copyWith(sortField: () => field, sortAscending: asc, page: 1),
    );
  }

  void clearSort() => state = state.copyWith(
    query: state.query.copyWith(sortField: () => null, page: 1),
  );

  void setCategory(String? id) => state = state.copyWith(
    query: state.query.copyWith(
      categoryId: () => id == 'index' ? null : id,
      page: 1,
    ),
    selected: {},
  );

  void toggleFilter(String field, String value) {
    final f = {
      for (final e in state.query.filters.entries) e.key: {...e.value},
    };
    final set = f.putIfAbsent(field, () => {});
    set.contains(value) ? set.remove(value) : set.add(value);
    state = state.copyWith(
      query: state.query.copyWith(filters: f, page: 1),
      selected: {},
    );
  }

  void clearFilters() =>
      state = state.copyWith(query: state.query.copyWith(filters: {}, page: 1));

  void toggleSelected(String id) {
    final s = {...state.selected};
    s.contains(id) ? s.remove(id) : s.add(id);
    state = state.copyWith(selected: s);
  }

  void setSelected(Set<String> ids) => state = state.copyWith(selected: ids);

  void setHiddenColumns(Set<String> hidden) {
    ref
        .read(sharedPrefsProvider)
        .setStringList('columns.$moduleId', hidden.toList());
    state = state.copyWith(hiddenColumns: hidden);
  }

  void toggleSummary() {
    final next = !state.showSummary;
    ref.read(sharedPrefsProvider).setBool('summary', next);
    state = state.copyWith(showSummary: next);
  }
}

final moduleViewProvider =
    NotifierProvider.family<ModuleViewController, ModuleViewState, String>(
      ModuleViewController.new,
    );

final searchResultsProvider = FutureProvider.family<SearchResult, String>((
  ref,
  moduleId,
) {
  ref.watch(_sessionKeyProvider);
  final query = ref.watch(moduleViewProvider(moduleId).select((s) => s.query));
  return ref.watch(repositoryProvider).search(moduleId, query);
});

/// Ad-hoc searches (column view, related assets) keyed by module + query.
final adhocSearchProvider = FutureProvider.autoDispose
    .family<SearchResult, ({String module, SearchQuery query})>((ref, key) {
      return ref.watch(repositoryProvider).search(key.module, key.query);
    });

/// Ids of the current result list, used for prev/next in the asset viewer.
class ViewerNavigation extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void set(List<String> ids) => state = ids;
}

final viewerNavigationProvider =
    NotifierProvider<ViewerNavigation, List<String>>(ViewerNavigation.new);

final assetPreviewPathProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, id) => ref.watch(repositoryProvider).assetPreviewPath(id),
    );
