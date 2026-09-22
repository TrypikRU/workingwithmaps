import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/features/map/data/map_tile_provider.dart';
import 'package:workingwithmaps/features/map/data/offline_map_repository.dart';
import 'package:workingwithmaps/features/map/domain/offline_map_pack.dart';
import 'package:workingwithmaps/features/objects/data/demo_objects.dart';

class PackTransport implements HttpClientAdapter {
  List<int> data = [];
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromBytes(
      data,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class CountingOnline extends TileProvider {
  CountingOnline(this.bytes);
  final Uint8List bytes;
  int requests = 0;
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return MemoryImage(bytes);
  }
}

void main() {
  final png = File('test/fixtures/offline_tile.png').readAsBytesSync();
  Map<String, dynamic> manifest() => {
    'format': 'xyz-png-v1',
    'region': OfflineMapPack.regionId,
    'offlineAllowed': true,
    'attribution': 'Test fixture only',
    'tiles': {
      for (final key in OfflineMapPack.expectedTiles()) key: base64Encode(png),
    },
  };

  test(
    'Railway offline region includes the demo objects and rejects old packs',
    () {
      for (final object in demoObjects) {
        expect(
          object.latitude,
          inInclusiveRange(OfflineMapPack.south, OfflineMapPack.north),
        );
        expect(
          object.longitude,
          inInclusiveRange(OfflineMapPack.west, OfflineMapPack.east),
        );
        for (final point in object.polygon) {
          expect(
            point.latitude,
            inInclusiveRange(OfflineMapPack.south, OfflineMapPack.north),
          );
          expect(
            point.longitude,
            inInclusiveRange(OfflineMapPack.west, OfflineMapPack.east),
          );
        }
      }
      final old = manifest()..['region'] = 'moscow-pokrovka-v1';
      expect(
        () => OfflineMapPack.parse(utf8.encode(jsonEncode(old))),
        throwsFormatException,
      );
    },
  );

  test(
    'Only complete fixed-region pack with bounded PNG tiles is accepted',
    () {
      final json = manifest();
      expect(
        OfflineMapPack.parse(utf8.encode(jsonEncode(json))).tiles,
        hasLength(40),
      );
      (json['tiles'] as Map).remove((json['tiles'] as Map).keys.first);
      expect(
        () => OfflineMapPack.parse(utf8.encode(jsonEncode(json))),
        throwsFormatException,
      );
      expect(
        () => OfflineMapPack.parse(
          Uint8List(OfflineMapPack.maxDownloadBytes + 1),
        ),
        throwsFormatException,
      );
      final other = manifest()..['offlineAllowed'] = false;
      expect(
        () => OfflineMapPack.parse(utf8.encode(jsonEncode(other))),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'Atomic install, replacement, restart, offline reads and online fallback',
    (tester) async {
      await tester.runAsync(() async {
        final folder = await Directory.systemTemp.createTemp(
          'field-offline-map-',
        );
        final transport = PackTransport()
          ..data = utf8.encode(jsonEncode(manifest()));
        final dio = Dio()..httpClientAdapter = transport;
        try {
          final repo = OfflineMapRepository(
            dio: dio,
            directory: () async => folder,
          );
          await repo.load();
          expect(repo.pack, isNull);
          final url = Uri.parse('http://127.0.0.1:8090/field-region.json');
          final first = repo.download(url, (_) {});
          final joined = repo.download(url, (_) {});
          await Future.wait([first, joined]);
          expect(transport.requests, 1);
          expect(repo.pack!.tiles, hasLength(40));
          final installed = repo.pack;
          transport.data = utf8.encode('{}');
          await expectLater(repo.download(url, (_) {}), throwsA(anything));
          expect(repo.pack, same(installed));
          final restarted = OfflineMapRepository(
            dio: dio,
            directory: () async => folder,
          );
          await restarted.load();
          expect(restarted.pack!.tiles, hasLength(40));
          // Existing package can be replaced on Windows without deleting it first.
          transport.data = utf8.encode(jsonEncode(manifest()));
          await restarted.download(url, (_) {});
          final online = CountingOnline(png);
          final provider = OfflineFirstTileProvider(restarted, online: online);
          final xyz = restarted.pack!.tiles.keys.first
              .split('/')
              .map(int.parse)
              .toList();
          final options = TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          );
          final image = provider.getImageWithCancelLoadingSupport(
            TileCoordinates(xyz[1], xyz[2], xyz[0]),
            options,
            Future.value(),
          );
          expect(image, isA<MemoryImage>());
          expect(online.requests, 0);
          provider.getImageWithCancelLoadingSupport(
            const TileCoordinates(0, 0, 3),
            options,
            Future.value(),
          );
          expect(online.requests, 1);
          restarted.offlineOnly = true;
          provider.getImageWithCancelLoadingSupport(
            const TileCoordinates(0, 0, 3),
            options,
            Future.value(),
          );
          expect(
            online.requests,
            1,
          ); // Missing tile must not contact network in forced offline mode.
          final count = transport.requests;
          await expectLater(
            repo.download(
              Uri.parse('https://tile.openstreetmap.org/pack.json'),
              (_) {},
            ),
            throwsFormatException,
          );
          expect(transport.requests, count);
          provider.dispose();
        } finally {
          dio.close(force: true);
          await folder.delete(recursive: true);
        }
      });
    },
  );
}
