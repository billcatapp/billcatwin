import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum _WaState { loading, qr, ready, navigating, sending, sent, error }

class WhatsAppPanel extends StatefulWidget {
  final String? customerPhone;
  final String? customerName;
  final Future<Uint8List> Function()? buildPdf;
  final String? pdfName;

  const WhatsAppPanel({
    super.key,
    this.customerPhone,
    this.customerName,
    this.buildPdf,
    this.pdfName,
  });

  @override
  State<WhatsAppPanel> createState() => _WhatsAppPanelState();
}

class _WhatsAppPanelState extends State<WhatsAppPanel> {
  late final WebViewController _wvc;
  _WaState _state = _WaState.loading;
  String _statusMsg = 'Loading WhatsApp...';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/122.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPageFinished,
      ))
      ..loadRequest(
        Uri.parse('https://web.whatsapp.com'),
        headers: {'Accept-Language': 'en-US,en;q=0.9'},
      );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _onPageFinished(String url) async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await _detectState();
  }

  Future<void> _detectState() async {
    final result = await _wvc.runJavaScriptReturningResult('''
      (function() {
        if (document.querySelector('[data-ref]') ||
            document.querySelector('canvas[aria-label]')) return 'qr';
        if (document.querySelector('[data-testid="chat-list"]') ||
            document.querySelector('[aria-label="Chat list"]') ||
            document.querySelector('#side')) return 'ready';
        return 'loading';
      })()
    ''');

    final s = result.toString().replaceAll('"', '');
    if (!mounted) return;

    if (s == 'qr') {
      setState(() { _state = _WaState.qr; _statusMsg = 'Scan QR code with your phone'; });
      _startQrPoll();
    } else if (s == 'ready') {
      setState(() { _state = _WaState.ready; });
      _setReadyStatus();
      if (widget.customerPhone != null) await _navigateToChat();
    } else {
      setState(() { _state = _WaState.loading; _statusMsg = 'Loading...'; });
      _pollTimer?.cancel();
      _pollTimer = Timer(const Duration(seconds: 3), _detectState);
    }
  }

  void _setReadyStatus() {
    if (!mounted) return;
    setState(() {
      _statusMsg = widget.customerPhone != null
          ? 'Ready · ${widget.customerName ?? widget.customerPhone}'
          : 'Connected';
    });
  }

  void _startQrPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) { _pollTimer?.cancel(); return; }
      final result = await _wvc.runJavaScriptReturningResult('''
        (function() {
          if (document.querySelector('[data-testid="chat-list"]') ||
              document.querySelector('#side')) return 'ready';
          return 'waiting';
        })()
      ''');
      if (result.toString().contains('ready')) {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() { _state = _WaState.ready; });
        _setReadyStatus();
        if (widget.customerPhone != null) await _navigateToChat();
      }
    });
  }

  Future<void> _navigateToChat() async {
    if (widget.customerPhone == null) return;
    final raw = widget.customerPhone!.replaceAll(RegExp(r'[^\d]'), '');
    final phone = raw.length == 10 ? '91$raw' : raw;
    setState(() { _state = _WaState.navigating; _statusMsg = 'Opening chat...'; });
    await _wvc.loadRequest(
      Uri.parse('https://web.whatsapp.com/send?phone=$phone'),
      headers: {'Accept-Language': 'en-US,en;q=0.9'},
    );
  }

  Future<void> _sendBill() async {
    if (widget.buildPdf == null) return;
    setState(() { _state = _WaState.sending; _statusMsg = 'Generating bill PDF...'; });

    try {
      final pdfBytes = await widget.buildPdf!();
      final tmpDir = await Directory.systemTemp.createTemp('billcat_wa_');
      final name = (widget.pdfName ?? 'Bill').replaceAll(RegExp(r'[^\w\-]'), '_');
      final pdfFile = File('${tmpDir.path}/$name.pdf');
      await pdfFile.writeAsBytes(pdfBytes);

      setState(() { _statusMsg = 'Attaching bill...'; });

      if (Platform.isWindows) {
        // Set the PDF file to the Windows clipboard as a file drop list via PowerShell
        final ps1 = pdfFile.path.replaceAll(r'\', r'\\');
        await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Add-Type -AssemblyName System.Windows.Forms;'
          r'$files = New-Object System.Collections.Specialized.StringCollection;'
          '\$files.Add("$ps1");'
          r'[System.Windows.Forms.Clipboard]::SetFileDropList($files);'
          r'Start-Sleep -Milliseconds 400;'
          r'Add-Type -AssemblyName System.Windows.Forms;'
          r'[System.Windows.Forms.SendKeys]::SendWait("^v");',
        ]);
      } else {
        // macOS: set clipboard as a POSIX file reference, then Cmd+V
        final esc = pdfFile.path.replaceAll("'", "'\\''");
        await Process.run('osascript', ['-e', "set the clipboard to POSIX file '$esc'"]);
        await Future.delayed(const Duration(milliseconds: 600));
        await Process.run('osascript', ['-e',
          'tell application "System Events" to keystroke "v" using command down']);
      }
      await Future.delayed(const Duration(seconds: 2));

      // Click the send button via JS
      await _wvc.runJavaScript('''
        (function() {
          const sendSelectors = [
            '[data-testid="send"]',
            'button[aria-label="Send"]',
            'span[data-icon="send"]',
          ];
          for (const sel of sendSelectors) {
            const el = document.querySelector(sel);
            if (el) { el.click(); return; }
          }
          // Fallback: press Enter on the compose box
          const input = document.querySelector(
            '[data-testid="conversation-compose-box-input"]'
          ) || document.querySelector('[contenteditable="true"][data-tab="10"]');
          if (input) {
            input.dispatchEvent(new KeyboardEvent('keydown',
              {key:'Enter', keyCode:13, bubbles:true}));
          }
        })()
      ''');

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() { _state = _WaState.sent; _statusMsg = 'Bill sent!'; });
    } catch (e) {
      if (mounted) setState(() { _state = _WaState.error; _statusMsg = 'Error: $e'; });
    }
  }

  bool get _canSend =>
      (_state == _WaState.ready || _state == _WaState.navigating) &&
      widget.buildPdf != null &&
      widget.customerPhone != null;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 920,
          height: 640,
          child: Column(children: [
            _buildTopBar(),
            Expanded(child: WebViewWidget(controller: _wvc)),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    const green = Color(0xFF00A884);
    final isBusy = _state == _WaState.loading ||
        _state == _WaState.navigating ||
        _state == _WaState.sending;

    return Container(
      height: 54,
      color: green,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Text('WhatsApp',
            style: GoogleFonts.inter(
                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(width: 12),
        // Status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isBusy)
              const SizedBox(
                width: 9, height: 9,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else if (_state == _WaState.qr)
              const Icon(Icons.qr_code_2_rounded, size: 12, color: Colors.white)
            else if (_state == _WaState.sent)
              const Icon(Icons.check_circle_rounded, size: 12, color: Colors.white)
            else if (_state == _WaState.error)
              const Icon(Icons.error_outline_rounded, size: 12, color: Colors.white)
            else
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(_statusMsg,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        const Spacer(),
        if (_canSend || _state == _WaState.sent)
          TextButton.icon(
            onPressed: (_state == _WaState.sent || _state == _WaState.sending)
                ? null
                : _sendBill,
            icon: Icon(
              _state == _WaState.sent
                  ? Icons.check_circle_outline_rounded
                  : Icons.send_rounded,
              size: 15,
              color: Colors.white,
            ),
            label: Text(
              _state == _WaState.sent ? 'Sent!' : 'Send Bill',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
          style: IconButton.styleFrom(padding: const EdgeInsets.all(6)),
        ),
      ]),
    );
  }
}
