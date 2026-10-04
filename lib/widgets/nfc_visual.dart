import 'package:flutter/material.dart';
import '../utils/constants.dart';

class NfcVisual extends StatelessWidget {
  final Color activeColor;

  const NfcVisual({super.key, this.activeColor = AppColors.primaryRed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Outer Ring
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activeColor.withValues(alpha: 0.05),
            ),
          ),

          // 2. Middle Ring
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activeColor.withValues(alpha: 0.15),
            ),
          ),

          // 3. Center Button
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: activeColor.withValues(alpha: 0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // CHANGED: Uses Icons.wifi to match the signal waves in the screenshot
                Icon(Icons.wifi, size: 45, color: activeColor),
                const SizedBox(height: 4),
                Text(
                  "NFC",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: activeColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
