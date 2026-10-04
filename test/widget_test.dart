import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_base/screens/teacher_attendance_screen.dart';
import 'package:school_base/services/teacher_attendance_service.dart';

class FakeAttendanceService extends TeacherAttendanceService {
  final List<String> enabledMethods;

  FakeAttendanceService(this.enabledMethods);

  @override
  Future<List<Map<String, String>>> classes() async => [
    {'id': 'class-1', 'name': 'Primary 1 A'},
  ];

  @override
  Future<Map<String, dynamic>> methods() async => {
    'enabledMethods': enabledMethods,
    'fingerprintProvider': 'secugen',
  };
}

void main() {
  testWidgets('teacher can start an enabled NFC class scan', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TeacherAttendanceScreen(
        attendanceService: FakeAttendanceService(['NFC']),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Primary 1 A'), findsOneWidget);
    expect(find.text('NFC card'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('unimplemented biometric capture cannot start attendance', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TeacherAttendanceScreen(
        attendanceService: FakeAttendanceService(['FACE']),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('FACE'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
}
