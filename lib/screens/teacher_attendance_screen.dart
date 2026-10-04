import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  late final _api = widget.attendanceService ?? TeacherAttendanceService();
  late final _nfc = widget.nfcService ?? NfcService();
  List<Map<String, String>> _classes = [];
  String? _classId;
  String _method = 'NFC';
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
          .map((value) => value.toString()).toList();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _methodPolicy = policy;
        _method = enabledMethods.contains(_method)
            ? _method : (enabledMethods.isEmpty ? 'NFC' : enabledMethods.first);
        _classId = classes.isEmpty ? null : classes.first['id'];
        _message = classes.isEmpty
            ? 'No classes assigned in the active session'
            : 'Select a class, then scan a student card';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not load classes: $error');
    }
  }

  Future<void> _startScan() async {
    if (_classId == null || _scanning) return;
    if (_method != 'NFC') {
      setState(() => _message = 'This attendance method needs its capture provider');
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
          final student = result['student'] is Map ? result['student'] as Map : {};
          final name = student['name']?.toString() ?? 'Student';
          final already = result['result'] == 'already_recorded';
          setState(() => _message = already
              ? '$name was already marked present today'
              : '$name marked present');
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
    if (_scanning) _nfc.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class attendance'),
        actions: [IconButton(onPressed: () => showLogoutDialog(context),
            icon: const Icon(Icons.logout))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _classId,
              decoration: const InputDecoration(labelText: 'Class'),
              items: _classes.map((item) => DropdownMenuItem(
                value: item['id'], child: Text(item['name'] ?? 'Class'),
              )).toList(),
              onChanged: _scanning ? null : (value) => setState(() => _classId = value),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Attendance method'),
              items: (_methodPolicy?['enabledMethods'] as List? ?? ['NFC'])
                  .map((value) => DropdownMenuItem<String>(
                    value: value.toString(),
                    child: Text(value == 'NFC' ? 'NFC card' : value.toString()),
                  )).toList(),
              onChanged: _scanning ? null : (value) => setState(() => _method = value ?? 'NFC'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _classId == null || _scanning || _method != 'NFC' ? null : _startScan,
              icon: const Icon(Icons.nfc),
              label: Text(_scanning ? 'Waiting for card…' : 'Scan student card'),
            ),
            const SizedBox(height: 32),
            Text(_message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(onPressed: _loadClasses, child: const Text('Refresh classes')),
          ],
        ),
      ),
    );
  }
}
