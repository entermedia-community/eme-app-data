import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/api_client.dart';
import '../../core/download.dart';
import '../../core/values.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../record/record_dialog.dart';

/// Full-screen asset details: Data | Viewer | History | Download, with prev/next.
class AssetViewerPage extends ConsumerStatefulWidget {
  const AssetViewerPage({super.key, required this.assetId, this.initialTab});
  final String assetId;

  /// `data`, `viewer`, `history` or `download` (deep link `?tab=`).
  final String? initialTab;

  @override
  ConsumerState<AssetViewerPage> createState() => _AssetViewerPageState();
}

class _AssetViewerPageState extends ConsumerState<AssetViewerPage>
    with SingleTickerProviderStateMixin {
  static const _tabNames = ['data', 'viewer', 'history', 'download'];
  late final _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: _tabNames.indexOf(widget.initialTab ?? 'data').clamp(0, 3),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final ids = ref.read(viewerNavigationProvider);
    final i = ids.indexOf(widget.assetId);
    if (i < 0) return;
    final next = i + delta;
    if (next < 0 || next >= ids.length) return;
    context.pushReplacement('/asset/${ids[next]}');
  }

  void _close() => context.canPop() ? context.pop() : context.go('/m/asset');

  @override
  Widget build(BuildContext context) {
    final asset = ref.watch(
      recordProvider((type: 'asset', id: widget.assetId)),
    );
    final ids = ref.watch(viewerNavigationProvider);
    final index = ids.indexOf(widget.assetId);
    final c = context.colors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: context.scheme.surface,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: c.shell,
                child: Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Close (Esc)',
                            onPressed: _close,
                            icon: const Icon(Ph.x, size: 15),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              asset.value?.sourcepath ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          if (index >= 0 && ids.length > 1) ...[
                            Text(
                              '${index + 1} of ${ids.length}',
                              style: TextStyle(color: c.muted, fontSize: 12.5),
                            ),
                            IconButton(
                              tooltip: 'Previous (←)',
                              onPressed: index > 0 ? () => _go(-1) : null,
                              icon: const Icon(Ph.caretLeft, size: 15),
                            ),
                            IconButton(
                              tooltip: 'Next (→)',
                              onPressed: index < ids.length - 1
                                  ? () => _go(1)
                                  : null,
                              icon: const Icon(Ph.caretRight, size: 15),
                            ),
                          ],
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: const [
                          Tab(
                            icon: Icon(Ph.info, size: 14),
                            text: 'Data',
                            iconMargin: EdgeInsets.zero,
                            height: 44,
                          ),
                          Tab(
                            icon: Icon(Ph.cornersOut, size: 14),
                            text: 'Viewer',
                            iconMargin: EdgeInsets.zero,
                            height: 44,
                          ),
                          Tab(
                            icon: Icon(Ph.clockCounterClockwise, size: 14),
                            text: 'History',
                            iconMargin: EdgeInsets.zero,
                            height: 44,
                          ),
                          Tab(
                            icon: Icon(Ph.downloadSimple, size: 14),
                            text: 'Download',
                            iconMargin: EdgeInsets.zero,
                            height: 44,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: asset.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => ErrorState(
                    error: e,
                    onRetry: () => ref.invalidate(
                      recordProvider((type: 'asset', id: widget.assetId)),
                    ),
                  ),
                  data: (a) => TabBarView(
                    controller: _tabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _DataTab(asset: a, onDeleted: _close),
                      _ViewerTab(asset: a),
                      _HistoryTab(asset: a),
                      _DownloadTab(asset: a),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataTab extends ConsumerWidget {
  const _DataTab({required this.asset, required this.onDeleted});
  final Json asset;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final preview = Column(
      children: [
        Expanded(
          child: Container(
            color: context.colors.shell,
            padding: const EdgeInsets.all(24),
            child: AssetThumb(
              sourcepath: asset.sourcepath,
              preset: Preset.large,
              fit: BoxFit.contain,
              fallbackIcon: iconForAsset(asset),
              background: Colors.transparent,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Pill(
                displayValue(asset['editstatus']).isEmpty
                    ? 'No status'
                    : displayValue(asset['editstatus']),
                icon: Ph.circle,
                color: const Color(0xFFF2B53A),
              ),
              OutlinedButton.icon(
                onPressed: () => downloadOriginal(context, ref, asset),
                icon: const Icon(Ph.downloadSimple, size: 14),
                label: const Text('Original'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.scheme.error,
                ),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Delete "${asset.title()}"?',
                    message: 'The file and its renditions will be removed.',
                  );
                  if (!ok) return;
                  try {
                    await ref
                        .read(repositoryProvider)
                        .deleteRecord('asset', asset.id);
                    ref.invalidate(searchResultsProvider('asset'));
                    onDeleted();
                  } catch (e) {
                    if (context.mounted)
                      showMessage(context, '$e', error: true);
                  }
                },
                icon: const Icon(Ph.trash, size: 14),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ],
    );
    final details = _AssetDetails(asset: asset);
    if (!wide) {
      return ListView(
        children: [
          SizedBox(height: 420, child: preview),
          details,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: preview),
        VerticalDivider(width: 1, color: context.scheme.outlineVariant),
        Expanded(flex: 4, child: SingleChildScrollView(child: details)),
      ],
    );
  }
}

class _AssetDetails extends ConsumerWidget {
  const _AssetDetails({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget section(
      String title,
      List<(String, Object?)> rows, {
      VoidCallback? onEdit,
    }) {
      final visible = rows
          .where((r) => r.$2 != null && displayValue(r.$2).isNotEmpty)
          .toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Ph.pencilSimple, size: 13),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        r.$1,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: _value(context, r.$2)),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    void edit() =>
        showRecordDialog(context, moduleId: 'asset', recordId: asset.id).then((
          _,
        ) {
          ref.invalidate(recordProvider((type: 'asset', id: asset.id)));
        });

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            asset.title(),
            style: context.text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 22),
          section('Details', [
            ('Headline', asset['headline']),
            ('Caption', asset['longcaption']),
            ('Alt text', asset['alternatetext']),
            ('Author', asset['author']),
            ('Keywords', asset['keywords']),
          ], onEdit: edit),
          section('Status', [
            ('Edit status', asset['editstatus']),
            ('Owner', asset['owner']),
            ('AI tags', asset['keywordsai']),
            ('Semantic topics', asset['semantictopics']),
            ('Language', asset['language']),
          ]),
          section('File', [
            ('File name', asset['name']),
            ('Type', asset['assettype']),
            ('Format', asset['fileformat']),
            ('Size', formatBytes(asset['filesize'])),
            (
              'Dimensions',
              asset['width'] == null
                  ? null
                  : '${asset['width']} × ${asset['height']} px',
            ),
            ('Pages', asset['pages']),
            ('Added', asset['assetaddeddate']),
            ('Modified', asset['assetmodificationdate']),
            ('Folders', asset['category']),
          ]),
        ],
      ),
    );
  }

  Widget _value(BuildContext context, Object? v) {
    if (v is List) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final x in v)
            if (displayValue(x).isNotEmpty && displayValue(x) != 'All')
              Pill(displayValue(x)),
        ],
      );
    }
    if (isLanguageMap(v)) {
      final m = v as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in m.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (m.length > 1)
                      TextSpan(
                        text: '${knownLanguages[e.key] ?? e.key}: ',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    TextSpan(text: '${e.value}'),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return SelectableText(
      displayValue(v),
      style: const TextStyle(fontSize: 14, height: 1.4),
    );
  }
}

