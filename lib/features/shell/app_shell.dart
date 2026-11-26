import 'package:eme_data_app/core/ph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand.dart';
import '../auth/auth_controller.dart';
import '../upload/upload_panel.dart';
import '../upload/upload_queue.dart';
import '../../core/icons.dart';

class SidebarOpen extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool('sidebar') ?? true;
  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool('sidebar', state);
  }
}

final sidebarOpenProvider = NotifierProvider<SidebarOpen, bool>(
  SidebarOpen.new,
);

String? moduleFromLocation(String location) {
  final m = RegExp(r'^/m/([^/]+)').firstMatch(location);
  return m?.group(1);
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebarOpen = ref.watch(sidebarOpenProvider) && wide;
    final current = moduleFromLocation(location);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            ref.read(sidebarOpenProvider.notifier).toggle(),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            ref.read(sidebarOpenProvider.notifier).toggle(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _GlobalSearchButton._open(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _GlobalSearchButton._open(context, ref),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          drawer: wide
              ? null
              : Drawer(
                  width: 280,
                  child: EntitySidebar(current: current, inDrawer: true),
                ),
          body: Stack(
            children: [
              Row(
                children: [
                  _SideRail(location: location),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: sidebarOpen ? 264 : 0,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 264,
                        maxWidth: 264,
                        child: EntitySidebar(current: current),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(current: current, showMenu: !wide),
                        _EntityTabs(current: current),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
              const Positioned(right: 16, bottom: 16, child: UploadPanel()),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail({required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final module = moduleFromLocation(location);
    final session = ref.watch(authProvider).user;
    final dark = ref.watch(settingsProvider).themeMode == ThemeMode.dark;
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: c.rail,
        border: Border(right: BorderSide(color: c.shellBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(10),
            child: const BrandMark(size: 32, showText: false),
          ),
          const SizedBox(height: 18),
          _RailButton(
            icon: Ph.house,
            activeIcon: PhFill.house,
            label: 'Home',
            active: location == '/',
            onTap: () => context.go('/'),
          ),
          _RailButton(
            icon: Ph.images,
            activeIcon: PhFill.images,
            label: 'Assets',
            active: module == 'asset',
            onTap: () => context.go('/m/asset'),
          ),
          _RailButton(
            icon: Ph.database,
            activeIcon: PhFill.database,
            label: 'Data entities (⌘B)',
            active: module != null && module != 'asset',
            onTap: () => MediaQuery.sizeOf(context).width >= 900
                ? ref.read(sidebarOpenProvider.notifier).toggle()
                : Scaffold.of(context).openDrawer(),
          ),
          _RailButton(
            icon: Ph.cloudArrowUp,
            label: 'Upload',
            onTap: () => pickAndUpload(context, ref, targetFor(ref, module)),
          ),
          const Spacer(),
          _RailButton(
            icon: dark ? Ph.sun : Ph.moonStars,
            label: dark ? 'Light theme' : 'Dark theme',
            onTap: () => ref.read(settingsProvider.notifier).toggleTheme(),
          ),
          const SizedBox(height: 6),
          if (session != null)
            PopupMenuButton<String>(
              tooltip: session.displayName,
              offset: const Offset(56, -80),
              onSelected: (v) {
                if (v == 'logout') ref.read(authProvider.notifier).logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.scheme.onSurface,
                        ),
                      ),
                      Text(
                        '${session.email ?? ''}',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      Text(
                        ref.read(settingsProvider).serverUrl,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Ph.signOut, size: 16),
                      SizedBox(width: 10),
                      Text('Sign out'),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: UserAvatar(
                  name: session.displayName,
                  imageUrl: session.portrait,
                  size: 32,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeIcon,
  });
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Material(
          color: active ? context.colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                active ? (activeIcon ?? icon) : icon,
                size: 20,
                color: active ? s.primary : context.colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Data Entity Manager": every entity module the user can see.
class EntitySidebar extends ConsumerStatefulWidget {
  const EntitySidebar({
    super.key,
    required this.current,
    this.inDrawer = false,
  });
  final String? current;
  final bool inDrawer;

  @override
  ConsumerState<EntitySidebar> createState() => _EntitySidebarState();
}

class _EntitySidebarState extends ConsumerState<EntitySidebar> {
  var _filter = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final modules = ref.watch(entityModulesProvider);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(right: BorderSide(color: c.shellBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    'DATA ENTITIES',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: c.muted,
                    ),
                  ),
                ),
                if (!widget.inDrawer)
                  IconButton(
                    tooltip: 'Collapse (⌘B)',
                    onPressed: () =>
                        ref.read(sidebarOpenProvider.notifier).toggle(),
                    icon: Icon(Ph.sidebarSimple, size: 16, color: c.muted),
                  ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Filter entities',
                prefixIcon: Icon(Ph.magnifyingGlass, size: 14),
                prefixIconConstraints: BoxConstraints(minWidth: 36),
              ),
            ),
          ),
          Expanded(
            child: modules.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e', style: TextStyle(color: c.muted)),
              ),
              data: (list) {
                final items = list
                    .where(
                      (m) =>
                          _filter.isEmpty ||
                          m.name().toLowerCase().contains(_filter),
                    )
                    .toList();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _SidebarItem(
                    module: items[i],
                    active: items[i].id == widget.current,
                    onTap: () {
                      if (widget.inDrawer) Navigator.of(context).pop();
                      context.go('/m/${items[i].id}');
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.module,
    required this.active,
    required this.onTap,
  });
  final ModuleInfo module;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final c = context.colors;
    final active = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? c.accentSoft
                : (_hover ? c.subtle : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                moduleIcon(widget.module, filled: active),
                size: 15,
                color: active ? s.primary : c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.module.name(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? s.primary : s.onSurface,
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

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.current, required this.showMenu});
  final String? current;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final module = current == null
        ? null
        : ref.watch(moduleByIdProvider(current!));
    final title =
        module?.name() ??
        (current == 'asset' ? 'Assets' : (current == null ? 'Home' : current!));
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.shell,
        border: Border(bottom: BorderSide(color: c.shellBorder)),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (context) => IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Ph.list, size: 18),
              ),
            ),
          if (module != null) ...[
            Icon(
              moduleIcon(module, filled: true, fallback: PhFill.images),
              size: 17,
              color: context.scheme.primary,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const _GlobalSearchButton(),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () =>
                pickAndUpload(context, ref, targetFor(ref, current)),
            icon: const Icon(Ph.cloudArrowUp, size: 15),
            label: const Text('Upload'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalSearchButton extends ConsumerWidget {
  const _GlobalSearchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    if (MediaQuery.sizeOf(context).width < 700) {
      return IconButton(
        onPressed: () => _open(context, ref),
        icon: const Icon(Ph.magnifyingGlass, size: 16),
      );
    }
    return InkWell(
      onTap: () => _open(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Ph.magnifyingGlass, size: 13, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search assets…',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: context.scheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('⌘K', style: TextStyle(fontSize: 11, color: c.muted)),
            ),
          ],
        ),
      ),
    );
  }

  static void _open(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _QuickSearchDialog(
        onSubmit: (text) {
          Navigator.pop(dialogContext);
          ref.read(moduleViewProvider('asset').notifier).setText(text);
          context.go('/m/asset');
        },
      ),
    );
  }
}

class _QuickSearchDialog extends StatelessWidget {
  const _QuickSearchDialog({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            onSubmitted: onSubmit,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Search all assets — press Enter',
              prefixIcon: Icon(Ph.magnifyingGlass, size: 16),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
      ),
    );
  }
}

/// Top menu: the `appsection` entries, rendered as pills.
class _EntityTabs extends ConsumerWidget {
  const _EntityTabs({required this.current});
  final String? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(appSectionsProvider).value ?? const [];
    if (sections.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: c.shell,
        border: Border(bottom: BorderSide(color: c.shellBorder)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final s in sections)
            _EntityPill(section: s, active: s.moduleId == current),
        ],
      ),
    );
  }
}

class _EntityPill extends ConsumerWidget {
  const _EntityPill({required this.section, required this.active});
  final AppSection section;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.scheme;
    final module = ref.watch(moduleByIdProvider(section.moduleId));
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? s.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go('/m/${section.moduleId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  moduleIcon(module, filled: active),
                  size: 14,
                  color: active ? s.onPrimary : context.colors.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  section.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? s.onPrimary : s.onSurface,
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
