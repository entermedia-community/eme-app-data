import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/app_theme.dart';

/// Right-hand "Summary": result counts plus facet filters.
class SummaryPanel extends ConsumerWidget {
  const SummaryPanel({super.key, required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final result = ref.watch(searchResultsProvider(moduleId)).value;
    final query = ref.watch(
      moduleViewProvider(moduleId).select((s) => s.query),
    );
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    final tree = ref.watch(categoryTreeProvider).value;
    final folder = query.categoryId == null
        ? null
        : tree?.find(query.categoryId!);

    final start = result == null || result.total == 0
        ? 0
        : (result.page - 1) * query.hitsPerPage + 1;
    final end = result == null
        ? 0
        : (start + result.hits.length - 1).clamp(0, result.total);

    // Keep selected options visible even when the current results no longer contain them.
    final facets = result?.facets ?? const <Facet>[];

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(left: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text(
            'SUMMARY',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 14),
          _Stat(label: 'Results', value: '${result?.total ?? '–'}'),
          _Stat(
            label: 'Showing',
            value: result == null ? '–' : '$start – $end',
          ),
          _Stat(
            label: 'Sorted by',
            value: query.sortField == null
                ? 'Default'
                : '${query.sortField} ${query.sortAscending ? '↑' : '↓'}',
          ),
          if (moduleId == 'asset')
            _Stat(
              label: 'Folder',
              value: folder?.path.isNotEmpty == true ? folder!.path : 'All',
            ),
          if (query.activeFilterCount > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: ctrl.clearFilters,
                icon: const Icon(Ph.xCircle, size: 13),
                label: Text(
                  'Clear ${query.activeFilterCount} filter${query.activeFilterCount == 1 ? '' : 's'}',
                ),
              ),
            ),
          ],
          for (final f in facets)
            _FacetGroup(
              facet: f,
              selected: query.filters[f.id] ?? const {},
              onToggle: (v) => ctrl.toggleFilter(f.id, v),
            ),
          if (result != null && facets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                'No filters for this list.',
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _FacetGroup extends StatefulWidget {
  const _FacetGroup({
    required this.facet,
    required this.selected,
    required this.onToggle,
  });
  final Facet facet;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  State<_FacetGroup> createState() => _FacetGroupState();
}

class _FacetGroupState extends State<_FacetGroup> {
  var _open = true;
  var _showAll = false;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final options = widget.facet.options;
    final visible = _showAll ? options : options.take(8).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.facet.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(
                  _open ? Ph.caretUp : Ph.caretDown,
                  size: 11,
                  color: context.colors.muted,
                ),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            for (final o in visible)
              InkWell(
                onTap: () => widget.onToggle(o.id),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: Checkbox(
                          value: widget.selected.contains(o.id),
                          onChanged: (_) => widget.onToggle(o.id),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          o.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: s.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${o.count}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (options.length > 8)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll ? 'Show less' : 'Show all ${options.length}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