class _ViewerTab extends ConsumerWidget {
  const _ViewerTab({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = '${asset['mediarendertype'] ?? ''}';
    final format = '${(asset['fileformat'] as Map?)?['id'] ?? ''}';
    if (type == 'document' || format == 'pdf') return _PdfView(asset: asset);
    if (type == 'image') {
      return Container(
        color: context.colors.shell,
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: AssetThumb(
              sourcepath: asset.sourcepath,
              preset: Preset.xl,
              fit: BoxFit.contain,
              background: Colors.transparent,
              radius: 0,
            ),
          ),
        ),
      );
    }
    return EmptyState(
      icon: iconForAsset(asset),
      title: 'Preview not available in the browser',
      message:
          'Download the original to view this ${type.isEmpty ? 'file' : type}.',
      action: FilledButton.icon(
        onPressed: () => downloadOriginal(context, ref, asset),
        icon: const Icon(Ph.downloadSimple, size: 14),
        label: const Text('Download original'),
      ),
    );
  }
}

final _pdfBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>((
  ref,
  url,
) {
  return ref.watch(apiClientProvider).getBytes(url);
});

class _PdfView extends ConsumerWidget {
  const _PdfView({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = '${(asset['fileformat'] as Map?)?['id'] ?? ''}';
    final sp = asset.sourcepath ?? '';
    // PDFs are shown from the original; other documents from the generated PDF rendition.
    final url = format == 'pdf'
        ? originalUrl(asset)
        : 'module/asset/generated/${encodePath(sp)}/document.pdf';
    final bytes = ref.watch(_pdfBytesProvider(url));
    return bytes.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => ErrorState(error: e),
      data: (b) => Container(
        color: context.colors.shell,
        child: PdfViewer.data(
          b,
          sourceName: '${asset.id}.pdf',
          params: const PdfViewerParams(
            backgroundColor: Colors.transparent,
            margin: 16,
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(versionsProvider(asset.id));
    final c = context.colors;
    return versions.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => ErrorState(error: e),
      data: (list) {
        final entries = [
          for (final v in list)
            (
              'Version ${v['number'] ?? ''}',
              [
                displayValue(v['userid']),
                displayValue(v['message']),
              ].where((s) => s.isNotEmpty).join(' – '),
              displayValue(v['date']),
              formatBytes(v['bytes'] ?? v['size']),
            ),
          if (list.isEmpty)
            (
              'Version 1',
              '${displayValue(asset['owner'])} – Imported',
              displayValue(
                asset['assetmodificationdate'] ?? asset['assetaddeddate'],
              ),
              formatBytes(asset['filesize']),
            ),
        ];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final (i, e) in entries.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? c.accentSoft
                              : context.scheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Ph.clockCounterClockwise,
                          size: 14,
                          color: i == 0 ? context.scheme.primary : c.muted,
                        ),
                      ),
                      if (i < entries.length - 1)
                        Container(
                          width: 2,
                          height: 46,
                          color: context.scheme.outlineVariant,
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.$1,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (e.$2.isNotEmpty)
                            Text(
                              e.$2,
                              style: TextStyle(color: c.muted, fontSize: 12.5),
                            ),
                          Text(
                            [e.$3, e.$4].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(color: c.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DownloadTab extends ConsumerWidget {
  const _DownloadTab({required this.asset});
  final Json asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = [
      for (final d in asset['downloads'] as List? ?? const [])
        if (d is Map) d,
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _DownloadRow(
          icon: Ph.fileArrowDown,
          title: 'Original file',
          subtitle:
              '${displayValue(asset['name'])} · ${formatBytes(asset['filesize'])}',
          onTap: () => downloadOriginal(context, ref, asset),
          primary: true,
        ),
        if (downloads.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Renditions',
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final d in downloads)
          _DownloadRow(
            icon: Ph.image,
            title: localized(d['name']),
            subtitle: '${d['url'] ?? ''}'.split('/').last,
            onTap: () => _download(
              context,
              ref,
              '${d['download'] ?? d['url']}',
              '${d['url'] ?? ''}'.split('/').last,
            ),
          ),
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          size: 18,
          color: primary ? context.scheme.primary : context.colors.muted,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: context.colors.muted, fontSize: 12),
        ),
        trailing: primary
            ? FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Ph.downloadSimple, size: 14),
                label: const Text('Download'),
              )
            : OutlinedButton(onPressed: onTap, child: const Text('Download')),
      ),
    );
  }
}

String originalUrl(Json asset) {
  final sp = asset.sourcepath ?? '';
  final name = '${asset['name'] ?? sp.split('/').last}';
  return 'module/asset/downloads/originals/${encodePath(sp)}/${Uri.encodeComponent(name)}';
}

Future<void> downloadOriginal(
  BuildContext context,
  WidgetRef ref,
  Json asset,
) => _download(
  context,
  ref,
  originalUrl(asset),
  '${asset['name'] ?? 'download'}',
);

Future<void> _download(
  BuildContext context,
  WidgetRef ref,
  String url,
  String fileName,
) async {
  showMessage(context, 'Preparing $fileName…');
  try {
    final bytes = await ref.read(apiClientProvider).getBytes(url);
    saveBytes(bytes, fileName);
  } catch (e) {
    if (context.mounted) showMessage(context, '$e', error: true);
  }
}
