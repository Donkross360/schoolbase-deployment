import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_base/screens/teacher_attendance_screen.dart';
import 'package:school_base/services/teacher_attendance_service.dart';

class FakeAttendanceService extends TeacherAttendanceService {
  final List<String> enabledMethods;
  final bool photoApproved;

  FakeAttendanceService(this.enabledMethods, {this.photoApproved = false});

  @override
  Future<List<Map<String, String>>> classes() async => [
    {'id': 'class-1', 'name': 'Primary 1 A'},
  ];

  @override
  Future<Map<String, dynamic>> methods() async => {
    'enabledMethods': enabledMethods,
    'fingerprintProvider': 'secugen',
  };

  @override
  Future<List<Map<String, dynamic>>> students(String classId) async => [
    {
      'id': 'student-1',
      'name': 'Ada Okoro',
      'faceReady': photoApproved,
      'photoUrl': null,
    },
  ];
}

void main() {
  testWidgets('teacher can start an enabled NFC class scan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherAttendanceScreen(
          attendanceService: FakeAttendanceService(['NFC']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Primary 1 A'), findsOneWidget);
    expect(find.text('NFC card'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('face capture waits for an approved student photo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherAttendanceScreen(
          attendanceService: FakeAttendanceService(['FACE']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FACE'), findsOneWidget);
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Okoro (photo needs approval)'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('approved student can open face capture', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherAttendanceScreen(
          attendanceService: FakeAttendanceService([
            'FACE',
          ], photoApproved: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Okoro').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('shows no scanner when every method is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherAttendanceScreen(
          attendanceService: FakeAttendanceService([]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No attendance method is currently available'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });
}
