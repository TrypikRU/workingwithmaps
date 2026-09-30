import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/map/presentation/map_screen.dart';
import '../../features/objects/presentation/objects_screen.dart';
import '../../features/objects/presentation/object_details_screen.dart';
import '../../features/route/presentation/current_route_screen.dart';
import '../../features/sync/presentation/sync_screen.dart';
import 'navigation_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/map',
    routes: [
      // У каждой вкладки свой Navigator: переходы сохраняют её стек и состояние.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppNavigationShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                name: 'map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/objects',
                builder: (context, state) => const ObjectsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/route',
                builder: (context, state) => const CurrentRouteScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sync',
                builder: (context, state) => const SyncScreen(),
              ),
            ],
          ),
        ],
      ),
      // Детали поверх оболочки: кнопка «Назад» возвращает к исходной вкладке и её камере.
      GoRoute(
        path: '/objects/:objectId',
        name: 'object-details',
        builder: (context, state) =>
            ObjectDetailsScreen(objectId: state.pathParameters['objectId']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
