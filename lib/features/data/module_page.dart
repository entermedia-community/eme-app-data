import 'dart:async';

import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../record/record_dialog.dart';
import '../upload/upload_panel.dart';
import '../upload/upload_queue.dart';
import 'columns.dart';
import 'folders_panel.dart';
import 'summary_panel.dart';
import 'views/column_view.dart';
import 'views/grid_view.dart';
import 'views/table_view.dart';

/// Results page for any module: assets or a data entity.
class ModulePage extends ConsumerStatefulWidget {
  const ModulePage({super.key, required this.moduleId, this.openRecordId});
  final String moduleId;

  /// Deep link `?open=<id>` (or `?open=new`) opens that record on load.
  final String? openRecordId;

  @override
  ConsumerState<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends ConsumerState<ModulePage> {
  String get moduleId => widget.moduleId;
  bool get isAsset => moduleId == 'asset';

  @override
  void initState() {
    super.initState();
    final open = widget.openRecordId;
    if (open != null && open.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isAsset) {
          context.push('/asset/$open');
        } else {
          showRecordDialog(context, moduleId: moduleId, recordId: open == 'new' ? null : open);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(moduleViewProvider(moduleId));
    final results = ref.watch(searchResultsProvider(moduleId));
    final width = MediaQuery.sizeOf(context).width;
    final showFolders = isAsset && width >= 1100 && view.viewMode != ViewMode.column;
    final showSummary = view.showSummary && width >= 1250 && view.viewMode != ViewMode.column;
    final target = isAsset ? targetFor(ref, 'asset') : targetFor(ref, moduleId);

    return Column(
      children: [
        _Toolbar(moduleId: moduleId),
        if (view.selected.isNotEmpty) _SelectionBar(moduleId: moduleId),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showFolders) const SizedBox(width: 264, child: FoldersPanel()),
              Expanded(
                child: UploadDropZone(
                  target: target,
                  child: results.when(
                    skipLoadingOnReload: true,
                    loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) =>
                        ErrorState(error: e, onRetry: () => ref.invalidate(searchResultsProvider(moduleId))),
                    data: (r) => _ResultsBody(moduleId: moduleId, result: r, viewMode: view.viewMode),
                  ),
                ),
              ),
              if (showSummary) SizedBox(width: 272, child: SummaryPanel(moduleId: moduleId)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens a record: the full-screen viewer for assets, the record dialog otherwise.
void openRecord(BuildContext context, WidgetRef ref, String moduleId, Json record, {List<Json>? siblings}) {
  if (moduleId == 'asset') {
    ref.read(viewerNavigationProvider.notifier).set([
      for (final h in siblings ?? [record]) h.id,
    ]);
    context.push('/asset/${record.id}');
  } else {
    showRecordDialog(context, moduleId: moduleId, recordId: record.id);
  }
}

class _ResultsBody extends ConsumerWidget {
  const _ResultsBody({required this.moduleId, required this.result, required this.viewMode});
  final String moduleId;
  final SearchResult result;
  final ViewMode viewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(moduleViewProvider(moduleId).select((s) => s.query));
    if (result.hits.isEmpty && viewMode != ViewMode.column) {
      final filtered = query.text.isNotEmpty || query.activeFilterCount > 0;
      return EmptyState(
        icon: filtered ? Ph.magnifyingGlass : Ph.cloudArrowUp,
        title: filtered ? 'No matches' : 'Nothing here yet',
        message: filtered
            ? 'Try a different search or clear the filters.'
            : moduleId == 'asset'
            ? 'Drag files here to upload them to this folder.'
            : 'Create a record, or drop files here to create one per file.',
        action: filtered
            ? OutlinedButton(
                onPressed: () {
                  ref.read(moduleViewProvider(moduleId).notifier)
                    ..setText('')
                    ..clearFilters();
                },
                child: const Text('Clear search'),
              )
            : null,
      );
    }
    return switch (viewMode) {
      ViewMode.table => ResultsTable(moduleId: moduleId, result: result),
      ViewMode.grid => ResultsGrid(moduleId: moduleId, result: result),
      ViewMode.column => ColumnBrowser(moduleId: moduleId, result: result),
    };
  }
}

class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({required this.moduleId});
  final String moduleId;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  late final _search = TextEditingController(text: ref.read(moduleViewProvider(widget.moduleId)).query.text);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(moduleViewProvider(widget.moduleId).notifier).setText(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.moduleId;
    final c = context.colors;
    final view = ref.watch(moduleViewProvider(id));
    final ctrl = ref.read(moduleViewProvider(id).notifier);
    final result = ref.watch(searchResultsProvider(id)).value;
    final module = ref.watch(moduleByIdProvider(id));
    final narrow = MediaQuery.sizeOf(context).width < 900;
    // Keep the field in sync when the query is changed elsewhere (quick search).
    ref.listen(moduleViewProvider(id).select((s) => s.query.text), (_, next) {
      if (_search.text != next) _search.text = next;
    });

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (id != 'asset' && (module?.isEntity ?? true)) ...[
            FilledButton.icon(
              onPressed: () => showRecordDialog(context, moduleId: id),
              icon: const Icon(Ph.plus, size: 14),
              label: Text(narrow ? 'New' : 'Create new'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            ),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: narrow ? 160 : 280,
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              onSubmitted: ctrl.setText,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search ${module?.name() ?? (id == 'asset' ? 'assets' : id)}',
                prefixIcon: const Icon(Ph.magnifyingGlass, size: 13),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Ph.x, size: 16),
                        onPressed: () {
                          _search.clear();
                          ctrl.setText('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (result != null && !narrow)
            Text(
              '${result.total} ${result.total == 1 ? 'result' : 'results'}',
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          const Spacer(),
          _ViewSwitcher(value: view.viewMode, onChanged: ctrl.setViewMode),
          const SizedBox(width: 6),
          _SortMenu(moduleId: id),
          if (view.viewMode == ViewMode.table) _ColumnsMenu(moduleId: id),
          if (result != null && result.pages > 1) _Pager(moduleId: id, result: result),
          _PageSizeMenu(moduleId: id),
          IconButton(
            tooltip: view.showSummary ? 'Hide summary' : 'Show summary',
            onPressed: ctrl.toggleSummary,
            icon: Icon(Ph.sidebar, size: 15, color: view.showSummary ? context.scheme.primary : c.muted),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(searchResultsProvider(id)),
            icon: Icon(Ph.arrowClockwise, size: 15, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.value, required this.onChanged});
  final ViewMode value;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget btn(ViewMode m, IconData icon, String label) {
      final active = m == value;
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: () => onChanged(m),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: active ? s.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: active ? s.onSurface : context.colors.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: s.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(ViewMode.table, Ph.table, 'Table'),
          btn(ViewMode.grid, Ph.gridFour, 'Grid'),
          btn(ViewMode.column, Ph.columns, 'Columns'),
        ],
      ),
    );
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(moduleViewProvider(moduleId).select((s) => s.query));
    final hits = ref.watch(searchResultsProvider(moduleId)).value?.hits ?? const [];
    final fields = ref.watch(fieldsProvider(moduleId)).value ?? const [];
    final cols = columnsFor(moduleId, fields, hits).where((c) => c.sortable).toList();
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    final label = q.sortField == null
        ? 'Default'
        : cols.where((c) => c.id == q.sortField).firstOrNull?.label ?? q.sortField!;
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      onSelected: (v) => v == '_default' ? ctrl.clearSort() : ctrl.sortBy(v),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: '_default', checked: q.sortField == null, child: const Text('Default')),
        const PopupMenuDivider(),
        for (final c in cols)
          CheckedPopupMenuItem(
            value: c.id,
            checked: q.sortField == c.id,
            child: Row(
              children: [
                Expanded(child: Text(c.label)),
                if (q.sortField == c.id) Icon(q.sortAscending ? Ph.sortAscending : Ph.sortDescending, size: 14),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(q.sortAscending ? Ph.sortAscending : Ph.sortDescending, size: 14, color: context.colors.muted),
            if (MediaQuery.sizeOf(context).width >= 1000) ...[
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColumnsMenu extends ConsumerWidget {
  const _ColumnsMenu({required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(moduleViewProvider(moduleId));
    final hits = ref.watch(searchResultsProvider(moduleId)).value?.hits ?? const [];
    final fields = ref.watch(fieldsProvider(moduleId)).value ?? const [];
    final cols = columnsFor(moduleId, fields, hits);
    final hidden = view.hiddenColumns ?? defaultHidden(moduleId, cols);
    return PopupMenuButton<String>(
      tooltip: 'Columns',
      icon: Icon(Ph.columns, size: 15, color: context.colors.muted),
      onSelected: (id) {
        final next = {...hidden};
        next.contains(id) ? next.remove(id) : next.add(id);
        ref.read(moduleViewProvider(moduleId).notifier).setHiddenColumns(next);
      },
      itemBuilder: (_) => [
        for (final c in cols) CheckedPopupMenuItem(value: c.id, checked: !hidden.contains(c.id), child: Text(c.label)),
      ],
    );
  }
}

class _PageSizeMenu extends ConsumerWidget {
  const _PageSizeMenu({required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(moduleViewProvider(moduleId).select((s) => s.query.hitsPerPage));
    return PopupMenuButton<int>(
      tooltip: 'Page size',
      onSelected: ref.read(moduleViewProvider(moduleId).notifier).setPageSize,
      itemBuilder: (_) => [
        for (final n in [12, 24, 36, 60, 100, 200])
          CheckedPopupMenuItem(value: n, checked: n == size, child: Text('$n per page')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Text('$size', style: const TextStyle(fontSize: 13)),
            Icon(Ph.caretDown, size: 11, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

class _Pager extends ConsumerWidget {
  const _Pager({required this.moduleId, required this.result});
  final String moduleId;
  final SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    return Row(
      children: [
        IconButton(
          onPressed: result.page > 1 ? () => ctrl.setPage(result.page - 1) : null,
          icon: const Icon(Ph.caretLeft, size: 13),
        ),
        Text('${result.page} / ${result.pages}', style: const TextStyle(fontSize: 13)),
        IconButton(
          onPressed: result.page < result.pages ? () => ctrl.setPage(result.page + 1) : null,
          icon: const Icon(Ph.caretRight, size: 13),
        ),
      ],
    );
  }
}

class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(moduleViewProvider(moduleId).select((s) => s.selected));
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    final s = context.scheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: context.colors.accentSoft,
      child: Row(
        children: [
          Icon(Ph.checkSquare, size: 15, color: s.primary),
          const SizedBox(width: 10),
          Text('${selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          TextButton(onPressed: () => ctrl.setSelected({}), child: const Text('Clear')),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: s.error),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Delete ${selected.length} item${selected.length == 1 ? '' : 's'}?',
                message: 'This cannot be undone.',
              );
              if (!ok) return;
              final repo = ref.read(repositoryProvider);
              var failed = 0;
              for (final id in selected) {
                try {
                  await repo.deleteRecord(moduleId, id);
                } catch (_) {
                  failed++;
                }
              }
              ctrl.setSelected({});
              ref.invalidate(searchResultsProvider(moduleId));
              if (context.mounted) {
                showMessage(context, failed == 0 ? 'Deleted' : '$failed could not be deleted', error: failed > 0);
              }
            },
            icon: const Icon(Ph.trash, size: 14),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
