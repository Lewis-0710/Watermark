import 'package:flutter_test/flutter_test.dart';

import 'package:watermark_remover/main.dart';

void main() {
  testWidgets('应用可以启动并显示首页标题', (tester) async {
    await tester.pumpWidget(const WatermarkRemoverApp());
    expect(find.text('水印清除大师'), findsOneWidget);
  });
}
