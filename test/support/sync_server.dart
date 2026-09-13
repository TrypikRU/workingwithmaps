import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:workingwithmaps/core/database/app_database.dart';

/// Mimics the API's durable entity-id/payload deduplication, including lost ACK.
/// Actual Dio serialization and validation run above this transport fake.
class SyncServer implements HttpClientAdapter {
  final records = <String, Map<String, dynamic>>{};
  final requests = <Map<String, dynamic>>[];
  final keys = <String>[];
  final responses = <int>[];
  DioExceptionType? failure;
  bool loseNextAck = false;
  Completer<void>? hold;
  int applied = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    active++;
    if (active > maxActive) maxActive = active;
    try {
      final data = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
      requests.add(data);
      keys.add(options.headers['Idempotency-Key'] as String);
      if (hold != null) await hold!.future;
      if (failure != null) {
        throw DioException(requestOptions: options, type: failure!);
      }
      final status = responses.isEmpty ? 200 : responses.removeAt(0);
      if (status != 200) return jsonResponse({'title': 'debug'}, status);
      final point = options.uri.path == '/location/batch';
      final payload = point
          ? (data['points'] as List).single as Map<String, dynamic>
          : data;
      final id = payload['id'] as String;
      final existing = records[id];
      final business = Map<String, dynamic>.of(payload)
        ..remove('serverVersion');
      if (existing == null ||
          jsonEncode(existing['business']) != jsonEncode(business)) {
        if (existing != null &&
            (point || payload['serverVersion'] != existing['version'])) {
          return jsonResponse({}, 409);
        }
        applied++;
        records[id] = {
          'business': business,
          'version': (existing?['version'] as int? ?? 0) + 1,
        };
      }
      if (loseNextAck) {
        loseNextAck = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
      final ack = {...payload, 'serverVersion': records[id]!['version']};
      return jsonResponse(
        point
            ? {
                'accepted': [ack],
              }
            : ack,
        200,
      );
    } finally {
      active--;
    }
  }

  ResponseBody jsonResponse(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

Future<void> enqueue(AppDatabase db, String id) => db.transaction(() async {
  await db
      .into(db.visits)
      .insert(
        VisitsCompanion.insert(
          id: id,
          objectId: 'demo-1',
          latitude: 55.7586,
          longitude: 37.6442,
          accuracy: 8,
        ),
      );
  await db
      .into(db.syncQueue)
      .insert(
        SyncQueueCompanion.insert(
          entityType: 'visit',
          entityId: id,
          operation: 'upsert',
        ),
      );
});
