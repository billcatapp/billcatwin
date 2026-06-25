import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_colors.dart';
import '../../services/supabase_service.dart';
import 'complete_profile_screen.dart';
import 'login_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String? email;
  final String? phone;
  const OtpVerificationScreen({super.key, this.email, this.phone})
      : assert(email != null || phone != null,
            'Either email or phone must be provided');

  bool get isPhone => phone != null;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _ctrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focus = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _canResend = false;
  int _countdown = 60;
  Timer? _timer;

  static const _navy = Color(0xFF1B2B4B);
  static const _bg = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    for (final c in _ctrl) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _canResend = true;
          t.cancel();
        }
      });
    });
  }

  String get _otpCode => _ctrl.map((c) => c.text).join();

  void _verify() async {
    final code = _otpCode;
    if (code.length < 6) {
      _showError('Please enter the complete 6-digit code.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (widget.isPhone) {
        await SupabaseService.verifyPhoneOtp(widget.phone!, code);
      } else {
        await SupabaseService.verifyOtp(widget.email!, code);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      _showError(e.message.contains('expired') || e.message.contains('invalid')
          ? 'Invalid or expired code. Please try again.'
          : e.message);
      _clearBoxes();
    } catch (_) {
      _showError('Verification failed. Please try again.');
      _clearBoxes();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resend() async {
    if (!_canResend) return;
    try {
      if (widget.isPhone) {
        await SupabaseService.resendPhoneOtp(widget.phone!);
      } else {
        await SupabaseService.resendOtp(widget.email!);
      }
      _startCountdown();
      _clearBoxes();
      if (!mounted) return;
      final dest = widget.isPhone ? widget.phone! : widget.email!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code resent to $dest',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (_) {
      _showError('Could not resend code. Please try again.');
    }
  }

  void _clearBoxes() {
    for (final c in _ctrl) {
      c.clear();
    }
    _focus[0].requestFocus();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Bottom status bar
          Positioned(
            bottom: 28,
            left: 36,
            right: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 24, height: 1, color: const Color(0xFFCBD5E1)),
                    const SizedBox(width: 10),
                    Text('SYSTEM SECURE (SSL-256)',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFCBD5E1),
                          letterSpacing: 1.5,
                        )),
                  ],
                ),
                Text('BILLCAT TERMINAL V1.0.0',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFCBD5E1),
                      letterSpacing: 1.5,
                    )),
              ],
            ),
          ),
          // Main content
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Text('BillCat',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      )),
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Card
                  Container(
                    width: 440,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 44),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text('Verification',
                            style: GoogleFonts.manrope(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            )),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF64748B),
                              height: 1.6,
                            ),
                            children: [
                              TextSpan(
                                  text: widget.isPhone
                                      ? "We've sent a 6-digit code via SMS to\n"
                                      : "We've sent a 6-digit code to your email\n"),
                              TextSpan(
                                  text: widget.isPhone
                                      ? widget.phone!
                                      : widget.email!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _navy,
                                  )),
                              const TextSpan(
                                  text: '. Enter it below to continue.'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 36),
                        // OTP boxes
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (i) {
                            return Padding(
                              padding:
                                  EdgeInsets.only(right: i < 5 ? 8 : 0),
                              child: _digitBox(i),
                            );
                          }),
                        ),
                        const SizedBox(height: 32),
                        // Verify button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verify,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _navy,
                              disabledBackgroundColor:
                                  _navy.withValues(alpha: 0.6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5))
                                : Text('Verify & Continue',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    )),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Resend row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Didn't receive the code?  ",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: const Color(0xFF94A3B8),
                                )),
                            GestureDetector(
                              onTap: _canResend ? _resend : null,
                              child: Text('Resend Code',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _canResend
                                        ? _navy
                                        : const Color(0xFFCBD5E1),
                                  )),
                            ),
                          ],
                        ),
                        if (!_canResend) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    size: 13,
                                    color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  'Resend code in 0:${_countdown.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Change Email / Number
                  GestureDetector(
                    onTap: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                      (route) => false,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isPhone
                              ? Icons.phone_outlined
                              : Icons.alternate_email_rounded,
                          size: 14,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isPhone ? 'Change Number' : 'Change Email',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _digitBox(int index) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _ctrl[index].text.isEmpty &&
            index > 0) {
          _focus[index - 1].requestFocus();
          _ctrl[index - 1].clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: 46,
        height: 56,
        child: TextField(
          controller: _ctrl[index],
          focusNode: _focus[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.manrope(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1B2B4B),
          ),
          onChanged: (v) {
            if (v.isNotEmpty) {
              if (index < 5) {
                _focus[index + 1].requestFocus();
              } else {
                _focus[index].unfocus();
                _verify();
              }
            }
          },
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: _ctrl[index].text.isNotEmpty
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF1B2B4B), width: 1.8),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
