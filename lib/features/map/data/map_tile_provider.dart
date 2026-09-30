import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_map_providers.dart';
import 'offline_map_repository.dart';

/// Хранилище тайлов не связано с бизнес-БД и SyncEngine. Приоритет локальных данных
/// означает чтение сохранённого тайла с переходом к сети при его отсутствии.
class OfflineFirstTileProvider extends TileProvider {
  OfflineFirstTileProvider(this.repository, {TileProvider? online})
    : online =
          online ??
          NetworkTileProvider(
            silenceExceptions: true,
            headers: {'User-Agent': 'com.klochkov.workingwithmaps'},
          );
  final OfflineMapRepository repository;
  final TileProvider online;
  static final emptyTile = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    ),
  );
  @override
  bool get supportsCancelLoading => true;
  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final bytes = repository
        .pack
        ?.tiles['${coordinates.z}/${coordinates.x}/${coordinates.y}'];
    if (bytes != null) return MemoryImage(bytes);
    if (repository.offlineOnly) return emptyTile;
    return online.supportsCancelLoading
        ? online.getImageWithCancelLoadingSupport(
            coordinates,
            options,
            cancelLoading,
          )
        : online.getImage(coordinates, options);
  }

  @override
  void dispose() => online.dispose();
}

final mapTileProviderFactoryProvider = Provider<TileProvider Function()>((ref) {
  final repository = ref.watch(offlineMapRepositoryProvider);
  return () => OfflineFirstTileProvider(repository);
});
