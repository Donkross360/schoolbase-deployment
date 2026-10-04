import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class TeacherAttendanceService {
  Future<List<Map<String, dynamic>>> students(String classId) async {
    final response = await ApiClient.request(
      'GET',
      '/attendance/mobile/classes/$classId/students',
    );
    if (response.statusCode != 200) throw StateError(_error(response));
    final decoded = jsonDecode(response.body);
    final rows = decoded is List ? decoded : decoded['data'] as List? ?? [];
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> markFace(
    String classId,
    String studentId,
    Uint8List photo,
  ) async {
    final response = await ApiClient.postCameraPhoto(
      '/attendance/mobile/face-check-in',
      {'classId': classId, 'studentId': studentId, 'clientEventId': _eventId()},
      photo,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_error(response));
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(
      decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded as Map,
    );
  }

  Future<Map<String, dynamic>> methods() async {
    final response = await ApiClient.request(
      'GET',
      '/attendance/mobile/methods',
    );
    if (response.statusCode != 200) throw StateError(_error(response));
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<List<Map<String, String>>> classes() async {
    final response = await ApiClient.request(
      'GET',
      '/attendance/mobile/classes',
    );
    if (response.statusCode != 200) throw StateError(_error(response));
    final decoded = jsonDecode(response.body);
    final rows = decoded is List ? decoded : (decoded['data'] as List? ?? []);
    return rows.map<Map<String, String>>((row) {
      final item = row as Map;
      return {
        'id': item['id'].toString(),
        'name': '${item['name']} ${item['arm'] ?? ''}'.trim(),
      };
    }).toList();
  }

  Future<Map<String, dynamic>> markNfc(String classId, String cardId) async {
    final body = {
      'classId': classId,
      'cardId': cardId,
      'clientEventId': _eventId(),
    };
    final response = await ApiClient.request(
      'POST',
      '/attendance/mobile/nfc-tap',
      body: body,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(_error(response));
    }
    final decoded = jsonDecode(response.body);
    return Map<String, dynamic>.from(
      decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded as Map,
    );
  }

  String _error(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final message = decoded['message'];
      if (message is List) return message.join(', ');
      if (message != null) return message.toString();
    } catch (_) {
      /* Use status below. */
    }
    return 'Request failed (${response.statusCode})';
  }

  String _eventId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
