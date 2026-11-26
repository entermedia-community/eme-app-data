import 'dart:math';

import 'package:eme_data_app/core/ph.dart';
import 'package:eme_app_sdk/eme_app_sdk.dart' show FieldValueView;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/values.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/asset_preview.dart';
import '../../../widgets/common.dart';
import '../columns.dart';
import '../module_page.dart';

class ResultsTable extends ConsumerWidget {
  const ResultsTable({super.key, required this.moduleId, required this.result});
  final String moduleId;
  final SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(moduleViewProvider(moduleId));
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    final fields = ref.watch(fieldsProvider(moduleId)).value ?? const [];
    final all = columnsFor(moduleId, fields, result.hits);
    final hidden = view.hiddenColumns ?? defaultHidden(moduleId, all);
    final cols = all.where((c) => !hidden.contains(c.id)).toList();
    final ids = {for (final h in result.hits) h.id};
    final allSelected = ids.isNotEmpty && ids.every(view.selected.contains);

    return LayoutBuilder(
      builder: (context, box) {
        const checkW = 48.0;
        const actionW = 52.0;
        final totalFlex = cols.fold<int>(0, (a, c) => a + c.flex);
        final free = box.maxWidth - checkW - actionW;
        final widths = [
          for (final c in cols) max(c.minWidth, free * c.flex / totalFlex),
        ];
        final tableW =
            checkW + actionW + widths.fold<double>(0, (a, w) => a + w);

        final table = SizedBox(
          width: max(tableW, box.maxWidth),
          child: Column(
            children: [
              _HeaderRow(
                cols: cols,
                widths: widths,
                query: view.query,
                allSelected: allSelected,
                onSelectAll: () => ctrl.setSelected(allSelected ? {} : ids),
                onSort: ctrl.sortBy,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: result.hits.length,
                  itemExtent: 76,
                  itemBuilder: (_, i) => _Row(
                    moduleId: moduleId,
                    record: result.hits[i],
                    cols: cols,
                    widths: widths,
                    selected: view.selected.contains(result.hits[i].id),
                    onSelect: () => ctrl.toggleSelected(result.hits[i].id),
                    onOpen: () => openRecord(
                      context,
                      ref,
                      moduleId,
                      result.hits[i],
                      siblings: result.hits,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        if (tableW <= box.maxWidth) return table;
        return _HScroll(child: table);
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.cols,
    required this.widths,
    required this.query,
    required this.allSelected,
    required this.onSelectAll,
    required this.onSort,
  });

  final List<ColumnDef> cols;
  final List<double> widths;
  final dynamic query;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: context.scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: allSelected,
              onChanged: (_) => onSelectAll(),
            ),
          ),
          for (var i = 0; i < cols.length; i++)
            SizedBox(
              width: widths[i],
              child: InkWell(
                onTap: cols[i].sortable ? () => onSort(cols[i].id) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          cols[i].label.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: c.muted,
                          ),
                        ),
                      ),
                      if (query.sortField == cols[i].id) ...[
                        const SizedBox(width: 4),
                        Icon(
                          query.sortAscending
                              ? PhFill.caretUp
                              : PhFill.caretDown,
                          size: 10,
                          color: context.scheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.moduleId,
    required this.record,
    required this.cols,
    required this.widths,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final String moduleId;
  final Json record;
  final List<ColumnDef> cols;
  final List<double> widths;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final c = context.colors;
    final isAsset = widget.moduleId == 'asset';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          decoration: BoxDecoration(
            color: widget.selected
                ? c.accentSoft
                : (_hover ? c.subtle : Colors.transparent),
            border: Border(bottom: BorderSide(color: s.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onSelect(),
                ),
              ),
              for (var i = 0; i < widget.cols.length; i++)
                SizedBox(
                  width: widget.widths[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: _cell(context, widget.cols[i], isAsset),
                  ),
                ),
              SizedBox(
                width: 52,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 100),
                  child: IconButton(
                    tooltip: 'Open',
                    onPressed: widget.onOpen,
                    icon: Icon(Ph.arrowSquareOut, size: 15, color: c.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ColumnDef col, bool isAsset) {
    final r = widget.record;
    switch (col.kind) {
      case ColumnKind.thumb:
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 84,
            height: 56,
            child: AssetThumb(
              sourcepath: thumbSourcepath(r, isAsset: isAsset),
              fallbackIcon: isAsset ? iconForAsset(r) : Ph.userSquare,
              radius: 6,
            ),
          ),
        );
      case _ when col.field != null && col.kind != ColumnKind.thumb:
        final f = col.field!;
        return Align(
          alignment: Alignment.centerLeft,
          child: FieldValueView(
            fieldId: f.id,
            value: r[col.id],
            datatype: f.datatype,
            rendertype: f.rendertype,
            assetBuilder: (_, id) => AssetPreview(assetId: id),
          ),
        );
      case ColumnKind.chips:
        final values = r[col.id] is List
            ? (r[col.id] as List)
            : (r[col.id] == null ? const [] : [r[col.id]]);
        if (values.isEmpty) return const SizedBox.shrink();
        return ClipRect(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final v in values.take(4))
                Pill(displayValue(v), color: context.scheme.secondary),
              if (values.length > 4)
                Pill('+${values.length - 4}', color: context.colors.muted),
            ],
          ),
        );
      default:
        final text = col.format(r);
        final primary = col.id == 'assettitle' || col.id == 'name';
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
              color: primary
                  ? context.scheme.onSurface
                  : context.scheme.onSurfaceVariant,
            ),
          ),
        );
    }
  }
}

/// Horizontal scroller whose bar is always visible and can be dragged with the mouse.
class _HScroll extends StatefulWidget {
  const _HScroll({required this.child});
  final Widget child;

  @override
  State<_HScroll> createState() => _HScrollState();
}

class _HScrollState extends State<_HScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        // Leaves room so the bar does not cover the last row.
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.child,
      ),
    );
  }
}
