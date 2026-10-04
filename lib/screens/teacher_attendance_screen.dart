import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'face_check_in_screen.dart';
import '../services/nfc_service.dart';
import '../services/teacher_attendance_service.dart';
import '../widgets/logout_dialog.dart';

class TeacherAttendanceScreen extends StatefulWidget {
  final TeacherAttendanceService? attendanceService;
  final NfcService? nfcService;

  const TeacherAttendanceScreen({
    super.key,
    this.attendanceService,
    this.nfcService,
  });

  @override
  State<TeacherAttendanceScreen> createState() =>
      _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  late final _api = widget.attendanceService ?? TeacherAttendanceService();
  late final _nfc = widget.nfcService ?? NfcService();
  List<Map<String, String>> _classes = [];
  String? _classId;
  String _method = 'NFC';
  List<Map<String, dynamic>> _students = [];
  String? _studentId;
  Map<String, dynamic>? _methodPolicy;
  String _message = 'Loading your classes…';
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final results = await Future.wait([_api.classes(), _api.methods()]);
      final classes = results[0] as List<Map<String, String>>;
      final policy = results[1] as Map<String, dynamic>;
      final enabledMethods = (policy['enabledMethods'] as List? ?? ['NFC'])
          .map((value) => value.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _methodPolicy = policy;
        _method = enabledMethods.contains(_method)
            ? _method
            : (enabledMethods.isEmpty ? '' : enabledMethods.first);
        _classId = classes.isEmpty ? null : classes.first['id'];
        _message = classes.isEmpty
            ? 'No classes assigned in the active session'
            : enabledMethods.isEmpty
            ? 'No attendance method is currently available. Ask an admin to check settings.'
            : 'Select a class and attendance method';
      });
      if (_classId != null) await _loadStudents(_classId!);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not load classes: $error');
    }
  }

  Future<void> _loadStudents(String classId) async {
    try {
      final students = await _api.students(classId);
      if (!mounted || _classId != classId) return;
      setState(() {
        _students = students;
        _studentId = students.any((row) => row['id'] == _studentId)
            ? _studentId
            : null;
      });
    } catch (error) {
      if (mounted && _classId == classId) {
        setState(() {
          _students = [];
          _studentId = null;
          _message = 'Could not load class students: $error';
        });
      }
    }
  }

  Future<void> _startFaceCheckIn() async {
    final classId = _classId;
    final student = _students
        .where((row) => row['id'] == _studentId)
        .firstOrNull;
    if (classId == null || student == null || student['faceReady'] != true) {
      return;
    }
    setState(() => _scanning = true);
    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => FaceCheckInScreen(
            classId: classId,
            studentId: student['id'].toString(),
            studentName: student['name']?.toString() ?? 'Student',
            referencePhotoUrl: student['photoUrl']?.toString(),
            attendanceService: _api,
          ),
        ),
      );
      if (!mounted || result == null) return;
      final name =
          (result['student'] as Map?)?['name']?.toString() ?? 'Student';
      final already = result['result'] == 'already_recorded';
      setState(
        () => _message = already
            ? '$name was already marked present today'
            : '$name marked present by face verification',
      );
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _startScan() async {
    if (_classId == null || _scanning) return;
    if (_method != 'NFC') {
      setState(
        () => _message = 'This attendance method needs its capture provider',
      );
      return;
    }
    if (!await _nfc.checkAvailability()) {
      setState(() => _message = 'NFC is unavailable on this phone');
      return;
    }
    setState(() {
      _scanning = true;
      _message = 'Hold the student card against this phone';
    });
    _nfc.startSession(
      onTagRead: (cardId) async {
        HapticFeedback.selectionClick();
        if (mounted) setState(() => _message = 'Checking card…');
        try {
          final result = await _api.markNfc(_classId!, cardId);
          if (!mounted) return;
          final student = result['student'] is Map
              ? result['student'] as Map
              : {};
          final name = student['name']?.toString() ?? 'Student';
          final already = result['result'] == 'already_recorded';
          setState(
            () => _message = already
                ? '$name was already marked present today'
                : '$name marked present',
          );
          HapticFeedback.mediumImpact();
        } catch (error) {
          if (mounted) setState(() => _message = 'Check-in failed: $error');
        } finally {
          if (mounted) setState(() => _scanning = false);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _message = 'Card scan failed: $error';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    if (_scanning && _method == 'NFC') _nfc.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedStudent = _students
        .where((row) => row['id'] == _studentId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class attendance'),
        actions: [
          IconButton(
            onPressed: () => showLogoutDialog(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_classId),
              initialValue: _classId,
              decoration: const InputDecoration(labelText: 'Class'),
              items: _classes
                  .map(
                    (item) => DropdownMenuItem(
                      value: item['id'],
                      child: Text(item['name'] ?? 'Class'),
                    ),
                  )
                  .toList(),
              onChanged: _scanning
                  ? null
                  : (value) {
                      setState(() {
                        _classId = value;
                        _studentId = null;
                        _students = [];
                      });
                      if (value != null) _loadStudents(value);
                    },
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              key: ValueKey(_method),
              initialValue: _method.isEmpty ? null : _method,
              decoration: const InputDecoration(labelText: 'Attendance method'),
              items: (_methodPolicy?['enabledMethods'] as List? ?? ['NFC'])
                  .map(
                    (value) => DropdownMenuItem<String>(
                      value: value.toString(),
                      child: Text(
                        value == 'NFC' ? 'NFC card' : value.toString(),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _scanning
                  ? null
                  : (value) => setState(() => _method = value ?? 'NFC'),
            ),
            const SizedBox(height: 16),
            if (_method == 'FACE') ...[
              DropdownButtonFormField<String>(
                key: ValueKey('face-student-$_classId-$_studentId'),
                initialValue: _studentId,
                decoration: const InputDecoration(labelText: 'Student'),
                items: _students
                    .map(
                      (row) => DropdownMenuItem<String>(
                        value: row['id'].toString(),
                        child: Text(
                          row['faceReady'] == true
                              ? row['name'].toString()
                              : '${row['name']} (photo needs approval)',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _scanning
                    ? null
                    : (value) => setState(() => _studentId = value),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scanning || selectedStudent?['faceReady'] != true
                    ? null
                    : _startFaceCheckIn,
                icon: const Icon(Icons.face),
                label: const Text('Open camera for face check-in'),
              ),
            ] else if (_method == 'NFC')
              FilledButton.icon(
                onPressed: _classId == null || _scanning || _method != 'NFC'
                    ? null
                    : _startScan,
                icon: const Icon(Icons.nfc),
                label: Text(
                  _scanning ? 'Waiting for card…' : 'Scan student card',
                ),
              ),
            const SizedBox(height: 32),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: _loadClasses,
              child: const Text('Refresh classes'),
            ),
          ],
        ),
      ),
    );
  }
}
