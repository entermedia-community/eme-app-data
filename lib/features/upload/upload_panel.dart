import 'package:eme_data_app/core/ph.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/values.dart';
import '../../theme/app_theme.dart';
import 'upload_queue.dart';

/// Floating progress card listing the upload queue.
class UploadPanel extends ConsumerStatefulWidget {
  const UploadPanel({super.key});

  @override
  ConsumerState<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends ConsumerState<UploadPanel> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(uploadQueueProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final s = context.scheme;
    final active = items.where((i) => !i.finished).toList();
    final overall = active.isEmpty
        ? 1.0
        : active.fold<int>(0, (a, i) => a + i.sent) /
              active.fold<int>(0, (a, i) => a + i.size).clamp(1, 1 << 62);
    return Material(
      elevation: 12,
      color: s.surfaceContainer,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Icon(
                      active.isEmpty ? PhFill.checkCircle : Ph.cloudArrowUp,
                      size: 16,
                      color: s.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        uploadSummary(items),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Ph.caretDown : Ph.caretUp,
                        size: 14,
                      ),
                    ),
                    if (active.isEmpty)
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(uploadQueueProvider.notifier)
                            .clearFinished(),
                        icon: const Icon(Ph.x, size: 13),
                      ),
                  ],
                ),
              ),
            ),
            if (active.isNotEmpty)
              LinearProgressIndicator(value: overall, minHeight: 2),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) =>
                      _UploadRow(item: items[items.length - 1 - i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends ConsumerWidget {
  const _UploadRow({required this.item});
  final UploadItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.scheme;
    final muted = context.colors.muted;
    final (icon, color) = switch (item.status) {
      UploadStatus.done => (PhFill.checkCircle, s.primary),
      UploadStatus.error => (PhFill.warningCircle, s.error),
      UploadStatus.cancelled => (Ph.prohibit, muted),
      _ => (Ph.fileArrowUp, muted),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 3),
                if (item.status == UploadStatus.uploading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 3,
                    ),
                  )
                else
                  Text(
                    item.status == UploadStatus.error
                        ? item.error ?? 'Failed'
                        : '${formatBytes(item.size)} · ${item.target.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: item.status == UploadStatus.error
                          ? s.error
                          : muted,
                    ),
                  ),
              ],
            ),
          ),
          if (item.status == UploadStatus.error)
            IconButton(
              tooltip: 'Retry',
              onPressed: () =>
                  ref.read(uploadQueueProvider.notifier).retry(item),
              icon: const Icon(Ph.arrowClockwise, size: 13),
            )
          else if (!item.finished)
            IconButton(
              tooltip: 'Cancel',
              onPressed: () =>
                  ref.read(uploadQueueProvider.notifier).cancel(item),
              icon: const Icon(Ph.x, size: 16),
            ),
        ],
      ),
    );
  }
}

/// Wraps [child] so files dropped anywhere on it are uploaded to [target].
/// Shows a full-surface overlay while files are dragged over.
class UploadDropZone extends ConsumerStatefulWidget {
  const UploadDropZone({
    super.key,
    required this.target,
    required this.child,
    this.enabled = true,
  });
  final UploadTarget target;
  final Widget child;
  final bool enabled;

  @override
  ConsumerState<UploadDropZone> createState() => _UploadDropZoneState();
}

class _UploadDropZoneState extends ConsumerState<UploadDropZone> {
  var _dragging = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final s = context.scheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        if (details.files.isEmpty) return;
        ref
            .read(uploadQueueProvider.notifier)
            .add(details.files, widget.target);
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.primary, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhFill.cloudArrowUp, size: 44, color: s.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Drop to upload',
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.target.label,
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
