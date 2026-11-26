import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/app_colors.dart';
import '../../services/supabase_service.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// The reset email carries a 6-digit code; it is entered on the next
  /// screen, which then leads on to setting the new password.
  void _goToCode() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          email: _emailController.text.trim().toLowerCase(),
          passwordReset: true,
        ),
      ),
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final exists = await SupabaseService.emailExists(_emailController.text);
      if (!exists) {
        _showError('No account found with this email.');
        return;
      }
      await SupabaseService.resetPassword(_emailController.text);
      _goToCode();
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      // If RPC not set up, try sending reset anyway
      try {
        await SupabaseService.resetPassword(_emailController.text);
        _goToCode();
      } catch (e) {
        _showError('Failed to send reset email. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left panel
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.lock_reset_rounded,
                          size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text('Reset Password',
                        style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        )),
                    const SizedBox(height: 8),
                    Text("We'll email you a reset code",
                        style: GoogleFonts.inter(
                            fontSize: 15, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
          // Right panel
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildFormState(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Forgot password?',
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              )),
          const SizedBox(height: 8),
          Text('Enter your email and we\'ll send you a 6-digit code.',
              style: GoogleFonts.inter(
                  color: AppColors.textMuted, fontSize: 15, fontWeight: FontWeight.w300)),
          const SizedBox(height: 36),
          Text('Email',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            validator: (v) =>
                v != null && v.contains('@') ? null : 'Enter a valid email',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle:
                  GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
              prefixIcon: const Icon(Icons.email_outlined,
                  color: AppColors.textMuted, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Send Code',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text('← Back to Sign In',
                  style: GoogleFonts.inter(
                      color: AppColors.accentBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }
}
