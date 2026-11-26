import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/values.dart';
import '../../../data/models.dart';
import '../../../data/providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../module_page.dart';
import '../../../core/icons.dart';

class ResultsGrid extends ConsumerWidget {
  const ResultsGrid({super.key, required this.moduleId, required this.result});
  final String moduleId;
  final SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      moduleViewProvider(moduleId).select((s) => s.selected),
    );
    final ctrl = ref.read(moduleViewProvider(moduleId).notifier);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: result.hits.length,
      itemBuilder: (_, i) {
        final r = result.hits[i];
        return GridCard(
          moduleId: moduleId,
          record: r,
          selected: selected.contains(r.id),
          onSelect: () => ctrl.toggleSelected(r.id),
          onOpen: () =>
              openRecord(context, ref, moduleId, r, siblings: result.hits),
        );
      },
    );
  }
}

class GridCard extends ConsumerStatefulWidget {
  const GridCard({
    super.key,
    required this.moduleId,
    required this.record,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
  });

  final String moduleId;
  final Json record;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  ConsumerState<GridCard> createState() => _GridCardState();
}

class _GridCardState extends ConsumerState<GridCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final c = context.colors;
    final r = widget.record;
    final isAsset = widget.moduleId == 'asset';
    final module = ref.watch(moduleByIdProvider(widget.moduleId));
    final subtitle = isAsset
        ? [
            displayValue(r['fileformat']),
            formatBytes(r['filesize']),
          ].where((x) => x.isNotEmpty).join(' · ')
        : displayValue(r['entity_date']).isNotEmpty
        ? displayValue(r['entity_date'])
        : displayValue(r['owner']);
    final highlight = widget.selected || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: s.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? s.primary
                  : (highlight ? s.outline : s.outlineVariant),
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AssetThumb(
                        sourcepath: thumbSourcepath(r, isAsset: isAsset),
                        preset: Preset.medium,
                        fallbackIcon: isAsset
                            ? iconForAsset(r)
                            : moduleIcon(
                                module,
                                filled: true,
                                fallback: PhFill.userCircle,
                              ),
                        background: isAsset ? null : const Color(0xFF55658F),
                      ),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: AnimatedOpacity(
                          opacity: highlight ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            decoration: BoxDecoration(
                              color: s.surface.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SizedBox.square(
                              dimension: 26,
                              child: Checkbox(
                                value: widget.selected,
                                onChanged: (_) => widget.onSelect(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isAsset)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              iconForAsset(r),
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty ? ' ' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
