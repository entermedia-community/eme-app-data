import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/app_theme.dart';

/// Category tree for assets, with a quick filter that searches every folder path.
class FoldersPanel extends ConsumerStatefulWidget {
  const FoldersPanel({super.key});

  @override
  ConsumerState<FoldersPanel> createState() => _FoldersPanelState();
}

class _FoldersPanelState extends ConsumerState<FoldersPanel> {
  final _expanded = <String>{'index'};
  var _filter = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tree = ref.watch(categoryTreeProvider);
    final selected =
        ref.watch(
          moduleViewProvider('asset').select((s) => s.query.categoryId),
        ) ??
        'index';
    final select = ref.read(moduleViewProvider('asset').notifier).setCategory;

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(right: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Text(
              'FOLDERS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: c.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _filter = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search folders',
                prefixIcon: Icon(Ph.magnifyingGlass, size: 13),
                prefixIconConstraints: BoxConstraints(minWidth: 34),
              ),
            ),
          ),
          Expanded(
            child: tree.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e', style: TextStyle(color: c.muted)),
              ),
              data: (root) {
                if (_filter.isNotEmpty) {
                  final matches = root
                      .flatten()
                      .where((n) => n.path.toLowerCase().contains(_filter))
                      .toList();
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final n in matches)
                        _FolderRow(
                          label: n.path,
                          depth: 0,
                          selected: n.id == selected,
                          onTap: () => select(n.id),
                        ),
                    ],
                  );
                }
                final rows = <Widget>[];
                void walk(CategoryNode n, int depth) {
                  final open = _expanded.contains(n.id);
                  rows.add(
                    _FolderRow(
                      label: depth == 0 ? 'All' : n.name,
                      depth: depth,
                      selected: n.id == selected,
                      hasChildren: n.children.isNotEmpty,
                      expanded: open,
                      onToggle: () => setState(
                        () =>
                            open ? _expanded.remove(n.id) : _expanded.add(n.id),
                      ),
                      onTap: () => select(n.id),
                    ),
                  );
                  if (open) {
                    for (final child in n.children) {
                      walk(child, depth + 1);
                    }
                  }
                }

                walk(root, 0);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  children: rows,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.hasChildren = false,
    this.expanded = false,
    this.onToggle,
  });

  final String label;
  final int depth;
  final bool selected;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final c = context.colors;
    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        onDoubleTap: onToggle,
        child: Padding(
          padding: EdgeInsets.only(
            left: 4.0 + depth * 14,
            right: 8,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: hasChildren
                    ? InkWell(
                        onTap: onToggle,
                        child: Icon(
                          expanded ? Ph.caretDown : Ph.caretRight,
                          size: 11,
                          color: c.muted,
                        ),
                      )
                    : null,
              ),
              Icon(
                selected || expanded ? Ph.folderOpen : Ph.folder,
                size: 14,
                color: selected ? s.primary : const Color(0xFFF2B53A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? s.primary : s.onSurface,
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
