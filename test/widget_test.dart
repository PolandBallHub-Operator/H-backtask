import 'package:flutter_test/flutter_test.dart';
import 'package:h_backtask/main.dart';

void main() {
  testWidgets('起動画面に接続案内を表示する', (tester) async {
    await tester.pumpWidget(const HBacktaskApp());
    expect(find.text('H-backtask'), findsOneWidget);
    expect(find.text('AndroidOS / FireOSを接続してください'), findsNWidgets(2));
    expect(find.text('ADBデバイスに接続'), findsOneWidget);
  });
}
