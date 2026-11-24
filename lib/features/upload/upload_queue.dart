import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/values.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../auth/auth_controller.dart';

/// Where dropped or picked files go.
sealed class UploadTarget {
  const UploadTarget(this.label, {this.refreshModule});
  final String label;

  /// Module whose results reload when uploads finish.
  final String? refreshModule;
}

/// A plain folder (category path).
class FolderTarget extends UploadTarget {
  const FolderTarget(this.folder, String label, {super.refreshModule = 'asset'}) : super(label);
  final String folder;
}

/// Files attached to one entity record (stored in its folder).
class RecordTarget extends UploadTarget {
  const RecordTarget({required this.moduleId, required this.recordId, required this.folder, required String label})
    : super(label, refreshModule: moduleId);
  final String moduleId;
  final String recordId;
  final String folder;
}

/// "Bulk folders from files": each file becomes a new entity record named after it.
class BulkEntityTarget extends UploadTarget {
  const BulkEntityTarget({required this.moduleId, required String label, this.extra = const {}})
    : super(label, refreshModule: moduleId);
  final String moduleId;

  /// Shared values applied to every new record (tags, categories, date...).
  final Json extra;
}

enum UploadStatus { queued, uploading, done, error, cancelled }

class UploadItem {
  UploadItem({required this.id, required this.file, required this.size, required this.target});
  final int id;
  final XFile file;
  final int size;
  final UploadTarget target;
  int sent = 0;
  UploadStatus status = UploadStatus.queued;
  String? error;
  String? assetId;
  final cancel = CancelToken();

  double get progress => size == 0 ? 0 : (sent / size).clamp(0, 1);
  bool get finished => status == UploadStatus.done || status == UploadStatus.error || status == UploadStatus.cancelled;
}

class UploadQueue extends Notifier<List<UploadItem>> {
  static const _concurrency = 3;
  var _nextId = 0;
  var _running = 0;

  @override
  List<UploadItem> build() => const [];

  EmeRepository get _repo => ref.read(repositoryProvider);

  Future<void> add(List<XFile> files, UploadTarget target) async {
    final items = <UploadItem>[];
    for (final f in files) {
      items.add(UploadItem(id: _nextId++, file: f, size: await f.length(), target: target));
    }
    if (items.isEmpty) return;
    state = [...state, ...items];
    _pump();
  }

  void cancel(UploadItem item) {
    if (item.finished) return;
    item.cancel.cancel();
    item.status = UploadStatus.cancelled;
    _changed();
  }

  void retry(UploadItem item) {
    if (item.status != UploadStatus.error) return;
    final again = UploadItem(id: _nextId++, file: item.file, size: item.size, target: item.target);
    state = [for (final i in state) i == item ? again : i];
    _pump();
  }

  void clearFinished() => state = state.where((i) => !i.finished).toList();

  void _changed() => state = [...state];

  void _pump() {
    while (_running < _concurrency) {
      final next = state.where((i) => i.status == UploadStatus.queued).firstOrNull;
      if (next == null) break;
      _running++;
      next.status = UploadStatus.uploading;
      _changed();
      unawaited(
        _upload(next).whenComplete(() {
          _running--;
          _changed();
          _pump();
          if (_running == 0) _refreshAfterBatch();
        }),
      );
    }
  }

  Future<void> _upload(UploadItem item) async {
    try {
      final target = item.target;
      final (folder, recordId, moduleId) = switch (target) {
        FolderTarget t => (t.folder, null, null),
        RecordTarget t => (t.folder, t.recordId, t.moduleId),
        BulkEntityTarget t => await _createEntityFor(item, t),
      };
      var last = DateTime.now();
      final asset = await _repo.uploadAsset(
        fileName: item.file.name,
        stream: () => item.file.openRead(),
        length: item.size,
        folder: folder,
        cancelToken: item.cancel,
        onProgress: (sent, total) {
          item.sent = sent;
          // Throttle rebuilds to ~10/s.
          if (DateTime.now().difference(last).inMilliseconds > 100) {
            last = DateTime.now();
            _changed();
          }
        },
      );
      item.assetId = asset['id']?.toString();
      if (target is BulkEntityTarget && recordId != null && moduleId != null && item.assetId != null) {
        // Use the uploaded file as the new record's picture.
        await _repo.save(moduleId, recordId, {'primarymedia': item.assetId});
      }
      item.sent = item.size;
      item.status = UploadStatus.done;
    } catch (e) {
      if (item.status == UploadStatus.cancelled) return;
      item.status = UploadStatus.error;
      item.error = '$e';
    }
  }

  Future<(String, String?, String?)> _createEntityFor(UploadItem item, BulkEntityTarget t) async {
    final dot = item.file.name.lastIndexOf('.');
    final name = dot > 0 ? item.file.name.substring(0, dot) : item.file.name;
    final id = await _repo.save(t.moduleId, null, {'name': name, ...t.extra});
    final record = await _repo.load(t.moduleId, id);
    final module = ref.read(moduleByIdProvider(t.moduleId));
    final folder = record.sourcepath ?? '${module?.name() ?? t.moduleId}/$name';
    return (folder, id, t.moduleId);
  }

  void _refreshAfterBatch() {
    final modules = {for (final i in state) ?i.target.refreshModule};
    for (final m in {...modules, 'asset'}) {
      ref.invalidate(searchResultsProvider(m));
    }
    ref.invalidate(categoryTreeProvider);
  }
}

final uploadQueueProvider = NotifierProvider<UploadQueue, List<UploadItem>>(UploadQueue.new);

/// Default destination for uploads started from [moduleId]'s page.
UploadTarget targetFor(WidgetRef ref, String? moduleId) {
  if (moduleId != null && moduleId != 'asset') {
    final module = ref.read(moduleByIdProvider(moduleId));
    if (module != null && module.isEntity) {
      return BulkEntityTarget(moduleId: moduleId, label: 'New ${module.name()} per file');
    }
  }
  final categoryId = ref.read(moduleViewProvider('asset')).query.categoryId;
  final tree = ref.read(categoryTreeProvider).value;
  final category = categoryId == null ? null : tree?.find(categoryId);
  if (category != null && category.path.isNotEmpty) return FolderTarget(category.path, category.name);
  final user = ref.read(authProvider).value;
  final name = user?.displayName ?? 'uploads';
  return FolderTarget('Users/$name', 'Users / $name');
}

Future<void> pickAndUpload(BuildContext context, WidgetRef ref, UploadTarget target) async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Upload to ${target.label}');
  if (files.isEmpty) return;
  await ref.read(uploadQueueProvider.notifier).add([for (final f in files) f.xFile], target);
}

String uploadSummary(List<UploadItem> items) {
  final active = items.where((i) => !i.finished).length;
  final failed = items.where((i) => i.status == UploadStatus.error).length;
  if (active > 0) {
    final total = items.where((i) => !i.finished).fold<int>(0, (a, i) => a + i.size);
    return 'Uploading $active file${active == 1 ? '' : 's'} · ${formatBytes(total)}';
  }
  if (failed > 0) return '$failed upload${failed == 1 ? '' : 's'} failed';
  return '${items.length} upload${items.length == 1 ? '' : 's'} complete';
}
