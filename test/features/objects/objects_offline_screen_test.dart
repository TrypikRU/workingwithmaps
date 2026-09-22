import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/core/network/dio_provider.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_screen.dart';

import '../../support/test_database.dart';
import 'objects_refresh_test.dart' show TestAdapter;

void main() {
  for (final offline in [true, false]) {
    testWidgets(
      'Objects remain visible after ${offline ? 'network error' : 'HTTP 500'}',
      (tester) async {
        final db = createTestDatabase();
        final target = (await db.select(db.technicalObjects).get()).first;
        final adapter = TestAdapter()..status = 500;
        if (offline) adapter.failure = DioExceptionType.connectionError;
        final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
          ..httpClientAdapter = adapter;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          dio.close(force: true);
          await db.close();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              dioProvider.overrideWithValue(dio),
            ],
            child: const MaterialApp(home: ObjectsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(target.name), findsOneWidget);
        await tester.tap(find.byTooltip('Обновить объекты с сервера'));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            offline
                ? 'Нет соединения с сервером. Сохранённые объекты доступны.'
                : 'Ошибка сервера. Сохранённые объекты доступны.',
          ),
          findsOneWidget,
        );
        expect(find.text(target.name), findsOneWidget);
        expect(find.text('Не удалось загрузить объекты'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // Dispose listeners before the test binding checks pending timers.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
