import 'dart:convert';
import 'package:http/http.dart' as http;

class HallSensorService {
  // When Chrome and mock_server.py run on the SAME computer:
  static const String baseUrl = 'http://127.0.0.1:5000';

  static Future<Map<String, dynamic>> getHallData() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/hall'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw Exception('Hall API returned ${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/history'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw Exception('History API returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((event) => Map<String, dynamic>.from(event as Map))
        .toList();
  }
}
