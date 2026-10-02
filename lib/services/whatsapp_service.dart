import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class WhatsAppService {
  final String phoneNumberId;
  final String accessToken;

  WhatsAppService({required this.phoneNumberId, required this.accessToken});

  bool get isConfigured => phoneNumberId.isNotEmpty && accessToken.isNotEmpty;

  /// Upload a PDF to WhatsApp media endpoint and return the media ID.
  Future<String?> _uploadMedia(Uint8List pdfBytes, String filename) async {
    if (!isConfigured) return null;
    final uri = Uri.parse(
        'https://graph.facebook.com/v19.0/$phoneNumberId/media');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['messaging_product'] = 'whatsapp'
      ..files.add(http.MultipartFile.fromBytes(
        'file', pdfBytes,
        filename: filename,
      ));
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) return null;
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['id'] as String?;
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

  /// Send a PDF invoice to a WhatsApp number via the Business API.
  /// Returns true on success.
  Future<bool> sendInvoicePdf({
    required String toPhone,
    required Uint8List pdfBytes,
    required String invoiceNo,
    required String storeName,
    required String customerName,
    required String amount,
    required String date,
    String docType = 'Invoice',
    String? invoiceLink,
  }) async {
    if (!isConfigured) return false;
    try {
      final mediaId = await _uploadMedia(pdfBytes, '$invoiceNo.pdf');
      if (mediaId == null) return false;

      final normalized = toPhone.replaceAll(RegExp(r'[^\d]'), '');
      final caption =
          'Hi $customerName, here is your $docType #$invoiceNo\n'
          'Amount: $amount | Date: $date\n'
          'From: $storeName'
          '${invoiceLink != null ? '\n$invoiceLink' : ''}';

      final uri = Uri.parse(
          'https://graph.facebook.com/v19.0/$phoneNumberId/messages');
      final res = await http.post(uri,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'messaging_product': 'whatsapp',
            'to': normalized,
            'type': 'document',
            'document': {
              'id': mediaId,
              'filename': '$invoiceNo.pdf',
              'caption': caption,
            },
          }));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
