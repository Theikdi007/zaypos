// QA round 17: can the real iPhone reach the Mac's API? Reports to r17_host.py over the LAN (QA_HOST), so it also
// works when the app is launched without a driver (flutter drive cannot find the VM service over Wi-Fi).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const api = String.fromEnvironment('API_BASE_URL');
const host = String.fromEnvironment('QA_HOST');

Future<void> post(String path, List<int> body) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final rq = await c.postUrl(Uri.parse('$host$path'));
  rq.contentLength = body.length;
  rq.add(body);
  await (await rq.close()).drain<void>();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('r17 probe: device reaches the API', (tester) async {
    String result;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final r = await (await c.getUrl(Uri.parse('$api/api/v1/sync/pull'))).close();
      result = 'GET $api/api/v1/sync/pull -> ${r.statusCode}';
    } catch (e) {
      result = 'GET $api/api/v1/sync/pull threw $e';
    }
    // ignore: avoid_print
    print('QA_NOTE:probe $result');
    if (host.isNotEmpty) await post('/note', utf8.encode('QA_NOTE:probe ${Platform.operatingSystemVersion} $result'));
    expect(result, endsWith('401'));
  });
}
