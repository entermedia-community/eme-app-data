import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/values.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../data/repository.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../upload/upload_panel.dart';
import '../../upload/upload_queue.dart';
import '../module_page.dart';
import '../../../core/icons.dart';

/// Miller-column browser.
///  - Assets: folder → subfolder → … → files in the folder → preview.
///  - Entities: records → files in the record's folder → preview.
class ColumnBrowser extends ConsumerStatefulWidget {
  const ColumnBrowser({
    super.key,
    required this.moduleId,
    required this.result,
  });
  final String moduleId;
  final SearchResult result;

  @override
  ConsumerState<ColumnBrowser> createState() => _ColumnBrowserState();
}

class _ColumnBrowserState extends ConsumerState<ColumnBrowser> {
  final _scroll = ScrollController();

  /// Assets mode: chosen category at each depth.
  final _path = <CategoryNode>[];
  Json? _record;
  Json? _asset;

  bool get _isAsset => widget.moduleId == 'asset';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final panes = <Widget>[];
    if (_isAsset) {
      final tree = ref.watch(categoryTreeProvider);
      final root = tree.value;
      if (root == null) {
        return tree.hasError
            ? ErrorState(error: tree.error!)
            : const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      var level = root;
      for (var depth = 0; depth <= _path.length; depth++) {
        final current = level;
        final selectedChild = depth < _path.length ? _path[depth] : null;
        panes.add(
          _Pane(
            title: depth == 0 ? 'All folders' : current.name,
            child: _FolderAndFilesList(
              folder: current,
              showFiles: depth > 0,
              selectedFolderId: selectedChild?.id,
              selectedAssetId: depth == _path.length ? _asset?.id : null,
              onFolder: (n) => setState(() {
                _path
                  ..removeRange(depth, _path.length)
                  ..add(n);
                _asset = null;
                _revealEnd();
              }),
              onAsset: (a) => setState(() {
                _path.removeRange(depth, _path.length);
                _asset = a;
                _revealEnd();
              }),
            ),
          ),
        );
        if (selectedChild == null) break;
        level = selectedChild;
      }
    } else {
      panes.add(
        _Pane(
          title:
              ref.watch(moduleByIdProvider(widget.moduleId))?.name() ??
              widget.moduleId,
          child: ListView(
            children: [
              for (final r in widget.result.hits)
                _ItemTile(
                  title: r.title(),
                  sourcepath: r['_thumbpath'] as String?,
                  icon: moduleIcon(
                    ref.watch(moduleByIdProvider(widget.moduleId)),
                  ),
                  selected: _record?.id == r.id,
                  trailing: Ph.caretRight,
                  onTap: () => setState(() {
                    _record = r;
                    _asset = null;
                    _revealEnd();
                  }),
                  onDoubleTap: () =>
                      openRecord(context, ref, widget.moduleId, r),
                ),
            ],
          ),
        ),
      );
      final rec = _record;
      final folderId = rec == null
          ? null
          : valueIds(rec['rootcategory']).firstOrNull;
      if (rec != null) {
        panes.add(
          _Pane(
            title: rec.title(),
            child: UploadDropZone(
              target: RecordTarget(
                moduleId: widget.moduleId,
                recordId: rec.id,
                folder: rec.sourcepath ?? rec.title(),
                label: rec.title(),
              ),
              child: folderId == null
                  ? EmptyState(
                      icon: Ph.folder,
                      title: 'No folder',
                      message: 'This record has no files folder yet.',
                    )
                  : _FilesList(
                      categoryId: folderId,
                      selectedId: _asset?.id,
                      onAsset: (a) => setState(() {
                        _asset = a;
                        _revealEnd();
                      }),
                    ),
            ),
          ),
        );
      }
    }

    final preview = _asset != null
        ? _AssetPreview(asset: _asset!)
        : (!_isAsset && _record != null)
        ? _RecordPreview(moduleId: widget.moduleId, record: _record!)
        : const EmptyState(
            icon: Ph.columns,
            title: 'Select an item',
            message: 'Pick a folder or record to browse its files.',
          );

    return LayoutBuilder(
      builder: (context, box) {
        const paneW = 260.0;
        final previewW = (box.maxWidth - panes.length * paneW).clamp(
          360.0,
          720.0,
        );
        return Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              height: box.maxHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in panes) SizedBox(width: paneW, child: p),
                  SizedBox(width: previewW, child: preview),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            color: context.scheme.surfaceContainerLow,
            child: Text(
              title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.colors.muted,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FolderAndFilesList extends ConsumerWidget {
  const _FolderAndFilesList({
    required this.folder,
    required this.showFiles,
    required this.selectedFolderId,
    required this.selectedAssetId,
    required this.onFolder,
    required this.onAsset,
  });

  final CategoryNode folder;
  final bool showFiles;
  final String? selectedFolderId;
  final String? selectedAssetId;
  final ValueChanged<CategoryNode> onFolder;
  final ValueChanged<Json> onAsset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = showFiles
        ? ref.watch(
            adhocSearchProvider((
              module: 'asset',
              query: _directFiles(folder.id),
            )),
          )
        : null;
    final folderTarget = FolderTarget(
      folder.path,
      folder.path.isEmpty ? 'All' : folder.path,
    );
    return UploadDropZone(
      enabled: showFiles,
      target: folderTarget,
      child: ListView(
        children: [
          for (final c in folder.children)
            _ItemTile(
              title: c.name,
              icon: Ph.folder,
              iconColor: const Color(0xFFF2B53A),
              selected: c.id == selectedFolderId,
              trailing: Ph.caretRight,
              onTap: () => onFolder(c),
            ),
          if (files != null)
            ...files.when(
              loading: () => [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              error: (e, _) => [
                Padding(padding: const EdgeInsets.all(12), child: Text('$e')),
              ],
              data: (r) => [
                for (final a in r.hits)
                  _ItemTile(
                    title: a.title(),
                    sourcepath: a.sourcepath,
                    icon: iconForAsset(a),
                    selected: a.id == selectedAssetId,
                    onTap: () => onAsset(a),
                    onDoubleTap: () =>
                        openRecord(context, ref, 'asset', a, siblings: r.hits),
                  ),
              ],
            ),
          if (folder.children.isEmpty &&
              (files?.value?.hits.isEmpty ?? true) &&
              !(files?.isLoading ?? false))
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Empty folder — drop files here',
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Files directly inside a folder (not in its subfolders).
SearchQuery _directFiles(String categoryId) => SearchQuery(
  hitsPerPage: 200,
  terms: [
    {'field': 'category-exact', 'operation': 'exact', 'value': categoryId},
  ],
);

class _FilesList extends ConsumerWidget {
  const _FilesList({
    required this.categoryId,
    required this.selectedId,
    required this.onAsset,
  });
  final String categoryId;
  final String? selectedId;
  final ValueChanged<Json> onAsset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(
      adhocSearchProvider((
        module: 'asset',
        query: SearchQuery(hitsPerPage: 200, categoryId: categoryId),
      )),
    );
    return files.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => ErrorState(error: e),
      data: (r) => r.hits.isEmpty
          ? const EmptyState(
              icon: Ph.cloudArrowUp,
              title: 'No files',
              message: 'Drop files here to add them.',
            )
          : ListView(
              children: [
                for (final a in r.hits)
                  _ItemTile(
                    title: a.title(),
                    sourcepath: a.sourcepath,
                    icon: iconForAsset(a),
                    selected: a.id == selectedId,
                    onTap: () => onAsset(a),
                    onDoubleTap: () =>
                        openRecord(context, ref, 'asset', a, siblings: r.hits),
                  ),
              ],
            ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.sourcepath,
    this.trailing,
    this.iconColor,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final String? sourcepath;
  final IconData? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Material(
      color: selected ? s.primary.withValues(alpha: 0.9) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: sourcepath != null
                    ? AssetThumb(
                        sourcepath: sourcepath,
                        fallbackIcon: icon,
                        radius: 5,
                      )
                    : Icon(
                        icon,
                        size: 16,
                        color: selected
                            ? s.onPrimary
                            : (iconColor ?? context.colors.muted),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? s.onPrimary : s.onSurface,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(
                  trailing,
                  size: 11,
                  color: selected ? s.onPrimary : context.colors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetPreview extends ConsumerWidget {
  const _AssetPreview({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <(String, String)>[
      ('File name', displayValue(asset['name'])),
      ('Type', displayValue(asset['assettype'])),
      ('Format', displayValue(asset['fileformat'])),
      ('Size', formatBytes(asset['filesize'])),
      if (asset['width'] != null)
        ('Dimensions', '${asset['width']} × ${asset['height']}'),
      ('Status', displayValue(asset['editstatus'])),
      ('Added', displayValue(asset['assetaddeddate'])),
      (
        'Folder',
        asset.sourcepath
                ?.split('/')
                .reversed
                .skip(1)
                .toList()
                .reversed
                .join(' / ') ??
            '',
      ),
    ].where((r) => r.$2.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: AssetThumb(
            sourcepath: asset.sourcepath,
            preset: Preset.large,
            fit: BoxFit.contain,
            fallbackIcon: iconForAsset(asset),
            radius: 10,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          asset.title(),
          style: context.text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final r in rows) _KV(r.$1, r.$2),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => openRecord(context, ref, 'asset', asset),
            icon: const Icon(Ph.arrowsOut, size: 14),
            label: const Text('Open'),
          ),
        ),
      ],
    );
  }
}

class _RecordPreview extends ConsumerWidget {
  const _RecordPreview({required this.moduleId, required this.record});
  final String moduleId;
  final Json record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = record.entries
        .where(
          (e) =>
              !e.key.startsWith('_') &&
              !const {
                'id',
                'description',
                'emrecordstatus',
                'sourcepath',
              }.contains(e.key),
        )
        .map((e) => (e.key, displayValue(e.value)))
        .where((e) => e.$2.isNotEmpty)
        .take(12);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: AssetThumb(
            sourcepath: record['_thumbpath'] as String?,
            preset: Preset.large,
            fallbackIcon: moduleIcon(
              ref.watch(moduleByIdProvider(moduleId)),
              filled: true,
            ),
            background: const Color(0xFF55658F),
            radius: 10,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          record.title(),
          style: context.text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final e in entries) _KV(e.$1, e.$2),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => openRecord(context, ref, moduleId, record),
            icon: const Icon(Ph.pencilSimple, size: 14),
            label: const Text('Open record'),
          ),
        ),
      ],
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            k,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
