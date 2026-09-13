import 'package:flutter/material.dart';

import '../domain/technical_object.dart';

// Представление статусов принадлежит UI, а не доменной модели.
extension ObjectStatusPresentation on ObjectStatus {
  String get label => switch (this) {
    ObjectStatus.planned => 'Запланирован',
    ObjectStatus.visited => 'Посещён',
    ObjectStatus.error => 'Ошибка',
  };

  Color get color => switch (this) {
    ObjectStatus.planned => const Color(0xFF1565C0),
    ObjectStatus.visited => const Color(0xFF2E7D32),
    ObjectStatus.error => const Color(0xFFC62828),
  };

  IconData get icon => switch (this) {
    ObjectStatus.planned => Icons.schedule,
    ObjectStatus.visited => Icons.check,
    ObjectStatus.error => Icons.priority_high,
  };
}

extension ObjectPriorityPresentation on ObjectPriority {
  String get label => switch (this) {
    ObjectPriority.low => 'Низкий',
    ObjectPriority.normal => 'Обычный',
    ObjectPriority.high => 'Высокий',
    ObjectPriority.critical => 'Критический',
  };
}
