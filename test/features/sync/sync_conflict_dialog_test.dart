import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/core/sync/sync_conflict.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_snapshot.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/sync/presentation/sync_conflicts_panel.dart';
import '../../support/test_database.dart';
import '../../support/sync_server.dart';

void main() {
  testWidgets(
    'Conflict stream opens versions; explicit local resolution enqueues without UI HTTP',
    (tester) async {
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      final server = SyncServer();
      final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
        ..httpClientAdapter = server;
      addTearDown(() => dio.close(force: true));
      const object = TechnicalObject(
        id: 'edit',
        name: 'Local',
        address: 'Address',
        latitude: 55,
        longitude: 37,
        serverVersion: 4,
      );
      await tester.runAsync(() async {
        await DriftObjectsDataSource(db).saveObject(object);
        server.records['edit'] = {
          'version': 5,
          'business': syncRequest(object.copyWith(name: 'Server').toJson())
            ..remove('serverVersion'),
        };
        await SyncEngine(SyncProcessor(db, dio: () => dio)).run();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SyncConflictsPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.text('Локальная версия: 4'), findsOneWidget);
      expect(find.text('Серверная версия: 5'), findsOneWidget);
      expect(find.textContaining('"name": "Local"'), findsWidgets);
      expect(find.textContaining('"name": "Server"'), findsWidgets);
      await tester.tap(find.text('Повторить локальную'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Разрешён:'), findsOneWidget);
      final queue = await db.select(db.syncQueue).getSingle();
      expect(queue.operationId, isNull);
      expect(queue.payload, isNull);
      expect(server.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Visit dialog explains preserved event and offers no server overwrite',
    (tester) async {
      final snapshot = jsonEncode({
        'id': 'visit',
        'accuracy': 8,
        'serverVersion': 4,
      });
      final conflict = SyncConflict(
        id: 1,
        queueId: 1,
        entityType: 'visit',
        entityId: 'visit',
        requestPayload: snapshot,
        localPayload: snapshot,
        currentLocalPayload: snapshot,
        serverPayload: jsonEncode({
          'id': 'visit',
          'accuracy': 12,
          'serverVersion': 5,
        }),
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: SyncConflictDialog(conflict: conflict)),
          ),
        ),
      );
      expect(find.text('Повторить локальную'), findsNothing);
      expect(find.text('Принять серверную'), findsOneWidget);
      expect(
        find.textContaining('локальный вариант останется в истории'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
