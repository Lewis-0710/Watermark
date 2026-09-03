import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:watermark_remover/main.dart';

void main() {
  testWidgets('应用可以正常启动并渲染首页输入框', (tester) async {
    await tester.pumpWidget(const WatermarkRemoverApp());
    expect(find.byType(TextField), findsOneWidget);
  });
}
