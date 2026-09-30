import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Команда фокуса отделена от MapController, жизненным циклом которого управляет
/// виджет. Номер изменения позволяет повторно показать объект после сдвига карты.
class MapFocusController extends Notifier<({String? objectId, int revision})> {
  @override
  ({String? objectId, int revision}) build() => (objectId: null, revision: 0);

  void focus(String objectId) {
    state = (objectId: objectId, revision: state.revision + 1);
  }
}

final mapFocusProvider =
    NotifierProvider<MapFocusController, ({String? objectId, int revision})>(
      MapFocusController.new,
    );
