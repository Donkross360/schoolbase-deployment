import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/teacher_attendance_service.dart';

class FaceCheckInScreen extends StatefulWidget {
  final String classId;
  final String studentId;
  final String studentName;
  final String? referencePhotoUrl;
  final TeacherAttendanceService attendanceService;

  const FaceCheckInScreen({
    super.key,
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.attendanceService,
    this.referencePhotoUrl,
  });

  @override
  State<FaceCheckInScreen> createState() => _FaceCheckInScreenState();
}

class _FaceCheckInScreenState extends State<FaceCheckInScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Uint8List? _photo;
  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this phone');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final previous = _camera;
      setState(() {
        _camera = controller;
        _error = null;
      });
      await previous?.dispose();
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera unavailable: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
    } else if (state == AppLifecycleState.resumed && _photo == null) {
      _startCamera();
    }
  }

  Future<void> _takePhoto() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _working) return;
    setState(() => _working = true);
    try {
      final image = await camera.takePicture();
      final bytes = await image.readAsBytes();
      // The capture is submitted from memory; do not leave a student photo in cache.
      try {
        await File(image.path).delete();
      } catch (_) {
        // The OS may have already removed the temporary capture.
      }
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not take a photo: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await widget.attendanceService.markFace(
        widget.classId,
        widget.studentId,
        photo,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Face check-in')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (widget.referencePhotoUrl != null)
                    CircleAvatar(
                      backgroundImage: NetworkImage(widget.referencePhotoUrl!),
                      radius: 24,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.studentName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Check that the selected student is in front of you. Ask them to face the camera in good light. Do not scan a printed photo or screen.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_photo != null)
                          Image.memory(_photo!, fit: BoxFit.contain)
                        else if (camera != null && camera.value.isInitialized)
                          CameraPreview(camera)
                        else
                          const Center(child: CircularProgressIndicator()),
                        if (_photo == null)
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 220,
                                height: 290,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(110),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16),
              if (_photo == null)
                FilledButton.icon(
                  onPressed:
                      _working || camera == null || !camera.value.isInitialized
                      ? null
                      : _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take photo'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _working
                            ? null
                            : () => setState(() => _photo = null),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _working ? null : _submit,
                        child: Text(
                          _working ? 'Checking…' : 'Verify and mark present',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
