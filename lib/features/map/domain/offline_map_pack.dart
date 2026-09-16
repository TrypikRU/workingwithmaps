import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Отдельный формат карты. Эти данные никогда не попадают в sync_queue/Drift.
class OfflineMapPack {
  OfflineMapPack(this.tiles, this.attribution);
  static const regionId = 'moscow-pokrovka-v1';
  static const south = 55.752, north = 55.767, west = 37.632, east = 37.655;
  static const minZoom = 13, maxZoom = 16;
  static const maxDownloadBytes = 12 * 1024 * 1024;
  static const maxTileBytes = 256 * 1024;
  static const maxDecodedBytes = 8 * 1024 * 1024;
  final Map<String, Uint8List> tiles;
  final String attribution;
  int get bytes => tiles.values.fold(0, (sum, tile) => sum + tile.length);

  static Set<String> expectedTiles() {
    int x(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
    int y(double lat, int z) {
      final r = lat * math.pi / 180;
      return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
              2 *
              (1 << z))
          .floor();
    }

    return {
      for (var z = minZoom; z <= maxZoom; z++)
        for (var tx = x(west, z); tx <= x(east, z); tx++)
          for (var ty = y(north, z); ty <= y(south, z); ty++) '$z/$tx/$ty',
    };
  }

  static OfflineMapPack parse(List<int> data) {
    if (data.length > maxDownloadBytes) {
      throw const FormatException('Пакет слишком большой');
    }
    final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    if (json['region'] != regionId ||
        json['format'] != 'xyz-png-v1' ||
        json['offlineAllowed'] != true) {
      throw const FormatException('Неверный регион или формат offline-пакета');
    }
    final attribution = json['attribution'];
    if (attribution is! String ||
        attribution.isEmpty ||
        attribution.length > 300) {
      throw const FormatException('В пакете отсутствует атрибуция');
    }
    final encoded = json['tiles'] as Map<String, dynamic>;
    final expected = expectedTiles();
    if (encoded.length != expected.length ||
        !expected.containsAll(encoded.keys)) {
      throw const FormatException(
        'Пакет должен содержать весь фиксированный регион, zoom 13–16',
      );
    }
    var total = 0;
    final tiles = <String, Uint8List>{};
    for (final entry in encoded.entries) {
      final bytes = base64Decode(entry.value as String);
      total += bytes.length;
      if (bytes.length < 24 ||
          bytes.length > maxTileBytes ||
          total > maxDecodedBytes ||
          base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
          ByteData.sublistView(bytes).getUint32(16) != 256 ||
          ByteData.sublistView(bytes).getUint32(20) != 256) {
        throw const FormatException('Ожидаются PNG 256×256 в пределах лимита');
      }
      tiles[entry.key] = bytes;
    }
    return OfflineMapPack(Map.unmodifiable(tiles), attribution);
  }
}
