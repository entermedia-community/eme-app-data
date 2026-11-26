import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/values.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../data/columns.dart';
import '../data/views/grid_view.dart';
import '../upload/upload_panel.dart';
import '../upload/upload_queue.dart';
import 'field_inputs.dart';
import '../../core/icons.dart';

/// Opens a record (or a blank form when [recordId] is null).
Future<void> showRecordDialog(
  BuildContext context, {
  required String moduleId,
  String? recordId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => RecordDialog(moduleId: moduleId, recordId: recordId),
  );
}

/// Fields shown first in the form, matching EME's default entity layout.
const _priority = [
  'name',
  'assettitle',
  'displayname',
  'headline',
  'longcaption',
  'alternatetext',
  'keywords',
  'searchcategory',
  'entity_date',
  'editstatus',
];

class RecordDialog extends ConsumerStatefulWidget {
  const RecordDialog({super.key, required this.moduleId, this.recordId});
  final String moduleId;
  final String? recordId;

  @override
  ConsumerState<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends ConsumerState<RecordDialog>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: widget.recordId == null ? 1 : 2,
    vsync: this,
  );
  late var _editing = widget.recordId == null;
  var _saving = false;
  var _showAll = false;
  String? _error;
  Map<String, FieldValue>? _values;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<FieldDef> _editableFields(List<FieldDef> defs, Json record) {
    if (defs.isEmpty) {
      // No field definitions available: offer plain text editing of what the record has.
      final keys = {
        'name',
        ...record.keys,
      }.where((k) => !systemFields.contains(k) && !k.startsWith('_'));
      return [
        for (final k in keys) FieldDef({'id': k, 'name': k}),
      ];
    }
    final list = defs
        .where(
          (f) =>
              f.editable &&
              !f.internal &&
              !f.isComplex &&
              !f.isAssetRef &&
              !f.isCategory &&
              !systemFields.contains(f.id),
        )
        .toList();
    int rank(FieldDef f) {
      final i = _priority.indexOf(f.id);
      return i < 0 ? 100 : i;
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  Future<void> _save(List<FieldDef> fields) async {
    final values = _values!;
    final payload = <String, Object?>{};
    for (final v in values.values) {
      if (widget.recordId == null ? true : v.dirty)
        payload.addAll(v.toPayload());
    }
    payload.removeWhere(
      (k, val) =>
          widget.recordId == null &&
          (val == '' || (val is List && val.isEmpty)),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final id = await repo.save(widget.moduleId, widget.recordId, payload);
      ref.invalidate(searchResultsProvider(widget.moduleId));
      ref.invalidate(recordProvider((type: widget.moduleId, id: id)));
      if (!mounted) return;
      if (widget.recordId == null) {
        Navigator.pop(context);
        showRecordDialog(context, moduleId: widget.moduleId, recordId: id);
        showMessage(context, 'Created');
      } else {
        setState(() {
          _editing = false;
          _values = null;
        });
        showMessage(context, 'Saved');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Json record) async {
    final ok = await confirm(
      context,
      title: 'Delete "${record.title()}"?',
      message: 'This cannot be undone.',
    );
    if (!ok) return;
    try {
      await ref
          .read(repositoryProvider)
          .deleteRecord(widget.moduleId, widget.recordId!);
      ref.invalidate(searchResultsProvider(widget.moduleId));
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Deleted');
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = ref.watch(moduleByIdProvider(widget.moduleId));
    final fieldsAsync = ref.watch(fieldsProvider(widget.moduleId));
    final recordAsync = widget.recordId == null
        ? const AsyncData<Json>({})
        : ref.watch(
            recordProvider((type: widget.moduleId, id: widget.recordId!)),
          );
    final size = MediaQuery.sizeOf(context);
    final c = context.colors;

    final record = recordAsync.value;
    final title = widget.recordId == null
        ? 'New ${module?.name() ?? ''}'
        : (record?.title() ?? '…');

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width.clamp(320, 1100),
        height: size.height.clamp(400, 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: c.shell,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        moduleIcon(module, filled: true),
                        size: 16,
                        color: context.scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        module?.name() ?? widget.moduleId,
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      Icon(Ph.caretRight, size: 11, color: c.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Ph.x, size: 15),
                      ),
                    ],
                  ),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(
                        text: widget.recordId == null
                            ? 'Details'
                            : module?.name() ?? 'Details',
                      ),
                      if (widget.recordId != null) const Tab(text: 'Files'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch ((fieldsAsync, recordAsync)) {
                (AsyncValue(isLoading: true, hasValue: false), _) ||
                (
                  _,
                  AsyncValue(isLoading: true, hasValue: false),
                ) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                (_, AsyncValue(:final error?)) => ErrorState(error: error),
                _ => TabBarView(
                  controller: _tabs,
                  children: [
                    _editing
                        ? _form(
                            _editableFields(
                              fieldsAsync.value ?? const [],
                              record ?? {},
                            ),
                            record ?? {},
                          )
                        : _details(fieldsAsync.value ?? const [], record ?? {}),
                    if (widget.recordId != null)
                      _FilesTab(
                        moduleId: widget.moduleId,
                        record: record ?? {},
                      ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(List<FieldDef> defs, Json record) {
    final c = context.colors;
    final labels = {for (final f in defs) f.id: f.label()};
    final entries =
        [
          for (final e in record.entries)
            if (!e.key.startsWith('_') &&
                !systemFields.contains(e.key) &&
                displayValue(e.value).isNotEmpty)
              (labels[e.key] ?? e.key, e.value),
        ]..sort((a, b) {
          int rank(String k) => _priority.indexOf(
            labels.entries.where((l) => l.value == k).firstOrNull?.key ?? k,
          );
          final ra = rank(a.$1), rb = rank(b.$1);
          return (ra < 0 ? 100 : ra).compareTo(rb < 0 ? 100 : rb);
        });
    final thumb = record['_thumbpath'] as String?;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 28,
          runSpacing: 20,
          children: [
            if (thumb != null)
              SizedBox(
                width: 220,
                height: 160,
                child: AssetThumb(
                  sourcepath: thumb,
                  preset: Preset.medium,
                  radius: 10,
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: LayoutBuilder(
                builder: (context, box) {
                  final colW = box.maxWidth >= 600
                      ? (box.maxWidth - 24) / 2
                      : box.maxWidth;
                  return Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      for (final e in entries)
                        SizedBox(
                          width: colW,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.$1,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              _valueView(e.$2),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Ph.pencilSimple, size: 14),
              label: const Text('Edit'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.scheme.error,
                side: BorderSide(
                  color: context.scheme.error.withValues(alpha: 0.5),
                ),
              ),
              onPressed: () => _delete(record),
              icon: const Icon(Ph.trash, size: 14),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _valueView(Object? v) {
    if (v is List && v.length > 1) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final x in v) Pill(displayValue(x))],
      );
    }
    if (isLanguageMap(v)) {
      final m = v as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in m.entries)
            Text.rich(
              TextSpan(
                children: [
                  if (m.length > 1)
                    TextSpan(
                      text: '${knownLanguages[e.key] ?? e.key}: ',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  TextSpan(text: '${e.value}'),
                ],
              ),
            ),
        ],
      );
    }
    return SelectableText(
      displayValue(v),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _form(List<FieldDef> fields, Json record) {
    _values ??= {for (final f in fields) f.id: FieldValue(f, record[f.id])};
    final primary = fields.where((f) => _priority.contains(f.id)).toList();
    final rest = fields.where((f) => !_priority.contains(f.id)).toList();
    final shown = primary.isEmpty
        ? fields
        : [...primary, if (_showAll) ...rest];

    return LayoutBuilder(
      builder: (context, box) {
        final twoCol = box.maxWidth >= 760;
        final colW = twoCol ? (box.maxWidth - 48 - 24) / 2 : box.maxWidth - 48;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 20,
                    children: [
                      for (final f in shown)
                        SizedBox(
                          width: f.multilanguage || f.isTextArea || f.isMulti
                              ? (twoCol ? colW : colW)
                              : colW,
                          child: FieldInput(
                            value: _values![f.id]!,
                            onChanged: () => setState(() {}),
                          ),
                        ),
                    ],
                  ),
                  if (primary.isNotEmpty && rest.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showAll = !_showAll),
                        icon: Icon(
                          _showAll ? Ph.caretUp : Ph.caretDown,
                          size: 12,
                        ),
                        label: Text(
                          _showAll
                              ? 'Fewer fields'
                              : 'More fields (${rest.length})',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(fields),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Ph.floppyDisk, size: 14),
                    label: Text(widget.recordId == null ? 'Create' : 'Save'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => widget.recordId == null
                              ? Navigator.pop(context)
                              : setState(() {
                                  _editing = false;
                                  _values = null;
                                }),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  if (_error != null)
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: context.scheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Files stored in the record's folder, with drag-and-drop upload.
class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.moduleId, required this.record});
  final String moduleId;
  final Json record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folderId = valueIds(record['rootcategory']).firstOrNull;
    final target = RecordTarget(
      moduleId: moduleId,
      recordId: record.id,
      folder: record.sourcepath ?? record.title(),
      label: record.title(),
    );
    final files = folderId == null
        ? null
        : ref.watch(
            adhocSearchProvider((
              module: 'asset',
              query: SearchQuery(hitsPerPage: 200, categoryId: folderId),
            )),
          );
    return UploadDropZone(
      target: target,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Text(
                  files?.value == null
                      ? 'Files'
                      : '${files!.value!.total} files',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    await pickAndUpload(context, ref, target);
                  },
                  icon: const Icon(Ph.cloudArrowUp, size: 14),
                  label: const Text('Upload files'),
                ),
              ],
            ),
          ),
          Expanded(
            child: files == null
                ? const EmptyState(
                    icon: Ph.cloudArrowUp,
                    title: 'Drop files here',
                    message: 'Files are stored in this record\'s folder.',
                  )
                : files.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (e, _) => ErrorState(error: e),
                    data: (r) => r.hits.isEmpty
                        ? const EmptyState(
                            icon: Ph.cloudArrowUp,
                            title: 'No files yet',
                            message: 'Drag files here to add them.',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 0.82,
                                ),
                            itemCount: r.hits.length,
                            itemBuilder: (_, i) => GridCard(
                              moduleId: 'asset',
                              record: r.hits[i],
                              selected: false,
                              onSelect: () {},
                              onOpen: () {
                                ref.read(viewerNavigationProvider.notifier).set(
                                  [for (final h in r.hits) h.id],
                                );
                                final router = GoRouter.of(context);
                                Navigator.pop(context);
                                router.push('/asset/${r.hits[i].id}');
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
