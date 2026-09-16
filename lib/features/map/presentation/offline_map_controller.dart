import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/offline_map_providers.dart';

class OfflineMapState {
  const OfflineMapState({
    this.busy = false,
    this.received = 0,
    this.revision = 0,
    this.hasPack = false,
    this.offlineOnly = false,
    this.attribution = '',
    this.error,
  });
  final bool busy, hasPack, offlineOnly;
  final int received, revision;
  final String attribution;
  final String? error;
}

final offlineMapControllerProvider =
    NotifierProvider<OfflineMapController, OfflineMapState>(
      OfflineMapController.new,
    );

class OfflineMapController extends Notifier<OfflineMapState> {
  @override
  OfflineMapState build() {
    Future<void>.microtask(load);
    return const OfflineMapState(busy: true);
  }

  void publish({String? error}) {
    if (!ref.mounted) return;
    final repo = ref.read(offlineMapRepositoryProvider);
    state = OfflineMapState(
      hasPack: repo.pack != null,
      offlineOnly: repo.offlineOnly,
      attribution: repo.pack?.attribution ?? '',
      revision: state.revision + 1,
      error: error,
    );
  }

  Future<void> load() async {
    try {
      await ref.read(offlineMapRepositoryProvider).load();
      publish();
    } catch (_) {
      publish(
        error: 'Не удалось открыть offline-пакет. Можно скачать его заново.',
      );
    }
  }

  Future<void> download() async {
    if (state.busy) return;
    state = OfflineMapState(
      busy: true,
      hasPack: state.hasPack,
      offlineOnly: state.offlineOnly,
      revision: state.revision,
      attribution: state.attribution,
    );
    try {
      const url = String.fromEnvironment(
        'OFFLINE_MAP_PACK_URL',
        defaultValue: 'http://10.0.2.2:8090/field-region.json',
      );
      await ref.read(offlineMapRepositoryProvider).download(Uri.parse(url), (
        received,
      ) {
        if (!ref.mounted) return;
        state = OfflineMapState(
          busy: true,
          received: received,
          hasPack: state.hasPack,
          offlineOnly: state.offlineOnly,
          revision: state.revision,
          attribution: state.attribution,
        );
      });
      publish();
    } catch (_) {
      publish(
        error:
            'Пакет не установлен. Проверьте сервер, формат и разрешение на offline-использование. Прежняя карта сохранена.',
      );
    }
  }

  void setOfflineOnly(bool value) {
    ref.read(offlineMapRepositoryProvider).offlineOnly = value;
    publish();
  }

  void refreshTiles() => publish();
}
