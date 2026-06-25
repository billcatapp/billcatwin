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
