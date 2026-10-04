import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';

class AttendanceService {
  final String baseUrl = "https://api.staging.schoolbase.africa";

  Future<bool> _isConnected() async {
    var result = await (Connectivity().checkConnectivity());
    if (result.contains(ConnectivityResult.none)) return false;
    return true;
  }

  // --- GATEMAN LOGIC (Works for Student AND Teacher) ---
  Future<Map<String, dynamic>> markGateAttendance(
    String nfcTagId,
    String type,
  ) async {
    if (!(await _isConnected())) {
      await DatabaseHelper.instance.insertAttendance(nfcTagId, type);
      return {
        'success': true,
        'message': 'Saved Offline.',
        'user_name': 'Offline Record',
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/attendance/gate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        // The backend identifies if the nfc_tag belongs to a student or teacher
        body: jsonEncode({'nfc_tag': nfcTagId, 'type': type}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': data['message'] ?? 'Success',
          'user_name': data['user_name'] ?? 'User',
          // If backend returns role/type, you can add it here
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Not Registered / Error',
        };
      }
    } catch (e) {
      await DatabaseHelper.instance.insertAttendance(nfcTagId, type);
      return {'success': true, 'message': 'Connection Failed. Saved Offline.'};
    }
  }

  // --- SYNC LOGIC ---
  Future<String> syncOfflineRecords() async {
    if (!(await _isConnected())) return "No Internet Connection";

    List<Map<String, dynamic>> records = await DatabaseHelper.instance
        .getAllUnsynced();
    if (records.isEmpty) return "No records to sync";

    int successCount = 0;
    for (var record in records) {
      if (record['class_id'] == null) {
        var result = await markGateAttendance(
          record['nfc_tag'],
          record['type'],
        );
        if (result['success'] &&
            !result['message'].toString().contains('Offline')) {
          await DatabaseHelper.instance.deleteRecord(record['id']);
          successCount++;
        }
      }
    }
    return "Synced $successCount records successfully.";
  }
}
