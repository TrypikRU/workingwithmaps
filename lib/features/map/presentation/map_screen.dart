import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/feature_placeholder.dart';
import '../../../core/location/location_controller.dart';
import '../../objects/presentation/objects_providers.dart';
import '../../objects/presentation/objects_refresh_button.dart';
import '../data/map_tile_provider.dart';
import 'map_focus_provider.dart';
import 'objects_map.dart';
import 'location_status_panel.dart';
import '../../tracking/presentation/tracking_controller.dart';
import '../../../core/geometry/circular_geofence.dart';
import 'geofence_providers.dart';
import 'offline_map_controller.dart';
import 'offline_map_dialog.dart';

class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final objects = ref.watch(objectsProvider);
    final focus = ref.watch(mapFocusProvider);
    final location = ref.watch(locationControllerProvider);
    final offline = ref.watch(offlineMapControllerProvider);
    final route = ref.watch(currentRouteProvider).asData?.value;
    final zones = ref.watch(objectGeofencesProvider);
    final nearby = objects.asData?.value
        .where((o) => zones[o.id] == GeofenceState.approaching)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
          IconButton(
            tooltip: 'Offline-карта',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const OfflineMapDialog(),
            ),
          ),
          const ObjectsRefreshButton(),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const LocationStatusPanel(),
            if (offline.hasPack || offline.offlineOnly)
              Text(
                offline.offlineOnly ? 'Только offline · Покровка · zoom 13–16' : 'Offline-регион сохранён · вне покрытия используется сеть',
              ),
            if (nearby != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Вы находитесь рядом с объектом: ${nearby.name}',
                  key: const ValueKey('approaching-object'),
                ),
              ),
            Expanded(
              child: objects.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => const FeaturePlaceholder(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить объекты',
                  message: 'Попробуйте открыть карту ещё раз.',
                ),
                data: (items) => Column(
                  children: [
                    if (items.isEmpty) const Text('Нет объектов на карте'),
                    Expanded(
                      child: ObjectsMap(
                        focusRevision: focus.revision,
                        tileRevision: offline.revision,
                        offlineTilesAvailable: offline.hasPack,
                        tileAttribution: offline.attribution,
                        objects: items,
                        focusObjectId: focus.objectId,
                        location: location,
                        track: route?.points ?? const [],
                        createTileProvider: ref.watch(
                          mapTileProviderFactoryProvider,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
