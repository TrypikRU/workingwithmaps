import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/offline_map_pack.dart';

/// Один ограниченный пакет в application support, отдельно от бизнес-БД и
/// обычного HTTP cache flutter_map. Не содержит downloader для OSM XYZ endpoint.
class OfflineMapRepository {
  OfflineMapRepository({
    required this.dio,
    Future<Directory> Function()? directory,
  }) : directory =
           directory ??
           (() async => Directory(
             '${(await getApplicationSupportDirectory()).path}/offline_maps',
           ));
  final Dio dio;
  final Future<Directory> Function() directory;
  OfflineMapPack? pack;
  bool offlineOnly = false;
  Future<void>? _installing;

  Future<void> load() async {
    final root = await directory();
    final file = File('${root.path}/region.json');
    if (!await file.exists()) return;
    if (await file.length() > OfflineMapPack.maxDownloadBytes) {
      throw const FormatException('Слишком большой локальный пакет');
    }
    final candidate = OfflineMapPack.parse(await file.readAsBytes());
    await _validateImages(candidate);
    pack = candidate;
  }

  Future<void> download(Uri url, void Function(int) progress) {
    // Повторное нажатие присоединяется к загрузке, не создавая гонку файлов.
    return _installing ??= _download(
      url,
      progress,
    ).whenComplete(() => _installing = null);
  }

  Future<void> _download(Uri url, void Function(int) progress) async {
    final token = CancelToken();
    final timer = Timer(
      const Duration(minutes: 2),
      () => token.cancel('Download deadline'),
    );
    try {
      await _fetchAndInstall(url, progress, token);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _fetchAndInstall(
    Uri url,
    void Function(int) progress,
    CancelToken token,
  ) async {
    if (!['http', 'https'].contains(url.scheme) ||
        !url.hasAuthority ||
        url.host == 'openstreetmap.org' ||
        url.host.endsWith('.openstreetmap.org') ||
        url.hasQuery) {
      throw const FormatException(
        'Нужен URL готового пакета с разрешённого собственного сервера',
      );
    }
    final response = await dio.get<ResponseBody>(
      url.toString(),
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: false,
      ),
    );
    final body = response.data!;
    final bytes = BytesBuilder(copy: false);
    // Проверяем фактический поток, а не только Content-Length. Ошибка/обрыв
    // никогда не заменяют рабочую карту частично скачанными данными.
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > OfflineMapPack.maxDownloadBytes) {
        throw const FormatException('Превышен лимит пакета 12 MiB');
      }
      bytes.add(chunk);
      progress(bytes.length);
    }
    final data = bytes.takeBytes();
    final candidate = OfflineMapPack.parse(data);
    await _validateImages(candidate);
    final root = await directory();
    await root.create(recursive: true);
    final temporary = File('${root.path}/region.json.tmp');
    await temporary.writeAsBytes(data, flush: true);
    await temporary.rename('${root.path}/region.json');
    pack = candidate;
  }

  Future<void> _validateImages(OfflineMapPack candidate) async {
    // Header недостаточен: проверяем реальные PNG до публикации всего пакета.
    // Декодируем последовательно и освобождаем изображения, ограничивая память.
    for (final bytes in candidate.tiles.values) {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          if (frame.image.width != 256 ||
              frame.image.height != 256 ||
              codec.frameCount != 1) {
            throw const FormatException(
              'Неверный размер или анимированный тайл',
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  }
}
