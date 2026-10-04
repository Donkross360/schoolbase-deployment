import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AttendanceToggle extends StatelessWidget {
  final bool isCheckInSelected;
  final Function(bool) onToggle;

  const AttendanceToggle({
    super.key,
    required this.isCheckInSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          _buildButton("Check In", true),
          _buildButton("Check Out", false),
        ],
      ),
    );
  }

  Widget _buildButton(String text, bool isCheckInBtn) {
    bool isActive = isCheckInSelected == isCheckInBtn;
    return Expanded(
      child: GestureDetector(
        onTap: () => onToggle(isCheckInBtn),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryRed : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
