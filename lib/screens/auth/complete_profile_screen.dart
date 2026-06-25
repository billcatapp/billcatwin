import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../billing/billing_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _bizCtrl    = TextEditingController();
  final _ownerCtrl  = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _addrCtrl   = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _postalCtrl = TextEditingController();

  String  _country     = 'India';
  String  _countryCode = '+91';
  String  _countryFlag = '🇮🇳';
  String  _currency    = 'INR';
  String? _logoPath;
  bool    _isLoading   = false;

  static const _navy  = Color(0xFF1B2B4B);
  static const _navyD = Color(0xFF0F1E35);
  static const _blue  = Color(0xFF3B82F6);
  static const _bdr   = Color(0xFFE2E8F0);
  static const _hint  = Color(0xFFCBD5E1);
  static const _muted = Color(0xFF94A3B8);
  static const _dark  = Color(0xFF0F172A);
  static const _sub   = Color(0xFF64748B);
  static const _bg    = Color(0xFFF8FAFC);

  static const _codes = [
    (flag:'🇮🇳', code:'+91',  name:'India'),
    (flag:'🇺🇸', code:'+1',   name:'United States'),
    (flag:'🇬🇧', code:'+44',  name:'United Kingdom'),
    (flag:'🇦🇪', code:'+971', name:'UAE'),
    (flag:'🇸🇬', code:'+65',  name:'Singapore'),
    (flag:'🇦🇺', code:'+61',  name:'Australia'),
    (flag:'🇨🇦', code:'+1',   name:'Canada'),
    (flag:'🇩🇪', code:'+49',  name:'Germany'),
    (flag:'🇫🇷', code:'+33',  name:'France'),
    (flag:'🇯🇵', code:'+81',  name:'Japan'),
    (flag:'🇧🇷', code:'+55',  name:'Brazil'),
    (flag:'🇵🇰', code:'+92',  name:'Pakistan'),
    (flag:'🇧🇩', code:'+880', name:'Bangladesh'),
    (flag:'🇸🇦', code:'+966', name:'Saudi Arabia'),
    (flag:'🇲🇾', code:'+60',  name:'Malaysia'),
  ];

  static const _countryList = [
    'India','United States','United Kingdom','UAE','Singapore',
    'Australia','Canada','Germany','France','Japan','Brazil',
    'Pakistan','Bangladesh','Saudi Arabia','Malaysia',
  ];

  static const _currencies = [
    (sym:'₹',   code:'INR', name:'Indian Rupee'),
    (sym:'\$',  code:'USD', name:'US Dollar'),
    (sym:'€',   code:'EUR', name:'Euro'),
    (sym:'£',   code:'GBP', name:'British Pound'),
    (sym:'د.إ', code:'AED', name:'UAE Dirham'),
    (sym:'S\$', code:'SGD', name:'Singapore Dollar'),
    (sym:'A\$', code:'AUD', name:'Australian Dollar'),
    (sym:'C\$', code:'CAD', name:'Canadian Dollar'),
    (sym:'¥',   code:'JPY', name:'Japanese Yen'),
    (sym:'R\$', code:'BRL', name:'Brazilian Real'),
  ];

  @override
  void dispose() {
    for (final c in [_bizCtrl,_ownerCtrl,_emailCtrl,_phoneCtrl,_addrCtrl,_cityCtrl,_postalCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r?.files.single.path != null) {
      setState(() => _logoPath = r!.files.single.path);
    }
  }

  void _next() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      String? logoUrl;
      if (_logoPath != null && userId != null) {
        try {
          final bytes = await File(_logoPath!).readAsBytes();
          final ext   = _logoPath!.split('.').last.toLowerCase();
          await client.storage.from('logos').uploadBinary(
            '$userId.$ext', bytes,
            fileOptions: const FileOptions(upsert: true),
          );
          logoUrl = client.storage.from('logos').getPublicUrl('$userId.$ext');
        } catch (_) {}
      }

      await client.auth.updateUser(UserAttributes(data: {
        'business_name': _bizCtrl.text.trim(),
        'owner_name':    _ownerCtrl.text.trim(),
        'work_email':    _emailCtrl.text.trim(),
        'phone':         '$_countryCode ${_phoneCtrl.text.trim()}',
        'address':       _addrCtrl.text.trim(),
        'city':          _cityCtrl.text.trim(),
        'country':       _country,
        'postal_code':   _postalCtrl.text.trim(),
        'currency':      _currency,
        if (logoUrl != null) 'logo_url': logoUrl,
      }));
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const BillingScreen()), (_) => false);
  }

  void _pickCode() async {
    final i = await showDialog<int>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20,20,20,12),
            child: Text('Country Code', style: GoogleFonts.manrope(
                fontSize: 15, fontWeight: FontWeight.w700, color: _dark)),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.builder(
              shrinkWrap: true, itemCount: _codes.length,
              itemBuilder: (_, i) {
                final c = _codes[i];
                final sel = _countryCode == c.code && _countryFlag == c.flag;
                return ListTile(
                  dense: true,
                  leading: Text(c.flag, style: const TextStyle(fontSize: 20)),
                  title: Text('${c.name}  ${c.code}',
                      style: GoogleFonts.inter(fontSize: 13,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: sel ? _navy : const Color(0xFF334155))),
                  trailing: sel ? Container(width: 8, height: 8,
                      decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)) : null,
                  onTap: () => Navigator.pop(context, i),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ])),
      ),
    );
    if (i != null) setState(() {
      _countryCode = _codes[i].code;
      _countryFlag = _codes[i].flag;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(children: [
        // ── Left panel ──────────────────────────────────────────────────────
        SizedBox(
          width: 280,
          child: Container(
            color: _navyD,
            child: Stack(children: [
              Positioned(bottom: -80, right: -80,
                child: Container(width: 280, height: 280,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.03)))),
              Positioned(top: 100, left: -60,
                child: Container(width: 200, height: 200,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.025)))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 0),
                  child: Row(children: [
                    Container(width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7)),
                      child: const Icon(Icons.point_of_sale_rounded,
                          color: Colors.white, size: 16)),
                    const SizedBox(width: 10),
                    Text('BillCat', style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 56),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('One last\nstep.', style: GoogleFonts.manrope(
                        fontSize: 32, fontWeight: FontWeight.w800,
                        color: Colors.white, height: 1.15)),
                    const SizedBox(height: 14),
                    Text('Set up your business profile to personalise your workspace.',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w300,
                            color: Colors.white54, height: 1.65)),
                  ]),
                ),
                const SizedBox(height: 44),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(children: [
                    _step('1', 'Create Account', done: true),
                    _stepLine(),
                    _step('2', 'Business Profile', active: true),
                    _stepLine(),
                    _step('3', 'Start Billing', dim: true),
                  ]),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: Text('Your data is encrypted\nand stored securely.',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w300,
                          color: Colors.white24, height: 1.6)),
                ),
              ]),
            ]),
          ),
        ),

        // ── Right panel ──────────────────────────────────────────────────────
        Expanded(
          child: Container(
            color: _bg,
            child: Form(
              key: _formKey,
              child: Column(children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(44, 40, 44, 24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Complete Your Profile',
                          style: GoogleFonts.manrope(fontSize: 21,
                              fontWeight: FontWeight.w800, color: _dark)),
                      const SizedBox(height: 3),
                      Text('Fill in your business details to get started.',
                          style: GoogleFonts.inter(fontSize: 13, color: _sub)),
                      const SizedBox(height: 24),

                      // ── Business Profile ────────────────────────────────
                      _card(
                        icon: Icons.storefront_outlined,
                        title: 'Business Profile',
                        child: Column(children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                            // Circular profile pic
                            Column(children: [
                              GestureDetector(
                                onTap: _pickLogo,
                                child: Stack(children: [
                                  Container(
                                    width: 76, height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _logoPath != null ? Colors.transparent : _navy,
                                      border: Border.all(
                                          color: _logoPath != null ? _bdr : Colors.transparent,
                                          width: 2),
                                      boxShadow: [BoxShadow(
                                          color: _navy.withValues(alpha: 0.18),
                                          blurRadius: 10, offset: const Offset(0, 3))],
                                      image: _logoPath != null
                                          ? DecorationImage(
                                              image: FileImage(File(_logoPath!)),
                                              fit: BoxFit.cover)
                                          : null,
                                    ),
                                    child: _logoPath == null
                                        ? const Icon(Icons.storefront_outlined,
                                            color: Colors.white, size: 28)
                                        : null,
                                  ),
                                  Positioned(right: 0, bottom: 0,
                                    child: Container(
                                      width: 22, height: 22,
                                      decoration: BoxDecoration(
                                        color: _navy, shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 1.5)),
                                      child: const Icon(Icons.camera_alt_rounded,
                                          color: Colors.white, size: 11),
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 6),
                              Text('Logo', style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: _sub)),
                            ]),
                            const SizedBox(width: 20),
                            Expanded(child: Row(children: [
                              Expanded(child: _field('Business Name', _bizCtrl,
                                  hint: 'Acme Corp.',
                                  validator: (v) => v!.trim().isEmpty ? 'Required' : null)),
                              const SizedBox(width: 12),
                              Expanded(child: _field('Owner Name', _ownerCtrl,
                                  hint: 'John Doe')),
                            ])),
                          ]),
                          const SizedBox(height: 14),
                          _field('Work Email', _emailCtrl,
                              hint: 'billing@yourcompany.com',
                              icon: Icons.alternate_email_rounded,
                              validator: (v) => v!.isNotEmpty && !v.contains('@')
                                  ? 'Invalid email' : null),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // ── Location ─────────────────────────────────────────
                      _card(
                        icon: Icons.location_on_outlined,
                        title: 'Location',
                        child: Column(children: [
                          // Phone + Street Address
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _lbl('Phone Number'),
                                const SizedBox(height: 6),
                                Row(children: [
                                  GestureDetector(
                                    onTap: _pickCode,
                                    child: Container(
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: _bdr),
                                        borderRadius: BorderRadius.circular(8)),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Text(_countryFlag,
                                            style: const TextStyle(fontSize: 16)),
                                        const SizedBox(width: 5),
                                        Text(_countryCode,
                                            style: GoogleFonts.inter(fontSize: 13,
                                                fontWeight: FontWeight.w600, color: _dark)),
                                        const SizedBox(width: 3),
                                        const Icon(Icons.keyboard_arrow_down_rounded,
                                            size: 13, color: _muted),
                                      ]),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: SizedBox(
                                    height: 42,
                                    child: TextFormField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(12),
                                      ],
                                      style: GoogleFonts.inter(fontSize: 13, color: _dark),
                                      decoration: _dec('98765 00000'),
                                    ),
                                  )),
                                ]),
                              ],
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: _field('Street Address', _addrCtrl,
                                hint: '123 Main Street, Ste 400')),
                          ]),
                          const SizedBox(height: 12),
                          // City + Country
                          Row(children: [
                            Expanded(child: _field('City', _cityCtrl, hint: 'Mumbai')),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _lbl('Country'),
                                const SizedBox(height: 6),
                                _drop<String>(
                                  value: _country,
                                  items: _countryList,
                                  display: (c) => c,
                                  onChange: (v) => setState(() => _country = v!),
                                ),
                              ],
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: _field('Postal Code', _postalCtrl,
                                hint: '110001',
                                formatters: [FilteringTextInputFormatter.digitsOnly])),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // ── Currency ─────────────────────────────────────────
                      _card(
                        icon: Icons.currency_exchange_rounded,
                        title: 'Currency',
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _lbl('Operational Currency'),
                          const SizedBox(height: 6),
                          _drop<String>(
                            value: _currency,
                            items: _currencies.map((c) => c.code).toList(),
                            display: (code) {
                              final c = _currencies.firstWhere((x) => x.code == code);
                              return '${c.sym}  ${c.code} — ${c.name}';
                            },
                            onChange: (v) => setState(() => _currency = v!),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 28),
                    ]),
                  ),
                ),

                // ── Bottom bar ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded, size: 12, color: _muted),
                    const SizedBox(width: 6),
                    Text('Data is encrypted and stored securely.',
                        style: GoogleFonts.inter(fontSize: 11, color: _muted)),
                    const Spacer(),
                    SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          disabledBackgroundColor: _navy.withValues(alpha: 0.6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('Next', style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, size: 15),
                              ]),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _step(String num, String label, {bool done=false, bool active=false, bool dim=false}) =>
    Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? _blue : active
              ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: done ? _blue : active
              ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Center(child: done
            ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
            : Text(num, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.white38))),
      ),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.inter(fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? Colors.white : dim ? Colors.white24 : Colors.white54)),
    ]);

  Widget _stepLine() => Padding(
    padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    child: Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.1)));

  Widget _card({required IconData icon, required String title, required Widget child}) =>
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bdr),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 14, color: _navy)),
          const SizedBox(width: 10),
          Text(title, style: GoogleFonts.manrope(fontSize: 13,
              fontWeight: FontWeight.w700, color: _dark)),
        ]),
        const SizedBox(height: 18),
        child,
      ]),
    );

  Widget _lbl(String t) => Text(t, style: GoogleFonts.inter(
      fontSize: 11, fontWeight: FontWeight.w500, color: _sub));

  Widget _field(String label, TextEditingController ctrl, {
    String hint = '', IconData? icon,
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _lbl(label),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, validator: validator,
        inputFormatters: formatters,
        style: GoogleFonts.inter(fontSize: 13, color: _dark),
        decoration: _dec(hint, icon: icon)),
  ]);

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: _hint, fontSize: 13),
    prefixIcon: icon != null ? Icon(icon, size: 15, color: _muted) : null,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _bdr)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _bdr)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _navy, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444))),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
  );

  Widget _drop<T>({required T value, required List<T> items,
    required String Function(T) display, required void Function(T?) onChange}) =>
    Container(
      height: 42,
      decoration: BoxDecoration(color: Colors.white,
          border: Border.all(color: _bdr), borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: _muted),
          style: GoogleFonts.inter(fontSize: 13, color: _dark),
          items: items.map((i) => DropdownMenuItem<T>(value: i,
              child: Text(display(i),
                  style: GoogleFonts.inter(fontSize: 13, color: _dark)))).toList(),
          onChanged: onChange,
        ),
      ),
    );
}
