import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/widgets/scroll_to_top_area.dart';

void main() {
  testWidgets('Кнопка появляется после прокрутки и возвращает к началу', (
    tester,
  ) async {
    late ScrollController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollToTopArea(
            builder: (scrollController) {
              controller = scrollController;
              return ListView.builder(
                controller: scrollController,
                itemExtent: 80,
                itemCount: 50,
                itemBuilder: (_, index) => Text('Объект $index'),
              );
            },
          ),
        ),
      ),
    );
    expect(find.byTooltip('Наверх'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(200));
    expect(find.byTooltip('Наверх'), findsOneWidget);
    await tester.tap(find.byTooltip('Наверх'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.byTooltip('Наверх'), findsNothing);
  });
}
