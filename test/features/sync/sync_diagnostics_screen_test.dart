import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_providers.dart';
import 'package:workingwithmaps/core/sync/sync_result.dart';
import 'package:workingwithmaps/core/sync/sync_run_control.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/features/sync/presentation/sync_screen.dart';

import '../../support/sync_server.dart';
import '../../support/test_database.dart';

// Widget contract test: real Drift streams, controllable engine completion.
// Actual HTTP/ACK/retry behavior is covered in sync_engine_test.dart.
class UiSyncEngine extends SyncEngine {
  UiSyncEngine(AppDatabase db)
    : super(
        SyncProcessor(db, dio: () => throw StateError('UI must not use HTTP')),
      );
  final activity = StreamController<bool>.broadcast();
  Completer<SyncResult>? completion;
  bool retryRequested = false;
  int calls = 0;
  @override
  Stream<bool> watchRunning() async* {
    yield completion != null;
    yield* activity.stream;
  }

  @override
  Future<SyncResult> run({bool retryFailed = false, SyncRunControl? control}) {
    calls++;
    retryRequested = retryFailed;
    completion = Completer<SyncResult>();
    activity.add(true);
    return completion!.future;
  }

  void finish() {
    final pending = completion!;
    completion = null;
    activity.add(false);
    pending.complete(const SyncResult(succeeded: 1));
  }
}

void main() {
  testWidgets('Empty sync screen has no automatic HTTP or lost local state', (
    tester,
  ) async {
    final db = createTestDatabase(seedDemoData: false);
    addTearDown(db.close);
    final sync = UiSyncEngine(db);
    addTearDown(sync.activity.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(sync),
        ],
        child: const MaterialApp(home: SyncScreen()),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Synced: 0',
      'Pending: 0',
      'Syncing: 0',
      'Failed: 0',
      'Пока не было',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(sync.calls, 0);
    await tester.scrollUntilVisible(find.text('Очередь пуста'), 250);
    expect(find.text('Очередь пуста'), findsOneWidget);
    expect(find.text('Синхронизация выполняется…'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Diagnostics shows details, requests retry and follows DB and engine streams',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = createTestDatabase();
      addTearDown(db.close);
      await enqueue(db, 'demo-visit');
      await db
          .update(db.syncQueue)
          .write(
            const SyncQueueCompanion(
              syncStatus: Value(SyncStatus.failed),
              attemptCount: Value(1),
              operationId: Value('stable-key'),
              lastError: Value(
                '{"kind":"conflict","statusCode":409,"retryable":false}',
              ),
            ),
          );
      final sync = UiSyncEngine(db);
      addTearDown(sync.activity.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            syncEngineProvider.overrideWithValue(sync),
          ],
          child: const MaterialApp(home: SyncScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Пока не было'), findsOneWidget);
      expect(find.text('Synced: 0'), findsOneWidget);
      expect(find.text('Failed: 1'), findsOneWidget);
      expect(find.text('entityType: visit'), findsOneWidget);
      expect(find.text('entityId: demo-visit'), findsOneWidget);
      expect(find.text('operation: upsert'), findsOneWidget);
      expect(find.text('attemptCount: 1'), findsOneWidget);
      expect(find.textContaining('createdAt:'), findsOneWidget);
      expect(find.text('nextRetryAt: Автоповтор отключён'), findsOneWidget);
      await tester.tap(find.text('Подробности ошибки'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('"statusCode": 409'), findsWidgets);
      expect(find.text('operationId: stable-key'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Повторить ошибочные'));
      await tester.pump();
      expect(sync.calls, 1);
      expect(sync.retryRequested, isTrue);
      expect(find.text('Синхронизация выполняется…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Синхронизировать сейчас'),
            )
            .onPressed,
        isNull,
      );
      // Failed is visible until the committed result arrives, not deleted by UI.
      expect(await db.select(db.syncQueue).get(), hasLength(1));
      await db.transaction(() async {
        await db.delete(db.syncQueue).go();
        await db
            .into(db.appMetadata)
            .insert(
              AppMetadataCompanion.insert(
                key: 'sync.acknowledged_count',
                value: '1',
              ),
            );
        await db
            .into(db.appMetadata)
            .insert(
              AppMetadataCompanion.insert(
                key: 'sync.last_success_at',
                value: '2026-09-12T12:00:00Z',
              ),
            );
      });
      sync.finish();
      await tester.pumpAndSettle();
      expect(find.text('Synced: 1'), findsOneWidget);
      expect(find.text('Failed: 0'), findsOneWidget);
      expect(find.text('Очередь пуста'), findsOneWidget);
      expect(find.text('Пока не было'), findsNothing);
      // Foreground run outside the screen's action controller is visible too.
      final automatic = sync.run();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Синхронизация выполняется…'), findsOneWidget);
      sync.finish();
      await automatic;
      await tester.pumpAndSettle();
      expect(find.text('Синхронизация выполняется…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
