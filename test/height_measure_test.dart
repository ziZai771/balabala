import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('measure char widths', (tester) async {
    const fontSize = 18.0;
    const lineHeight = 1.8;
    final textStyle = TextStyle(fontSize: fontSize, height: lineHeight);

    // 测量单个字符宽度
    for (final ch in ['测', '中', '文', 'a', '1', '，', '。', '　', 'A', '0']) {
      final tp = TextPainter(
        text: TextSpan(text: ch, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      print('char=$ch width=${tp.width.toStringAsFixed(2)} height=${tp.height.toStringAsFixed(2)}');
    }

    // 测量单行高度（fontSize=18, lineHeight=1.8）
    final tp = TextPainter(
      text: const TextSpan(text: '测', style: TextStyle(fontSize: 18, height: 1.8)),
      textDirection: TextDirection.ltr,
    )..layout();
    print('single line height=${tp.height.toStringAsFixed(2)}');

    // 测量 10 个中文字符的宽度
    final tp10 = TextPainter(
      text: const TextSpan(text: '测测测测测测测测测测', style: TextStyle(fontSize: 18, height: 1.8)),
      textDirection: TextDirection.ltr,
    )..layout();
    print('10 chars width=${tp10.width.toStringAsFixed(2)} per_char=${(tp10.width/10).toStringAsFixed(2)}');
  });
}
