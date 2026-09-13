import 'package:drift/native.dart';
import 'package:workingwithmaps/core/database/app_database.dart';

/// Та же схема и beforeOpen, что на Android, без path_provider и файлов устройства.
AppDatabase createTestDatabase({bool seedDemoData = true}) =>
    AppDatabase.forTesting(NativeDatabase.memory(), seedDemoData: seedDemoData);
