import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  static Future<bool> emailExists(String email) async {
    final result = await client.rpc(
      'check_email_exists',
      params: {'email_to_check': email.trim().toLowerCase()},
    );
    return result as bool;
  }

  static Future<void> signInWithPhone(String phone) async {
    await client.auth.signInWithOtp(phone: phone.trim());
  }

  static Future<void> verifyPhoneOtp(String phone, String token) async {
    await client.auth.verifyOTP(
      phone: phone.trim(),
      token: token.trim(),
      type: OtpType.sms,
    );
  }

  static Future<void> resendPhoneOtp(String phone) async {
    await client.auth.resend(
      type: OtpType.sms,
      phone: phone.trim(),
    );
  }

  static Future<void> signInWithGoogle() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'billcat://login-callback',
    );
  }

  static Future<void> verifyOtp(String email, String token) async {
    await client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: OtpType.signup,
    );
  }

  static Future<void> resendOtp(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;
}
