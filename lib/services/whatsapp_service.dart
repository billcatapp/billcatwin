import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class WhatsAppService {
  final String phoneNumberId;
  final String accessToken;

  WhatsAppService({required this.phoneNumberId, required this.accessToken});

  bool get isConfigured => phoneNumberId.isNotEmpty && accessToken.isNotEmpty;

  /// Meta's own error text from the last failed e-bill send. Kept so a failure
  /// can say WHY — "send failed" alone gives the shopkeeper nothing to act on.
  String? lastError;

  // Without these a half-open connection never resolves: the send Future hangs
  // forever, no success or failure toast ever fires, and the bill is silently
  // lost. Upload gets longer — the PDF is bigger.
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _uploadTimeout = Duration(seconds: 45);
  static const Duration _sendTimeout = Duration(seconds: 30);

  /// Approved Utility template in WhatsApp Manager. A template can be sent
  /// outside the 24-hour customer-service window; a free-form document message
  /// cannot, so a walk-in customer who never messaged the shop only ever
  /// receives a template.
  static const _templateName = 'invoice_receipts';
  static const _templateLanguage = 'en';

  /// BillCat's own relay (Supabase function `whatsapp-send`), used by shops
  /// that have not brought their own Meta number. The WhatsApp token stays on
  /// the server: anything shipped in the app binary can be extracted and used
  /// to send from BillCat's number. Same relay the Mac app uses.
  static const _relayUrl =
      'https://xawpxbhglzhaibmcpwho.supabase.co/functions/v1/whatsapp-send';

  /// Meta rejects template parameters that are empty or carry newlines, tabs
  /// or runs of 4+ spaces, so every value is flattened before it is sent.
  static String _param(String value, {required String fallback}) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// Pulls the human-readable message out of a Graph API error body.
  static String _describe(int status, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'] as Map<String, dynamic>?;
      if (err != null) {
        final msg = (err['message'] ?? '').toString();
        final detail = (err['error_data'] is Map)
            ? ((err['error_data'] as Map)['details'] ?? '').toString()
            : '';
        final code = err['code']?.toString() ?? '$status';
        return detail.isNotEmpty ? '[$code] $detail' : '[$code] $msg';
      }
    } catch (_) {}
    return 'HTTP $status: ${body.length > 200 ? body.substring(0, 200) : body}';
  }

  static String _normalize(String phone) {
    // Strip spaces, dashes, parens; digits only, no leading 0.
    String p = phone.replaceAll(RegExp(r'[\s\-().+]'), '');
    if (p.startsWith('0')) p = p.substring(1);
    return p;
  }

  /// Sends a plain text message. Returns null on success, or the reason it
  /// failed so the caller can show it per recipient instead of a bare
  /// "didn't send".
  ///
  /// Meta only accepts free-form text inside the 24 hours after the customer
  /// last messaged this number. Outside that window it answers 131047 and the
  /// message must be a pre-approved template — which is the usual reason a
  /// send to a long customer list mostly fails.
  Future<String?> sendText({
    required String toPhone,
    required String message,
  }) async {
    if (!isConfigured) return 'WhatsApp is not configured';
    try {
      final normalized = toPhone.replaceAll(RegExp(r'[^\d]'), '');
      if (normalized.isEmpty) return 'No phone number';
      final res = await http.post(
        Uri.parse('https://graph.facebook.com/v19.0/$phoneNumberId/messages'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': normalized,
          'type': 'text',
          'text': {'preview_url': true, 'body': message},
        }),
      );
      if (res.statusCode == 200) return null;
      try {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        final e = err['error'] as Map<String, dynamic>?;
        final code = (e?['code'] as num?)?.toInt();
        if (code == 131047) {
          return 'Outside the 24-hour window — needs an approved template';
        }
        return (e?['message'] as String?) ?? 'HTTP ${res.statusCode}';
      } catch (_) {
        return 'HTTP ${res.statusCode}';
      }
    } catch (e) {
      return 'Could not reach WhatsApp';
    }
  }

  /// Sends an approved message template. Returns null on success, or the
  /// reason it failed in words a shopkeeper can act on.
  ///
  /// Templates are the only messages Meta delivers to someone who has not
  /// messaged this number in the last 24 hours, which is why a bulk send to
  /// a customer list must use one. [bodyParams] fill the template's body
  /// variables {{1}}, {{2}}, ... in order, so their count must match the
  /// template exactly. [toPhone] must already carry its country code.
  Future<String?> sendTemplate({
    required String toPhone,
    required String templateName,
    required String languageCode,
    List<String> bodyParams = const [],
  }) async {
    if (!isConfigured) return 'WhatsApp API is not set up';
    final normalized = toPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (normalized.isEmpty) return 'No phone number';
    try {
      final res = await http.post(
        Uri.parse('https://graph.facebook.com/v19.0/$phoneNumberId/messages'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': normalized,
          'type': 'template',
          'template': {
            'name': templateName,
            'language': {'code': languageCode},
            if (bodyParams.isNotEmpty)
              'components': [
                {
                  'type': 'body',
                  'parameters': [
                    for (final p in bodyParams) {'type': 'text', 'text': p},
                  ],
                },
              ],
          },
        }),
      );
      if (res.statusCode == 200) return null;
      try {
        final e = (jsonDecode(res.body) as Map<String, dynamic>)['error']
            as Map<String, dynamic>?;
        final code = (e?['code'] as num?)?.toInt();
        switch (code) {
          case 132001:
            return 'Template "$templateName" not found or not approved for '
                'language "$languageCode"';
          case 132000:
            return 'Template expects a different number of values';
          case 131026:
            return 'Not reachable on WhatsApp';
          case 190:
            return 'Access token expired — update it in Settings';
          case 131056:
            return 'Too many messages to this number — try later';
        }
        return (e?['message'] as String?) ?? 'HTTP ${res.statusCode}';
      } catch (_) {
        return 'HTTP ${res.statusCode}';
      }
    } catch (_) {
      return 'Could not reach WhatsApp';
    }
  }

  /// Uploads the PDF as a WhatsApp media object on the shop's own number;
  /// returns the media id, or null with [lastError] set.
  Future<String?> _uploadPdf(Uint8List pdfBytes, String filename) async {
    final uri = Uri.parse(
      'https://graph.facebook.com/v19.0/$phoneNumberId/media',
    );
    final boundary = 'BillCatBoundary${DateTime.now().millisecondsSinceEpoch}';
    final head = StringBuffer()
      ..write('--$boundary\r\n')
      ..write(
        'Content-Disposition: form-data; name="messaging_product"\r\n\r\n'
        'whatsapp\r\n',
      )
      ..write('--$boundary\r\n')
      ..write(
        'Content-Disposition: form-data; name="type"\r\n\r\n'
        'application/pdf\r\n',
      )
      ..write('--$boundary\r\n')
      ..write(
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n',
      )
      ..write('Content-Type: application/pdf\r\n\r\n');
    final headBytes = utf8.encode(head.toString());
    final footer = utf8.encode('\r\n--$boundary--\r\n');
    final multipart = Uint8List(
      headBytes.length + pdfBytes.length + footer.length,
    )
      ..setRange(0, headBytes.length, headBytes)
      ..setRange(headBytes.length, headBytes.length + pdfBytes.length, pdfBytes);
    multipart.setRange(
      headBytes.length + pdfBytes.length,
      multipart.length,
      footer,
    );

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final req = await client.postUrl(uri);
      req.headers.set('Authorization', 'Bearer $accessToken');
      req.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );
      req.headers.contentLength = multipart.length;
      req.add(multipart);
      final res = await req.close().timeout(_uploadTimeout);
      final respStr = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_uploadTimeout);
      // Status FIRST: a proxy or captive portal answers with HTML, and
      // parsing that would hide the real HTTP failure behind a Dart error.
      if (res.statusCode != 200) {
        lastError = 'PDF upload — ${_describe(res.statusCode, respStr)}';
        return null;
      }
      final decoded = jsonDecode(respStr);
      if (decoded is Map<String, dynamic> && decoded['id'] is String) {
        return decoded['id'] as String;
      }
      lastError = 'PDF upload — no media id in reply';
      return null;
    } on TimeoutException {
      lastError = 'PDF upload timed out — check the internet connection';
      return null;
    } catch (e) {
      lastError = 'PDF upload — $e';
      return null;
    } finally {
      // force: a hung socket must actually be torn down, not pooled.
      client.close(force: true);
    }
  }

  /// Posts [body] with Windows' own curl (System32\curl.exe) instead of
  /// Dart's HttpClient. Some mobile/hotspot connections corrupt Dart's TLS
  /// uploads above ~16 KB (connection reset, broken pipe) while the OS's own
  /// TLS gets through, and a bill PDF is a few hundred KB.
  ///
  /// Returns null when curl can't be used, or failed before anything reached
  /// the server — the caller then falls back to HttpClient. Any later failure
  /// is returned as an error and never retried, so a bill that did go out is
  /// not sent twice.
  static Future<({int status, String body, String? error})?>
  _postWithSystemCurl(String url, String bearer, List<int> body) async {
    if (!Platform.isWindows) return null;
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final curl = '$root\\System32\\curl.exe';
    if (!File(curl).existsSync()) return null;
    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('billcat_wa_');
      final bodyFile = File('${dir.path}${Platform.pathSeparator}bill.json');
      await bodyFile.writeAsBytes(body, flush: true);
      final proc = await Process.start(curl, [
        '--silent',
        '--show-error',
        '--connect-timeout', '10',
        '--max-time', '60',
        // The session token goes in on stdin, never on the command line
        // where any other process on the machine could read it.
        '--config', '-',
        '--header', 'Content-Type: application/json',
        '--data-binary', '@${bodyFile.path}',
        '--write-out', '\n%{http_code}',
        url,
      ]);
      final out = proc.stdout.transform(utf8.decoder).join();
      final err = proc.stderr.transform(utf8.decoder).join();
      proc.stdin.write('header = "Authorization: Bearer $bearer"\n');
      await proc.stdin.close();
      final code = await proc.exitCode.timeout(
        const Duration(seconds: 75),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );
      final text = await out;
      if (code == -1 || code == 28) {
        return (
          status: 0,
          body: '',
          error: 'WhatsApp timed out — check the internet connection',
        );
      }
      if (code != 0) {
        // Failed before the request reached the server: bad init/URL, DNS,
        // connect, TLS handshake or certificate. Safe to retry another way.
        const notSent = {1, 2, 3, 5, 6, 7, 35, 60, 77};
        if (notSent.contains(code)) return null;
        return (
          status: 0,
          body: '',
          error:
              'WhatsApp relay — network error (curl $code: '
              '${(await err).trim()})',
        );
      }
      final nl = text.lastIndexOf('\n');
      return (
        status: int.tryParse(text.substring(nl + 1).trim()) ?? 0,
        body: nl < 0 ? '' : text.substring(0, nl),
        error: null,
      );
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Sends through BillCat's relay. The shop's Supabase session identifies it
  /// to the server, which applies the daily cap and holds the WhatsApp token.
  Future<bool> _sendViaRelay(Map<String, dynamic> payload) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      lastError = 'Sign in to send bills on WhatsApp.';
      return false;
    }
    final bytes = utf8.encode(jsonEncode(payload));
    // First choice: the OS's own curl (see _postWithSystemCurl). HttpClient
    // below is only the fallback for when curl can't be used.
    final viaCurl = await _postWithSystemCurl(
      _relayUrl,
      session.accessToken,
      bytes,
    );
    if (viaCurl != null) {
      if (viaCurl.error != null) {
        lastError = viaCurl.error;
        return false;
      }
      if (viaCurl.status == 200) return true;
      try {
        lastError = (jsonDecode(viaCurl.body) as Map<String, dynamic>)['error']
            ?.toString();
      } catch (_) {
        lastError = 'HTTP ${viaCurl.status}';
      }
      return false;
    }
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final req = await client.postUrl(Uri.parse(_relayUrl));
      req.headers.set('Authorization', 'Bearer ${session.accessToken}');
      req.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(_uploadTimeout);
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_uploadTimeout);
      if (res.statusCode == 200) return true;
      try {
        lastError = (jsonDecode(body) as Map<String, dynamic>)['error']
            ?.toString();
      } catch (_) {
        lastError = 'HTTP ${res.statusCode}';
      }
      return false;
    } on TimeoutException {
      lastError = 'WhatsApp timed out — check the internet connection';
      return false;
    } catch (e) {
      lastError = 'WhatsApp relay — $e';
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Sends a bill PDF on WhatsApp with the approved `invoice_receipts`
  /// template, so it reaches a customer who has never messaged the shop.
  /// Returns true on success; on failure [lastError] says why.
  ///
  /// A shop with its own Meta number in Settings sends from it directly.
  /// Every other shop goes through BillCat's relay, from BillCat's number,
  /// with no credentials in the app. The PDF is the template's header and
  /// the six body values follow {{1}}..{{6}} in the approved text exactly.
  Future<bool> sendInvoicePdf({
    required String toPhone,
    required Uint8List pdfBytes,
    required String invoiceNo,
    required String storeName,
    required String customerName,
    required String amount,
    required String date,
    String docType = 'Invoice',
    // Not part of the approved template; kept so callers are unchanged.
    String? invoiceLink,
    String dialCode = '91',
    // The shop's WhatsApp group invite link. Sent to the relay, which adds a
    // "Join our WhatsApp group" button under View Bill when it has one. A
    // relay that does not know the field ignores it.
    String groupLink = '',
  }) async {
    lastError = null;
    final phone = _normalize(toPhone);
    if (phone.isEmpty) {
      lastError = 'No customer phone number';
      return false;
    }

    if (!isConfigured) {
      return _sendViaRelay({
        'toPhone': toPhone,
        'dialCode': dialCode,
        'pdfBase64': base64Encode(pdfBytes),
        'invoiceNo': invoiceNo,
        'storeName': storeName,
        'customerName': customerName,
        'amount': amount,
        'date': date,
        'docType': docType,
        if (groupLink.trim().isNotEmpty) 'groupLink': groupLink.trim(),
      });
    }

    final mediaId = await _uploadPdf(pdfBytes, '$docType-$invoiceNo.pdf');
    if (mediaId == null) return false;

    final payload = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': phone,
      'type': 'template',
      'template': {
        'name': _templateName,
        'language': {'code': _templateLanguage},
        'components': [
          {
            'type': 'header',
            'parameters': [
              {
                'type': 'document',
                'document': {'id': mediaId, 'filename': '$docType-$invoiceNo.pdf'},
              },
            ],
          },
          {
            'type': 'body',
            'parameters': [
              {
                'type': 'text',
                'text': _param(customerName, fallback: 'Valued Customer'),
              },
              {'type': 'text', 'text': _param(storeName, fallback: 'BillCat')},
              {'type': 'text', 'text': _param(docType, fallback: 'Invoice')},
              {'type': 'text', 'text': _param(invoiceNo, fallback: '-')},
              {'type': 'text', 'text': _param(amount, fallback: '-')},
              {'type': 'text', 'text': _param(date, fallback: '-')},
            ],
          },
        ],
      },
    });

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final req = await client.postUrl(
        Uri.parse('https://graph.facebook.com/v19.0/$phoneNumberId/messages'),
      );
      req.headers.set('Authorization', 'Bearer $accessToken');
      // Explicit UTF-8: the amount carries ₹, which dart:io's latin1 default
      // cannot encode.
      req.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      final bytes = utf8.encode(payload);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(_sendTimeout);
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_sendTimeout);
      if (res.statusCode == 200) return true;
      lastError = _describe(res.statusCode, body);
      return false;
    } on TimeoutException {
      lastError = 'WhatsApp timed out — check the internet connection';
      return false;
    } catch (e) {
      lastError = '$e';
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
