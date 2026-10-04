import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class AdminService {

  // --- SEARCH STUDENTS ---
  Future<List<dynamic>> searchUsers(String query) async {
    List<dynamic> allResults = [];
    try {
      final response = await ApiClient.request(
        'GET', '/students', query: {'search': query, 'limit': '50'},
      );
      _processResponse(response, 'student', allResults);

      return allResults;
    } catch (e) {
      return [];
    }
  }

  // --- LINK CARD (Handles Both) ---
  Future<String?> linkCardToUser(
    String userId,
    String nfcId,
    String userType,
  ) async {
    try {
      // Determine endpoint based on type
      if (userType.toLowerCase() == 'teacher') {
        return 'Teacher card enrollment is not available yet.';
      }

      final response = await ApiClient.request(
        'POST', '/attendance/mobile/students/$userId/card',
        body: {'cardId': nfcId},
      );

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 204) {
        return null;
      } else {
        final data = jsonDecode(response.body);
        return data['message']?.toString() ?? "Failed to link card.";
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  void _processResponse(
    http.Response response,
    String type,
    List<dynamic> list,
  ) {
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      List<dynamic> rawData = [];
      if (decoded is Map && decoded['data'] != null) {
        if (decoded['data'] is List) {
          rawData = decoded['data'];
        } else if (decoded['data'] is Map && decoded['data']['data'] != null) {
          rawData = decoded['data']['data'];
        }
      } else if (decoded is List) {
        rawData = decoded;
      }

      for (var item in rawData) {
        list.add({
          'id': item['id'],
          'name': "${item['first_name']} ${item['last_name']}",
          'school_id': item['registration_number'] ?? item['email'] ?? 'ID:${item['id']}',
          'type': type, // 'student' or 'teacher'
        });
      }
    }
  }
}
