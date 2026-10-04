import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/nfc_service.dart';
import '../providers/attendance_provider.dart';
import '../utils/constants.dart';
import '../widgets/nfc_visual.dart';

class GatemanScreen extends StatefulWidget {
  const GatemanScreen({super.key});

  @override
  State<GatemanScreen> createState() => _GatemanScreenState();
}

class _GatemanScreenState extends State<GatemanScreen> {
  final NfcService _nfcService = NfcService();

  // State
  bool _isCheckIn = true;
  String _statusTitle = "Ready to Scan";
  String _statusSubtitle = "Tap your card to check-in.";

  // Visual Feedback State
  Color _visualColor = AppColors.primaryRed;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startNfcSession();
  }

  void _startNfcSession() async {
    bool isAvailable = await _nfcService.checkAvailability();

    if (!isAvailable) {
      if (mounted) {
        setState(() => _statusSubtitle = "NFC not available on this device");
      }
      return;
    }

    _nfcService.startSession(
      onTagRead: (tagId) async {
        if (_isProcessing) {
          return;
        }

        // 1. Immediate Feedback
        HapticFeedback.lightImpact();
        setState(() {
          _isProcessing = true;
          _statusTitle = "Verifying...";
          _statusSubtitle = "Please wait";
          _visualColor = Colors.orange;
        });

        // 2. Perform Check
        final result = await context.read<AttendanceProvider>().markGateEntry(
          tagId,
          _isCheckIn ? 'in' : 'out',
        );

        if (!mounted) {
          return;
        }

        // 3. Show Result
        if (result['success'] == true) {
          _showSuccess(result['user_name'] ?? 'User');
        } else {
          _showFailure(result['message'] ?? 'Not Registered');
        }
      },
      onError: (err) {
        if (mounted && !_isProcessing) {
          // Silent error handling
        }
      },
    );
  }

  void _showSuccess(String name) {
    HapticFeedback.heavyImpact();
    setState(() {
      _visualColor = Colors.green;
      _statusTitle = "Success";
      _statusSubtitle = "Welcome, $name";
    });
    _resetAfterDelay();
  }

  void _showFailure(String error) {
    HapticFeedback.vibrate();
    setState(() {
      _visualColor = Colors.red;
      _statusTitle = "Failed";
      _statusSubtitle = error;
    });
    _resetAfterDelay();
  }

  void _resetAfterDelay() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _visualColor = AppColors.primaryRed;
          _statusTitle = "Ready to Scan";
          _updateSubtitle();
        });
      }
    });
  }

  void _updateSubtitle() {
    setState(() {
      _statusSubtitle =
          "Tap your card to ${_isCheckIn ? 'check-in' : 'check-out'}.";
    });
  }

  @override
  void dispose() {
    _nfcService.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // --- 1. HEADER ---
              const Text(
                "Record Attendance",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 30),

              // --- 2. SEGMENTED TOGGLE ---
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    // CHECK IN BUTTON
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_isProcessing) {
                            setState(() {
                              _isCheckIn = true;
                              _updateSubtitle();
                            });
                            HapticFeedback.selectionClick();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isCheckIn
                                ? AppColors.primaryRed
                                : Colors.white,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(7),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Check In",
                            style: TextStyle(
                              color: _isCheckIn
                                  ? Colors.white
                                  : AppColors.primaryRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // VERTICAL DIVIDER
                    Container(width: 1, color: Colors.grey.shade300),

                    // CHECK OUT BUTTON
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_isProcessing) {
                            setState(() {
                              _isCheckIn = false;
                              _updateSubtitle();
                            });
                            HapticFeedback.selectionClick();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: !_isCheckIn
                                ? AppColors.primaryRed
                                : Colors.white,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(7),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            "Check Out",
                            style: TextStyle(
                              color: !_isCheckIn
                                  ? Colors.white
                                  : AppColors.primaryRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // --- 3. VISUAL ---
              NfcVisual(activeColor: _visualColor),

              const Spacer(flex: 2),

              // --- 4. BOTTOM STATUS ---
              Text(
                _statusTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusSubtitle,
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
