import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Отдельная фабрика позволяет проверять настоящую карту с тайлами в памяти.
/// Каждый TileLayer владеет своим provider и освобождает его при закрытии.
final mapTileProviderFactoryProvider = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(),
);
