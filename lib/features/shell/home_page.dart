import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../data/module_page.dart';
import '../data/views/grid_view.dart';
import '../upload/upload_panel.dart';
import '../upload/upload_queue.dart';
import '../../core/icons.dart';

const _recentQuery = SearchQuery(
  hitsPerPage: 12,
  sortField: 'assetaddeddate',
  sortAscending: false,
);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).user;
    final sections = ref.watch(appSectionsProvider).value ?? const [];
    final recent = ref.watch(
      adhocSearchProvider((module: 'asset', query: _recentQuery)),
    );
    final c = context.colors;

    return UploadDropZone(
      target: targetFor(ref, 'asset'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        children: [
          Text(
            'Welcome back${session == null ? '' : ', ${session.displayName}'}',
            style: context.text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Browse your entities, or drop files anywhere on this page to upload them.',
            style: TextStyle(color: c.muted),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _Tile(
                icon: Ph.images,
                title: 'Assets',
                moduleId: 'asset',
                onTap: () => context.go('/m/asset'),
              ),
              for (final s in sections)
                _Tile(
                  icon: moduleIcon(
                    ref.watch(moduleByIdProvider(s.moduleId)),
                    filled: true,
                  ),
                  title: s.name,
                  moduleId: s.moduleId,
                  onTap: () => context.go('/m/${s.moduleId}'),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Text(
                'Recently added',
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/m/asset'),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          recent.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('$e', style: TextStyle(color: c.muted)),
            data: (r) => r.hits.isEmpty
                ? Text('No assets yet.', style: TextStyle(color: c.muted))
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
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
                      onOpen: () => openRecord(
                        context,
                        ref,
                        'asset',
                        r.hits[i],
                        siblings: r.hits,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.moduleId,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String moduleId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref
        .watch(
          adhocSearchProvider((
            module: moduleId,
            query: const SearchQuery(hitsPerPage: 1),
          )),
        )
        .value
        ?.total;
    final s = context.scheme;
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: s.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        count == null
                            ? ' '
                            : '$count ${count == 1 ? 'item' : 'items'}',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
