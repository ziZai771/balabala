import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compare line wrapping TextPainter vs Text', (tester) async {
    const fontSize = 18.0;
    const lineHeight = 1.8;
    const maxWidth = 700.0;
    final textStyle = TextStyle(fontSize: fontSize, height: lineHeight);

    final longText = List.filled(200, '测').join('');

    final tp = TextPainter(
      text: TextSpan(text: longText, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);
    debugPrint('TP: height=${tp.height} (200字)');

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: maxWidth,
            child: Text(
              longText,
              key: key,
              style: textStyle,
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
    final box = key.currentContext!.findRenderObject() as RenderBox;
    debugPrint('Text: height=${box.size.height} (200字)');
    debugPrint('DIFF = ${box.size.height - tp.height}');

    for (final count in [10, 20, 40, 80]) {
      final t = List.filled(count, '测').join('');
      final tp2 = TextPainter(
        text: TextSpan(text: t, style: textStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: maxWidth);
      final key2 = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: maxWidth,
              child: Text(
                t,
                key: key2,
                style: textStyle,
                textDirection: TextDirection.ltr,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );
      final box2 = key2.currentContext!.findRenderObject() as RenderBox;
      debugPrint('$count字: TP=${tp2.height.toStringAsFixed(1)} Text=${box2.size.height.toStringAsFixed(1)} diff=${(box2.size.height-tp2.height).toStringAsFixed(1)}');
    }
  });
}
