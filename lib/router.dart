import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/assets/asset_viewer_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/data/module_page.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/home_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) return loc == '/splash' ? null : '/splash';
      final signedIn = auth.value != null;
      if (!signedIn) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/asset/:id',
        pageBuilder: (_, s) => MaterialPage(
          fullscreenDialog: true,
          child: AssetViewerPage(assetId: s.pathParameters['id']!, initialTab: s.uri.queryParameters['tab']),
        ),
      ),
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/m/:module',
            pageBuilder: (_, s) {
              final module = s.pathParameters['module']!;
              return NoTransitionPage(
                key: ValueKey(module),
                child: ModulePage(moduleId: module, openRecordId: s.uri.queryParameters['open']),
              );
            },
          ),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
  );
}
