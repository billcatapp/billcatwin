import 'dart:async';
import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import 'package:uuid/uuid.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/product_variant.dart';
import '../../models/transaction_record.dart';
import '../../providers/cart_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/label_printer.dart';
import '../../services/local_db_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/update_service.dart';
import 'package:printing/printing.dart' show Printer, Printing, PdfPreview;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart' as bc;
import '../../services/receipt_printer.dart';
import '../../services/thermal_logo.dart';
import '../../services/thermal_printer.dart';
import '../../services/whatsapp_service.dart' as _wa;
import '../auth/login_screen.dart';

const _defaultProducts = <Product>[];

// ── Currency data ────────────────────────────────────────────────────────────

typedef _Currency = ({String flag, String code, String name, String symbol});

const List<_Currency> _currencies = [
  (flag: '🇮🇳', code: 'INR', name: 'Indian Rupee', symbol: '₹'),
  (flag: '🇺🇸', code: 'USD', name: 'US Dollar', symbol: '\$'),
  (flag: '🇪🇺', code: 'EUR', name: 'Euro', symbol: '€'),
  (flag: '🇬🇧', code: 'GBP', name: 'British Pound', symbol: '£'),
  (flag: '🇯🇵', code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
  (flag: '🇨🇳', code: 'CNY', name: 'Chinese Yuan', symbol: '¥'),
  (flag: '🇦🇺', code: 'AUD', name: 'Australian Dollar', symbol: 'A\$'),
  (flag: '🇨🇦', code: 'CAD', name: 'Canadian Dollar', symbol: 'C\$'),
  (flag: '🇨🇭', code: 'CHF', name: 'Swiss Franc', symbol: 'Fr'),
  (flag: '🇸🇬', code: 'SGD', name: 'Singapore Dollar', symbol: 'S\$'),
  (flag: '🇭🇰', code: 'HKD', name: 'Hong Kong Dollar', symbol: 'HK\$'),
  (flag: '🇳🇿', code: 'NZD', name: 'New Zealand Dollar', symbol: 'NZ\$'),
  (flag: '🇰🇷', code: 'KRW', name: 'South Korean Won', symbol: '₩'),
  (flag: '🇳🇴', code: 'NOK', name: 'Norwegian Krone', symbol: 'kr'),
  (flag: '🇸🇪', code: 'SEK', name: 'Swedish Krona', symbol: 'kr'),
  (flag: '🇩🇰', code: 'DKK', name: 'Danish Krone', symbol: 'kr'),
  (flag: '🇲🇽', code: 'MXN', name: 'Mexican Peso', symbol: 'MX\$'),
  (flag: '🇿🇦', code: 'ZAR', name: 'South African Rand', symbol: 'R'),
  (flag: '🇧🇷', code: 'BRL', name: 'Brazilian Real', symbol: 'R\$'),
  (flag: '🇦🇪', code: 'AED', name: 'UAE Dirham', symbol: 'د.إ'),
  (flag: '🇸🇦', code: 'SAR', name: 'Saudi Riyal', symbol: '﷼'),
  (flag: '🇹🇭', code: 'THB', name: 'Thai Baht', symbol: '฿'),
  (flag: '🇮🇩', code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp'),
  (flag: '🇲🇾', code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM'),
  (flag: '🇵🇭', code: 'PHP', name: 'Philippine Peso', symbol: '₱'),
  (flag: '🇵🇰', code: 'PKR', name: 'Pakistani Rupee', symbol: '₨'),
  (flag: '🇧🇩', code: 'BDT', name: 'Bangladeshi Taka', symbol: '৳'),
  (flag: '🇱🇰', code: 'LKR', name: 'Sri Lankan Rupee', symbol: '₨'),
  (flag: '🇳🇵', code: 'NPR', name: 'Nepalese Rupee', symbol: '₨'),
  (flag: '🇹🇷', code: 'TRY', name: 'Turkish Lira', symbol: '₺'),
  (flag: '🇷🇺', code: 'RUB', name: 'Russian Ruble', symbol: '₽'),
  (flag: '🇵🇱', code: 'PLN', name: 'Polish Zloty', symbol: 'zł'),
  (flag: '🇨🇿', code: 'CZK', name: 'Czech Koruna', symbol: 'Kč'),
  (flag: '🇭🇺', code: 'HUF', name: 'Hungarian Forint', symbol: 'Ft'),
  (flag: '🇷🇴', code: 'RON', name: 'Romanian Leu', symbol: 'lei'),
  (flag: '🇺🇦', code: 'UAH', name: 'Ukrainian Hryvnia', symbol: '₴'),
  (flag: '🇮🇱', code: 'ILS', name: 'Israeli New Shekel', symbol: '₪'),
  (flag: '🇰🇼', code: 'KWD', name: 'Kuwaiti Dinar', symbol: 'KD'),
  (flag: '🇧🇭', code: 'BHD', name: 'Bahraini Dinar', symbol: 'BD'),
  (flag: '🇶🇦', code: 'QAR', name: 'Qatari Riyal', symbol: 'QR'),
  (flag: '🇴🇲', code: 'OMR', name: 'Omani Rial', symbol: 'OMR'),
  (flag: '🇯🇴', code: 'JOD', name: 'Jordanian Dinar', symbol: 'JD'),
  (flag: '🇪🇬', code: 'EGP', name: 'Egyptian Pound', symbol: 'E£'),
  (flag: '🇳🇬', code: 'NGN', name: 'Nigerian Naira', symbol: '₦'),
  (flag: '🇰🇪', code: 'KES', name: 'Kenyan Shilling', symbol: 'KSh'),
  (flag: '🇬🇭', code: 'GHS', name: 'Ghanaian Cedi', symbol: '₵'),
  (flag: '🇹🇿', code: 'TZS', name: 'Tanzanian Shilling', symbol: 'TSh'),
  (flag: '🇺🇬', code: 'UGX', name: 'Ugandan Shilling', symbol: 'USh'),
  (flag: '🇪🇹', code: 'ETB', name: 'Ethiopian Birr', symbol: 'Br'),
  (flag: '🇦🇷', code: 'ARS', name: 'Argentine Peso', symbol: 'AR\$'),
  (flag: '🇨🇱', code: 'CLP', name: 'Chilean Peso', symbol: 'CL\$'),
  (flag: '🇨🇴', code: 'COP', name: 'Colombian Peso', symbol: 'CO\$'),
  (flag: '🇵🇪', code: 'PEN', name: 'Peruvian Sol', symbol: 'S/'),
  (flag: '🇻🇳', code: 'VND', name: 'Vietnamese Dong', symbol: '₫'),
  (flag: '🇹🇼', code: 'TWD', name: 'Taiwan Dollar', symbol: 'NT\$'),
  (flag: '🇮🇷', code: 'IRR', name: 'Iranian Rial', symbol: '﷼'),
  (flag: '🇲🇦', code: 'MAD', name: 'Moroccan Dirham', symbol: 'MAD'),
  (flag: '🇩🇿', code: 'DZD', name: 'Algerian Dinar', symbol: 'دج'),
  (flag: '🇹🇳', code: 'TND', name: 'Tunisian Dinar', symbol: 'DT'),
  (flag: '🇮🇸', code: 'ISK', name: 'Icelandic Króna', symbol: 'kr'),
  (flag: '🇭🇷', code: 'HRK', name: 'Croatian Kuna', symbol: 'kn'),
  (flag: '🇷🇸', code: 'RSD', name: 'Serbian Dinar', symbol: 'din'),
  (flag: '🇧🇬', code: 'BGN', name: 'Bulgarian Lev', symbol: 'лв'),
  (flag: '🇲🇲', code: 'MMK', name: 'Myanmar Kyat', symbol: 'K'),
  (flag: '🇰🇭', code: 'KHR', name: 'Cambodian Riel', symbol: '៛'),
  (flag: '🇱🇦', code: 'LAK', name: 'Lao Kip', symbol: '₭'),
  (flag: '🇲🇳', code: 'MNT', name: 'Mongolian Tugrik', symbol: '₮'),
  (flag: '🇦🇲', code: 'AMD', name: 'Armenian Dram', symbol: '֏'),
  (flag: '🇬🇪', code: 'GEL', name: 'Georgian Lari', symbol: '₾'),
  (flag: '🇦🇿', code: 'AZN', name: 'Azerbaijani Manat', symbol: '₼'),
  (flag: '🇰🇿', code: 'KZT', name: 'Kazakhstani Tenge', symbol: '₸'),
  (flag: '🇺🇿', code: 'UZS', name: 'Uzbekistani Sum', symbol: 'лв'),
  (flag: '🇹🇲', code: 'TMT', name: 'Turkmenistani Manat', symbol: 'T'),
  (flag: '🇧🇾', code: 'BYN', name: 'Belarusian Ruble', symbol: 'Br'),
  (flag: '🇲🇩', code: 'MDL', name: 'Moldovan Leu', symbol: 'L'),
  (flag: '🇦🇱', code: 'ALL', name: 'Albanian Lek', symbol: 'L'),
  (flag: '🇲🇰', code: 'MKD', name: 'Macedonian Denar', symbol: 'ден'),
  (flag: '🇧🇦', code: 'BAM', name: 'Bosnia Mark', symbol: 'KM'),
  (flag: '🇲🇹', code: 'MTL', name: 'Maltese Lira', symbol: 'Lm'),
  (flag: '🇵🇦', code: 'PAB', name: 'Panamanian Balboa', symbol: 'B/.'),
  (flag: '🇨🇷', code: 'CRC', name: 'Costa Rican Colón', symbol: '₡'),
  (flag: '🇬🇹', code: 'GTQ', name: 'Guatemalan Quetzal', symbol: 'Q'),
  (flag: '🇧🇴', code: 'BOB', name: 'Bolivian Boliviano', symbol: 'Bs.'),
  (flag: '🇵🇾', code: 'PYG', name: 'Paraguayan Guaraní', symbol: '₲'),
  (flag: '🇺🇾', code: 'UYU', name: 'Uruguayan Peso', symbol: 'UY\$'),
  (flag: '🇪🇨', code: 'USD', name: 'Ecuadorian (USD)', symbol: '\$'),
  (flag: '🇨🇺', code: 'CUP', name: 'Cuban Peso', symbol: '₱'),
  (flag: '🇩🇴', code: 'DOP', name: 'Dominican Peso', symbol: 'RD\$'),
  (flag: '🇯🇲', code: 'JMD', name: 'Jamaican Dollar', symbol: 'J\$'),
  (flag: '🇹🇹', code: 'TTD', name: 'Trinidad Dollar', symbol: 'TT\$'),
  (flag: '🇧🇧', code: 'BBD', name: 'Barbadian Dollar', symbol: 'Bds\$'),
  (flag: '🇫🇯', code: 'FJD', name: 'Fijian Dollar', symbol: 'FJ\$'),
  (flag: '🇵🇬', code: 'PGK', name: 'Papua New Guinea Kina', symbol: 'K'),
];

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<Product> _products = List.from(_defaultProducts);
  Map<String, List<ProductVariant>> _variantsByProduct = {};
  // Product whose variants are currently expanded inline in the billing grid.
  String? _expandedVariantProductId;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  // Debounces the search box's auto-add so a fast barcode scan fully arrives
  // (including its trailing EAN-13 check digit) before we try to match.
  Timer? _scanDebounce;
  // Global barcode-scanner capture: a keyboard-wedge scanner types its whole
  // code in a rapid keystroke burst into whatever field currently has focus.
  // We intercept that burst app-wide (see _handleGlobalKey) so a scan always
  // routes to the cart, even if the Customer Name / Phone field is focused.
  String _scanBuffer = '';
  DateTime _lastScanKeyTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _scanBurstRapid = false;
  DateTime _lastScanAddedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _selectedTab = 1;
  String _inventorySearchQuery = '';
  String _inventoryCategoryFilter = 'All';
  double _rightPanelWidth = 375;

  // Reports state
  String _reportView = 'Sales';
  String _utilitiesView = 'Delivery';
  String _salesSearchQuery = '';
  String _customerSearchQuery = '';
  List<Customer> _reportCustomers = [];
  List<Customer> _savedCustomers = [];
  List<Customer> _nameAcOptions = [];
  List<Customer> _phoneAcOptions = [];
  bool _acSkipRefocus = false;
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _customerNameFocus = FocusNode();
  final _customerPhoneFocus = FocusNode();
  final _addCustomerFocus = FocusNode();

  // Dynamic categories (user can add more)
  List<String> _userCategories = [];

  // Dashboard state (real data)
  double _dashSales = 0;
  int _dashTxCount = 0;
  int _dashItemsSold = 0;
  double _dashAvgOrder = 0;
  double _dashYestSales = 0;
  int _dashYestTxCount = 0;
  int _dashYestItems = 0;
  double _dashYestAvg = 0;
  double _dashWeekSales = 0;
  double _dashMonthSales = 0;
  double _dashYearSales = 0;

  // Per-period additional metrics
  int _dashWeekTxCount = 0;
  int _dashWeekItems = 0;
  double _dashWeekAvg = 0;
  int _dashMonthTxCount = 0;
  int _dashMonthItems = 0;
  double _dashMonthAvg = 0;
  int _dashYearTxCount = 0;
  int _dashYearItems = 0;
  double _dashYearAvg = 0;

  // Profit per period
  double _dashProfitToday = 0;
  double _dashProfitWeek = 0;
  double _dashProfitMonth = 0;

  // Period selector
  String _dashPeriod = 'Today';

  // Chart bars per period
  List<(String, double)> _chartBarsToday = [];
  List<(String, double)> _chartBarsWeek = [];
  List<(String, double)> _chartBarsMonth = [];
  List<(String, double)> _chartBarsYear = [];

  // Same-day last week (for "No data yesterday" comparison)
  double _dashLastWeekSameDaySales = 0;

  // Top sold products per period: (name, qty, revenue)
  List<(String, int, double)> _topProductsToday = [];
  List<(String, int, double)> _topProductsWeek = [];
  List<(String, int, double)> _topProductsMonth = [];
  List<(String, int, double)> _topProductsYear = [];
  List<(String, double, Color)> _dashCategories = [];
  List<TransactionRecord> _dashRecentTx = [];

  // Sales report period
  String _reportSalesPeriod = 'This Week';
  List<TransactionRecord> _txListToday = [];
  List<TransactionRecord> _txListWeek = [];
  List<TransactionRecord> _txListMonth = [];

  // Settings state
  String _storeName = 'BillCat Store';
  String _storeAddress = '';
  String _storePhone = '';
  String _storeEmail = '';
  String _storeGstin = '';
  String _logoPath = '';
  String _logoUrl = '';
  String _receiptFooter = 'Thank you for your purchase!';
  String _taxLabel = 'GST';
  String _taxRateDisplay = '0';
  String _currencySymbol = '₹';
  String _currencyCode = 'INR';
  String _dialCode = '+91'; // default India
  String _invoiceLayout = 'Classic';
  String _printOrientation = 'Portrait';
  String _storeTerms =
      'Payment due within 30 days. Goods once sold will not be taken back.';
  String _storeUpiId = '';
  String _branchNumber = '01';

  // Printer state
  String _selectedPrinter = 'System Default';
  Printer? _activePrinter;
  String _paperSize = 'A4';
  bool _autoPrint = false;
  // Remembered state of the Print Bill dialog's toggles between opens.
  bool _sendToPrinterPref = false;
  bool _sendWhatsAppPref = false;

  // Barcode print last-used settings
  double _barcodeLabelW = 58;
  double _barcodeLabelH = 30;
  int _barcodePerRow = 1;
  String _barcodePrinter = 'System Default';

  // Bulk barcode print view
  Map<String, int> _bulkPrintQtys = {};
  Map<String, bool> _bulkPrintSelected = {};
  List<String> _bulkPrinters = ['System Default'];

  // Top toast
  String _toastMessage = '';
  bool _toastVisible = false;
  bool _toastIsError = false;

  // Update banner
  UpdateInfo? _updateInfo;
  bool _updateDismissed = false;
  bool _isCheckingUpdate = false;
  String _currentVersion = '';
  double? _downloadProgress; // null=idle, 0–1=downloading, 1.0=done
  String _downloadedPath = '';

  // Owner / Staff access
  bool _ownerLockEnabled = false;
  bool _isOwnerMode = false;
  String _ownerPasscode = '';

  // Settings panel
  bool _showSettings = false;
  bool _isPrinting = false;
  Timer? _printSafetyTimer;
  bool _addingCustomProduct = false;
  final _customNameCtrl = TextEditingController();
  final _customPriceCtrl = TextEditingController();
  String _settingsPage = 'General';
  String _editStoreName = 'BillCat Store';
  String _editStoreAddress = '';
  String _editLogoPath = '';
  String _editLogoUrl = '';
  String _editReceiptFooter = 'Thank you for your purchase!';
  String _editTaxLabel = 'VAT';
  String _editTaxRate = '0';
  String _editCurrencyCode = 'INR';
  String _editCurrencySymbol = '₹';
  String _editDialCode = '+91';
  String _editPaperSize = 'A4';
  bool _editAutoPrint = false;
  String _editStorePhone = '';
  String _editStoreEmail = '';
  String _editStoreGstin = '';
  String _editInvoiceLayout = 'Classic';
  String _editPrintOrientation = 'Portrait';
  String _editPrinterTab = 'Regular';
  int _previewRevision = 0;
  String _editStoreTerms =
      'Payment due within 30 days. Goods once sold will not be taken back.';
  String _editStoreUpiId = '';
  String _editBranchNumber = '01';

  // WhatsApp Meta Cloud API
  String _waPhoneNumberId = '';
  String _waAccessToken = '';
  String _editWaPhoneNumberId = '';
  String _editWaAccessToken = '';

  List<Product> get _filteredProducts {
    return _products.where((p) {
      final matchCat =
          _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchSearch =
          p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.sku.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
  }

  // Grid entries: normally all products; while a product's variants are
  // expanded, the grid shows only that product followed by its variant cards.
  List<Object> get _displayGridItems {
    final expandedId = _expandedVariantProductId;
    if (expandedId != null) {
      final parent = _filteredProducts.cast<Product?>().firstWhere(
        (p) => p!.id == expandedId,
        orElse: () => null,
      );
      final variants =
          _variantsByProduct[expandedId] ?? const <ProductVariant>[];
      if (parent != null && variants.isNotEmpty) {
        return <Object>[parent, ...variants.map((v) => (parent, v))];
      }
    }
    return List<Object>.from(_filteredProducts);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _cleanupCupsOptions();
    _loadSettingsFromStorage();
    _loadProducts();
    _loadDashboardData();
    _loadSavedCustomers();
    ConnectivityService.instance.addListener(_onSyncComplete);
    _checkForUpdate();
    _loadCurrentVersion();
    ReceiptPrinter.preWarm();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTaxRate());
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && mounted) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted || _searchFocus.hasFocus || _showSettings) return;
          final primary = FocusManager.instance.primaryFocus;
          if (primary == null || primary.context == null) {
            _searchFocus.requestFocus();
            return;
          }
          // Don't steal focus from another text input (dialogs, customer fields, etc.)
          bool otherTextFieldFocused = false;
          primary.context?.visitAncestorElements((element) {
            if (element.widget is EditableText) {
              otherTextFieldFocused = true;
              return false;
            }
            return true;
          });
          if (!otherTextFieldFocused) _searchFocus.requestFocus();
        });
      }
    });
  }

  // Removes corrupted BillCat-specific CUPS options written by older app versions.
  // Those lpoptions entries caused Printers & Scanners in System Settings to freeze.
  Future<void> _cleanupCupsOptions() async {
    try {
      final file = File('${Platform.environment['HOME']}/.cups/lpoptions');
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      final cleaned = lines
          .map((line) {
            // Remove BillCat_* media and PageSize options from any line
            var l = line.replaceAll(RegExp(r'\s*media=BillCat_\S+'), '');
            l = l.replaceAll(RegExp(r'\s*PageSize=Custom\.\d+x\d+'), '');
            return l.trim();
          })
          .where((l) => l.isNotEmpty)
          .toList();
      if (cleaned.join('\n') != lines.join('\n')) {
        file.writeAsStringSync('${cleaned.join('\n')}\n');
      }
    } catch (_) {}
  }

  Future<void> _loadSettingsFromStorage() async {
    final s = await LocalDbService.getSettings();
    if (s.isEmpty || !mounted) return;
    setState(() {
      _storeName = s['store_name'] ?? _storeName;
      _storeAddress = s['store_address'] ?? _storeAddress;
      _storePhone = s['store_phone'] ?? _storePhone;
      _storeEmail = s['store_email'] ?? _storeEmail;
      _storeGstin = s['store_gstin'] ?? _storeGstin;
      _receiptFooter = s['receipt_footer'] ?? _receiptFooter;
      _taxLabel = s['tax_label'] ?? _taxLabel;
      _taxRateDisplay = s['tax_rate'] ?? _taxRateDisplay;
      _currencyCode = s['currency_code'] ?? _currencyCode;
      _currencySymbol = s['currency_symbol'] ?? _currencySymbol;
      _dialCode = s['dial_code'] ?? _dialCode;
      _paperSize = s['paper_size'] ?? _paperSize;
      _selectedPrinter = s['selected_printer'] ?? _selectedPrinter;
      _barcodeLabelW =
          double.tryParse(s['barcode_label_w'] ?? '') ?? _barcodeLabelW;
      _barcodeLabelH =
          double.tryParse(s['barcode_label_h'] ?? '') ?? _barcodeLabelH;
      _barcodePerRow =
          int.tryParse(s['barcode_per_row'] ?? '') ?? _barcodePerRow;
      _barcodePrinter = s['barcode_printer'] ?? _barcodePrinter;
      _printOrientation = s['print_orientation'] ?? _printOrientation;
      final savedLayout = s['invoice_layout'] ?? _invoiceLayout;
      const _validLayouts = [
        'Classic',
        'Simple',
        'Modern',
        'GST',
        'Landscape',
        'Theme 1',
        'Theme 2',
        'Theme 3',
        'Theme 4',
        'Theme 5',
      ];
      _invoiceLayout = _validLayouts.contains(savedLayout)
          ? savedLayout
          : 'Classic';
      _storeTerms = s['store_terms'] ?? _storeTerms;
      _logoPath = s['logo_path'] ?? _logoPath;
      // Prefer local setting; fall back to auth user metadata logo_url
      final metaLogoUrl =
          Supabase.instance.client.auth.currentUser?.userMetadata?['logo_url']
              as String? ??
          '';
      _logoUrl = (s['logo_url']?.isNotEmpty == true
          ? s['logo_url']!
          : metaLogoUrl);
      _autoPrint = (s['auto_print'] ?? '0') == '1';
      _sendToPrinterPref = (s['print_send_to_printer'] ?? '0') == '1';
      _sendWhatsAppPref = (s['print_send_whatsapp'] ?? '0') == '1';
      _storeUpiId = s['store_upi_id'] ?? _storeUpiId;
      _branchNumber = s['branch_number'] ?? _branchNumber;
      _ownerPasscode = s['owner_passcode'] ?? '';
      _ownerLockEnabled = (s['owner_lock_enabled'] ?? '0') == '1';
      _waPhoneNumberId = s['wa_phone_number_id'] ?? '';
      _waAccessToken = s['wa_access_token'] ?? '';
      _editWaPhoneNumberId = _waPhoneNumberId;
      _editWaAccessToken = _waAccessToken;
    });
    _syncTaxRate();
    _restoreActivePrinter();
  }

  Future<void> _restoreActivePrinter() async {
    if (_selectedPrinter == 'PDF Export' ||
        _selectedPrinter == 'System Default')
      return;
    try {
      final printers = await Printing.listPrinters();
      final match = printers.where((p) => p.name == _selectedPrinter).toList();
      if (match.isNotEmpty && mounted)
        setState(() => _activePrinter = match.first);
    } catch (_) {}
  }

  void _syncTaxRate() {
    final cart = context.read<CartProvider>();
    cart.setTaxRate(double.tryParse(_taxRateDisplay) ?? 0.0);
  }

  // Applies a tax rate entered from the cart summary: updates the running bill
  // and persists it so the next bill (and the receipt) uses the same rate.
  void _applyTaxRate(String rate) {
    final parsed = (double.tryParse(rate) ?? 0.0).clamp(0.0, 100.0);
    final normalised = parsed == parsed.truncateToDouble()
        ? parsed.toStringAsFixed(0)
        : parsed.toString();
    setState(() {
      _taxRateDisplay = normalised;
      _editTaxRate = normalised;
    });
    context.read<CartProvider>().setTaxRate(parsed);
    LocalDbService.saveSettings({'tax_rate': normalised});
    ConnectivityService.instance.syncNow();
  }

  Future<void> _loadSavedCustomers() async {
    final customers = await LocalDbService.getCustomers();
    if (mounted) setState(() => _savedCustomers = customers);
  }

  Future<void> _loadCurrentVersion() async {
    final v = await UpdateService.currentVersion();
    if (mounted) setState(() => _currentVersion = v);
  }

  Future<void> _checkForUpdate() async {
    // Surface a previous failed self-update (the old version relaunching
    // "successfully" otherwise looks like the update simply didn't happen).
    try {
      final failReason = await UpdateService.consumeFailedUpdateLog();
      if (failReason != null && mounted) {
        _showToast(
          'The last update could not be applied automatically. '
          'Please download the installer from the update banner. '
          '($failReason)',
          isError: true,
        );
      }
    } catch (_) {}
    try {
      final info = await UpdateService.checkForUpdate();
      if (mounted && info != null) setState(() => _updateInfo = info);
    } catch (_) {}
  }

  Future<void> _manualCheckForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
      _updateDismissed = false;
    });
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (info != null) {
        setState(() {
          _updateInfo = info;
          _isCheckingUpdate = false;
        });
      } else {
        setState(() {
          _updateInfo = null;
          _isCheckingUpdate = false;
        });
        if (mounted) {
          _showToast(
            'BillCat is up to date (v${_currentVersion.isNotEmpty ? _currentVersion : '1.0.0'})',
          );
        }
      }
    } on UpdateCheckError catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        _showToast(e.message, isError: true);
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  Future<void> _installUpdate() async {
    final info = _updateInfo;
    if (info == null || _downloadProgress != null) return;
    setState(() {
      _downloadProgress = 0.0;
      _downloadedPath = '';
    });
    try {
      await UpdateService.installUpdate(info.downloadUrl, (p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
    } on UpdateCheckError catch (e) {
      if (mounted) {
        setState(() => _downloadProgress = null);
        _showToast(e.message, isError: true);
      }
    } catch (_) {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  // Matches stored 12-digit EAN-13 against scanner output (12 or 13 digits)
  // App-wide barcode-scanner capture. A keyboard-wedge scanner emits its whole
  // code as a rapid keystroke burst (characters far faster than any human) and
  // usually a trailing Enter. We watch every key event, and when a rapid,
  // barcode-shaped burst completes we add the matching item to the cart — no
  // matter which field happened to have focus — then wipe the code out of any
  // field that caught it. Slow (human) typing is left completely alone.
  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Only active on the Billing tab, and not while a modal dialog is open.
    if (_selectedTab != 1 || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }

    // Billing shortcuts: Ctrl+P = Print Bill, Ctrl+C = Paid/Close Bill.
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyP) {
        final cart = context.read<CartProvider>();
        if (cart.items.isNotEmpty && !_isPrinting) _showPrintBillDialog(cart);
        return true;
      }
      if (key == LogicalKeyboardKey.keyC) {
        final cart = context.read<CartProvider>();
        if (cart.items.isNotEmpty) _closeBill(context, cart);
        return true;
      }
      // Any other Ctrl combo (copy/paste in fields, etc.) — leave it alone and
      // don't let it feed the scan buffer.
      return false;
    }

    final now = DateTime.now();
    final gapMs = now.difference(_lastScanKeyTime).inMilliseconds;
    _lastScanKeyTime = now;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _scanBuffer;
      final wasRapid = _scanBurstRapid;
      _scanBuffer = '';
      _scanBurstRapid = false;
      // Treat as a scan only if the buffer built up rapidly and looks like a
      // real code (long enough, alphanumeric). Otherwise let Enter behave
      // normally (e.g. submitting a typed search / customer field).
      if (wasRapid && code.length >= 6 && _looksLikeCode(code)) {
        _addScannedCodeToCart(code);
        return true; // consume the scanner's Enter so fields don't also submit
      }
      return false;
    }

    final ch = event.character;
    if (ch == null || ch.length != 1 || !_isCodeChar(ch)) {
      _scanBuffer = '';
      _scanBurstRapid = false;
      return false;
    }

    // > ~60ms since the previous key = a fresh keystroke. Could be a human, or
    // the first char of a scan. Start a new buffer but let this one through
    // (we still keep it buffered so the full code is intact for matching).
    if (gapMs > 60) {
      _scanBuffer = ch;
      _scanBurstRapid = false;
      return false;
    }
    // Rapid successor = part of a scanner burst. Buffer and swallow it.
    _scanBuffer += ch;
    _scanBurstRapid = true;
    return true;
  }

  bool _isCodeChar(String ch) => RegExp(r'^[0-9A-Za-z\-]$').hasMatch(ch);

  bool _looksLikeCode(String s) =>
      s.length >= 6 && RegExp(r'^[0-9A-Za-z\-]+$').hasMatch(s);

  void _addScannedCodeToCart(String code) {
    if (!mounted) return;
    final query = code.trim();
    final cart = context.read<CartProvider>();

    final variantMatch = _matchVariantByCode(query);
    if (variantMatch != null) {
      cart.addVariant(variantMatch.$1, variantMatch.$2);
      _showToast(
        '${variantMatch.$1.name} (${variantMatch.$2.label}) added to cart',
      );
      _afterScanAdd(query);
      return;
    }
    final match = _products.cast<Product?>().firstWhere(
      (p) =>
          _barcodeMatches(p!.barcodeNo, query) ||
          p.sku.toLowerCase() == query.toLowerCase(),
      orElse: () => null,
    );
    if (match != null) {
      final hasVariants = (_variantsByProduct[match.id] ?? const []).isNotEmpty;
      if (hasVariants) {
        _addToCartOrPickVariant(match, cart);
      } else {
        cart.addProduct(match);
        _showToast('${match.name} added to cart');
      }
      _afterScanAdd(query);
      return;
    }
    _showToast('No product found for "$query"', isError: true);
    _afterScanAdd(query);
  }

  // Wipe a just-scanned code out of any field that caught the raw keystrokes,
  // then park focus back on the search box ready for the next scan.
  void _afterScanAdd(String code) {
    _lastScanAddedAt = DateTime.now();
    _scanDebounce?.cancel();
    void scrub(TextEditingController c) {
      final t = c.text;
      if (t == code || (t.length >= 6 && _looksLikeCode(t))) c.clear();
    }

    scrub(_searchController);
    scrub(_customerNameCtrl);
    scrub(_customerPhoneCtrl);
    if (mounted) setState(() => _searchQuery = '');
    Future.microtask(() {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  bool _barcodeMatches(String stored, String scanned) {
    if (stored.isEmpty) return false;
    if (stored == scanned) return true;
    // Scanner sends full 13-digit EAN-13 (stored is the 12-digit input)
    if (scanned.length == 13 && scanned.startsWith(stored)) return true;
    // Scanner configured as UPC-A: strips leading '0' from EAN-13 before sending
    // e.g. stored=000000100009, EAN-13=0000001000092, scanner sends=000001000092
    if (scanned.length == 12) {
      final withLeadingZero = '0$scanned';
      if (withLeadingZero.startsWith(stored)) return true;
    }
    return false;
  }

  Future<void> _loadProducts() async {
    await LocalDbService.assignMissingBarcodeNos();
    final local = await LocalDbService.getProducts();
    final savedCats = await LocalDbService.getCategories();
    final variantsByProduct =
        await LocalDbService.getVariantsGroupedByProduct();
    if (mounted)
      setState(() {
        _products = local;
        _variantsByProduct = variantsByProduct;
        final seen = <String>{};
        // Merge: categories from DB table + categories from products
        final fromProducts = local
            .map((p) => p.category)
            .where((c) => c.isNotEmpty)
            .toSet();
        _userCategories = [
          ...savedCats,
          ...fromProducts.where((c) => !savedCats.contains(c)),
        ].where((c) => seen.add(c)).toList();
      });
  }

  (Product, ProductVariant)? _matchVariantByCode(String query) {
    for (final entry in _variantsByProduct.entries) {
      for (final v in entry.value) {
        final matches =
            _barcodeMatches(v.barcodeNo, query) ||
            (v.sku.isNotEmpty && v.sku.toLowerCase() == query.toLowerCase());
        if (matches) {
          final product = _products.cast<Product?>().firstWhere(
            (p) => p!.id == entry.key,
            orElse: () => null,
          );
          if (product != null) return (product, v);
        }
      }
    }
    return null;
  }

  void _addToCartOrPickVariant(Product product, CartProvider cart) {
    final variants = _variantsByProduct[product.id] ?? const <ProductVariant>[];
    if (variants.isEmpty) {
      cart.addProduct(product);
      return;
    }
    showDialog(
      context: context,
      builder: (dCtx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Choose a variant',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 14),
                ...variants.map((v) {
                  final inCartQty = cart.quantityInCartForVariant(
                    product.id,
                    v.id,
                  );
                  final remaining = v.stock - inCartQty;
                  final outOfStock = remaining <= 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: outOfStock
                          ? null
                          : () {
                              cart.addVariant(product, v);
                              Navigator.pop(dCtx);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: outOfStock
                              ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.label,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: outOfStock
                                      ? AppColors.textMuted
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                            Text(
                              outOfStock
                                  ? 'Out of stock'
                                  : '$_currencySymbol${v.price.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: outOfStock
                                    ? AppColors.error
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dCtx),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadDashboardData() async {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    // Week: Mon–today
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    // Month: 1st of current month
    final monthStart = DateTime(today.year, today.month, 1);
    // Year: Jan 1
    final yearStart = DateTime(today.year, 1, 1);

    final lastWeekSameDay = today.subtract(const Duration(days: 7));

    final results = await Future.wait([
      LocalDbService.getTransactionsForDate(today),
      LocalDbService.getTransactionsForDate(yesterday),
      LocalDbService.getTransactionsForRange(weekStart, today),
      LocalDbService.getTransactionsForRange(monthStart, today),
      LocalDbService.getTransactionsForRange(yearStart, today),
      LocalDbService.getTransactionsForDate(lastWeekSameDay),
    ]);

    final todayTx = results[0];
    final yesterdayTx = results[1];
    final weekTx = results[2];
    final monthTx = results[3];
    final yearTx = results[4];
    final lastWeekSameDayTx = results[5];

    final products = await LocalDbService.getProducts();
    final catMap = {for (final p in products) p.id: p.category};
    final buyingPriceMap = {for (final p in products) p.id: p.buyingPrice};

    double sales = 0, ySales = 0;
    int txCount = todayTx.length, yTxCount = yesterdayTx.length;
    int items = 0, yItems = 0;
    final catRevenue = <String, double>{};

    for (final t in todayTx) {
      sales += t.total;
      for (final i in t.items) {
        items += i.quantity;
        final cat = catMap[i.productId] ?? 'Other';
        catRevenue[cat] = (catRevenue[cat] ?? 0) + i.total;
      }
    }
    for (final t in yesterdayTx) {
      ySales += t.total;
      for (final i in t.items) yItems += i.quantity;
    }

    double weekSales = weekTx.fold(0.0, (s, t) => s + t.total);
    double monthSales = monthTx.fold(0.0, (s, t) => s + t.total);
    double yearSales = yearTx.fold(0.0, (s, t) => s + t.total);
    double lastWeekSameDaySales = lastWeekSameDayTx.fold(
      0.0,
      (s, t) => s + t.total,
    );

    int weekItems = 0, monthItems = 0, yearItems = 0;
    for (final t in weekTx) {
      for (final i in t.items) weekItems += i.quantity;
    }
    for (final t in monthTx) {
      for (final i in t.items) monthItems += i.quantity;
    }
    for (final t in yearTx) {
      for (final i in t.items) yearItems += i.quantity;
    }

    // ── Profit per period ─────────────────────────────────────────────────────
    double calcProfit(List<TransactionRecord> txs) {
      double profit = 0;
      for (final t in txs) {
        double cogs = 0;
        for (final i in t.items) {
          cogs += (buyingPriceMap[i.productId] ?? 0.0) * i.quantity;
        }
        profit += t.total - cogs;
      }
      return profit;
    }

    final profitToday = calcProfit(todayTx);
    final profitWeek = calcProfit(weekTx);
    final profitMonth = calcProfit(monthTx);

    // ── Chart bars ────────────────────────────────────────────────────────────
    // Today: 8 three-hour slots
    final tSlotLabels = ['12a', '3a', '6a', '9a', '12p', '3p', '6p', '9p'];
    final tSlotMap = {for (final l in tSlotLabels) l: 0.0};
    for (final t in todayTx) {
      final l = tSlotLabels[t.createdAt.hour ~/ 3];
      tSlotMap[l] = tSlotMap[l]! + t.total;
    }
    final chartToday = tSlotLabels.map((l) => (l, tSlotMap[l]!)).toList();

    // Week: Mon–Sun
    const wLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final wMap = {for (final l in wLabels) l: 0.0};
    for (final t in weekTx) {
      final l = wLabels[t.createdAt.weekday - 1];
      wMap[l] = wMap[l]! + t.total;
    }
    final chartWeek = wLabels.map((l) => (l, wMap[l]!)).toList();

    // Month: weeks W1–W5
    const mLabels = ['W1', 'W2', 'W3', 'W4', 'W5'];
    final mMap = {for (final l in mLabels) l: 0.0};
    for (final t in monthTx) {
      final l = 'W${((t.createdAt.day - 1) ~/ 7) + 1}';
      mMap[l] = (mMap[l] ?? 0) + t.total;
    }
    final chartMonth = mLabels.map((l) => (l, mMap[l]!)).toList();

    // Year: Jan–Dec
    final yMap = {for (int i = 1; i <= 12; i++) _monthName(i): 0.0};
    for (final t in yearTx) {
      final l = _monthName(t.createdAt.month);
      yMap[l] = yMap[l]! + t.total;
    }
    final chartYear = List.generate(
      12,
      (i) => (_monthName(i + 1), yMap[_monthName(i + 1)]!),
    );

    // ── Top sold products ─────────────────────────────────────────────────────
    List<(String, int, double)> _topOf(List<TransactionRecord> txs) {
      final map = <String, (int, double)>{};
      for (final t in txs) {
        for (final item in t.items) {
          final e = map[item.productName] ?? (0, 0.0);
          map[item.productName] = (e.$1 + item.quantity, e.$2 + item.total);
        }
      }
      // Returns carry negative quantities so a product nets down correctly,
      // but one that only ever came back is not a top seller.
      final sorted = map.entries.where((e) => e.value.$1 > 0).toList()
        ..sort((a, b) => b.value.$1.compareTo(a.value.$1));
      return sorted
          .take(5)
          .map((e) => (e.key, e.value.$1, e.value.$2))
          .toList();
    }

    final topToday = _topOf(todayTx);
    final topWeek = _topOf(weekTx);
    final topMonth = _topOf(monthTx);
    final topYear = _topOf(yearTx);

    const catColors = [
      Color(0xFF1B2B4B),
      Color(0xFF3B82F6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
    ];
    final sortedCats = catRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dashCats = sortedCats
        .take(5)
        .toList()
        .asMap()
        .entries
        .map(
          (e) =>
              (e.value.key, e.value.value, catColors[e.key % catColors.length]),
        )
        .toList();

    // ── Payment breakdown ─────────────────────────────────────────────────────
    const payColors = {
      'cash': Color(0xFF10B981),
      'card': Color(0xFF3B82F6),
      'upi': Color(0xFF8B5CF6),
      'hybrid': Color(0xFFF59E0B),
    };
    if (!mounted) return;
    setState(() {
      _dashSales = sales;
      _dashTxCount = txCount;
      // Item counts net returns off, which is right when both fall in the
      // period — but a return of an older bill must not read as a minus count.
      _dashItemsSold = items < 0 ? 0 : items;
      _dashAvgOrder = txCount > 0 ? sales / txCount : 0;
      _dashYestSales = ySales;
      _dashYestTxCount = yTxCount;
      _dashYestItems = yItems < 0 ? 0 : yItems;
      _dashYestAvg = yTxCount > 0 ? ySales / yTxCount : 0;
      _dashWeekSales = weekSales;
      _dashMonthSales = monthSales;
      _dashYearSales = yearSales;
      _dashWeekTxCount = weekTx.length;
      _dashWeekItems = weekItems < 0 ? 0 : weekItems;
      _dashWeekAvg = weekTx.isNotEmpty ? weekSales / weekTx.length : 0;
      _dashMonthTxCount = monthTx.length;
      _dashMonthItems = monthItems < 0 ? 0 : monthItems;
      _dashMonthAvg = monthTx.isNotEmpty ? monthSales / monthTx.length : 0;
      _dashYearTxCount = yearTx.length;
      _dashYearItems = yearItems < 0 ? 0 : yearItems;
      _dashYearAvg = yearTx.isNotEmpty ? yearSales / yearTx.length : 0;
      _chartBarsToday = chartToday;
      _chartBarsWeek = chartWeek;
      _chartBarsMonth = chartMonth;
      _chartBarsYear = chartYear;
      _dashLastWeekSameDaySales = lastWeekSameDaySales;
      _topProductsToday = topToday;
      _topProductsWeek = topWeek;
      _topProductsMonth = topMonth;
      _topProductsYear = topYear;
      _dashCategories = dashCats;
      _dashRecentTx = todayTx.take(5).toList();
      _txListToday = todayTx;
      _txListWeek = weekTx;
      _txListMonth = monthTx;
      _dashProfitToday = profitToday;
      _dashProfitWeek = profitWeek;
      _dashProfitMonth = profitMonth;
    });
  }

  void _onSyncComplete() {
    _loadProducts();
    _loadDashboardData();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _printSafetyTimer?.cancel();
    _scanDebounce?.cancel();
    ConnectivityService.instance.removeListener(_onSyncComplete);
    _searchController.dispose();
    _searchFocus.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _customerNameFocus.dispose();
    _customerPhoneFocus.dispose();
    _addCustomerFocus.dispose();
    _customNameCtrl.dispose();
    _customPriceCtrl.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
      _toastVisible = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showSettings
                ? _buildSettingsPanel()
                : Column(
                    key: const ValueKey('main'),
                    children: [
                      _buildTopBar(),
                      _buildUpdateBanner(),
                      Expanded(
                        child: IndexedStack(
                          index: _selectedTab,
                          children: [
                            _buildDashboardView(),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildLeftPanel(),
                                _buildResizeDivider(),
                                _buildRightPanel(),
                              ],
                            ),
                            _buildInventoryView(),
                            _buildReportsView(),
                            _buildUtilitiesView(),
                          ],
                        ),
                      ),
                      _buildBottomBar(),
                    ],
                  ),
          ),
          // ── Top toast ──
          _buildToast(),
          // ── Print loading overlay ──
          if (_isPrinting) _buildPrintingOverlay(),
        ],
      ),
    );
  }

  Widget _buildPrintingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Preparing\nReceipt...',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D1D1F),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Toast ────────────────────────────────────────────────────────────────

  Widget _buildToast() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 380),
      curve: _toastVisible ? Curves.easeOutBack : Curves.easeIn,
      top: _toastVisible ? 24 : -80,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          opacity: _toastVisible ? 1.0 : 0.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _toastIsError
                  ? const Color(0xFFB71C1C)
                  : const Color(0xFF1D1D1F),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _toastIsError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  color: _toastIsError
                      ? Colors.red[200]
                      : const Color(0xFF4CAF50),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _toastMessage,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Update Banner ────────────────────────────────────────────────────────────

  Widget _buildUpdateBanner() {
    if (_updateInfo == null || _updateDismissed) return const SizedBox.shrink();
    final info = _updateInfo!;
    final isDownloading = _downloadProgress != null && _downloadProgress! < 1.0;
    final isDone = _downloadProgress != null && _downloadProgress! >= 1.0;
    final bannerColor = info.mandatory
        ? AppColors.error
        : const Color(0xFF1565C0);

    return Material(
      color: bannerColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDownloading
                        ? 'Installing BillCat ${info.version}...'
                        : 'BillCat ${info.version} is available'
                              '${info.releaseNotes.isNotEmpty ? ' — ${info.releaseNotes}' : ''}',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                if (!isDownloading && !isDone)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: _installUpdate,
                    child: const Text(
                      'Install Update',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (!info.mandatory && !isDownloading) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _updateDismissed = true;
                      _downloadProgress = null;
                    }),
                    tooltip: 'Dismiss',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: Colors.white.withValues(alpha: 0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${((_downloadProgress ?? 0) * 100).toInt()}%',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Logo
          Image.asset('assets/images/billcat_icon.png', height: 100),
          const SizedBox(width: 20),
          // Nav tabs
          if (!_ownerLockEnabled || _isOwnerMode) ...[
            _navTab('Dashboard', 0),
            const SizedBox(width: 4),
          ],
          _navTab('Billing', 1),
          const SizedBox(width: 4),
          _navTab('Inventory', 2),
          if (!_ownerLockEnabled || _isOwnerMode) ...[
            const SizedBox(width: 4),
            _reportsDropdownTab(),
            const SizedBox(width: 4),
            _utilitiesDropdownTab(),
          ],
          const Spacer(),
          _topBarIconBtn(
            Icons.assignment_return_outlined,
            'Return / Exchange',
            _showReturnDialog,
          ),
          const SizedBox(width: 8),
          // Lock icon only shown when staff access control is enabled
          if (_ownerLockEnabled) ...[
            _topBarIconBtn(
              _isOwnerMode
                  ? Icons.lock_open_outlined
                  : Icons.lock_outline_rounded,
              _isOwnerMode ? 'Lock (Staff Mode)' : 'Owner Access',
              _isOwnerMode ? _lockOwnerMode : _showOwnerPasscodeDialog,
            ),
            const SizedBox(width: 8),
          ],
          // Print Barcodes (Inventory tab) or Printer (other tabs)
          if (_selectedTab == 2) ...[
            GestureDetector(
              onTap: () {
                _bulkPrintQtys = {
                  for (final p in _products) p.id: p.stock > 0 ? p.stock : 1,
                };
                _bulkPrintSelected = {}; // start empty — user adds via search
                _bulkPrinters = ['System Default'];
                Printing.listPrinters()
                    .then((printers) {
                      final list = <String>[
                        'System Default',
                        ...printers.map((p) => p.name),
                      ];
                      if (mounted) setState(() => _bulkPrinters = list);
                    })
                    .catchError((_) {});
                _showBulkPrintDialog();
              },
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.barcode_reader,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Print Barcodes',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_selectedTab != 2) ...[
            const SizedBox(width: 8),
            _topBarIconBtn(Icons.print_outlined, 'Printer', _showPrinterDialog),
          ],
          const SizedBox(width: 8),
          _topBarIconBtn(Icons.settings_outlined, 'Settings', _openSettings),
          const SizedBox(width: 16),
          // Profile avatar
          _buildProfileMenu(),
        ],
      ),
    );
  }

  Widget _navTab(String label, int index) {
    final selected = _selectedTab == index;
    return _NavHoverTab(
      selected: selected,
      onTap: () => setState(() => _selectedTab = index),
      label: label,
    );
  }

  Widget _reportsDropdownTab() {
    final selected = _selectedTab == 3;
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Colors.white,
      elevation: 4,
      onSelected: (value) {
        setState(() {
          _selectedTab = 3;
          _reportView = value;
        });
        if (value == 'Customers') _loadReportCustomers();
      },
      itemBuilder: (_) => ['Sales', 'Customers', 'Inventory', 'Dealers']
          .map(
            (v) => PopupMenuItem<String>(
              value: v,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    switch (v) {
                      'Sales' => Icons.bar_chart_rounded,
                      'Customers' => Icons.people_alt_outlined,
                      'Dealers' => Icons.local_shipping_outlined,
                      _ => Icons.inventory_2_outlined,
                    },
                    size: 16,
                    color: (selected && _reportView == v)
                        ? AppColors.accentBlue
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    v,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: (selected && _reportView == v)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: (selected && _reportView == v)
                          ? AppColors.accentBlue
                          : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: _DropdownNavHover(
        selected: selected,
        label: selected ? _reportView : 'Reports',
      ),
    );
  }

  Widget _utilitiesDropdownTab() {
    final selected = _selectedTab == 4;
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Colors.white,
      elevation: 4,
      onSelected: (value) {
        setState(() {
          _selectedTab = 4;
          _utilitiesView = value;
        });
      },
      itemBuilder: (_) => ['Delivery']
          .map(
            (v) => PopupMenuItem<String>(
              value: v,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    switch (v) {
                      'Delivery' => Icons.local_shipping_outlined,
                      _ => Icons.build_outlined,
                    },
                    size: 16,
                    color: (selected && _utilitiesView == v)
                        ? AppColors.accentBlue
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    v,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: (selected && _utilitiesView == v)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: (selected && _utilitiesView == v)
                          ? AppColors.accentBlue
                          : AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: _DropdownNavHover(
        selected: selected,
        label: selected ? _utilitiesView : 'Utilities',
      ),
    );
  }

  // ── Left Panel ───────────────────────────────────────────────────────────────

  Widget _buildLeftPanel() {
    return Expanded(
      flex: 62,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            _HoverShadowBox(
              borderRadius: 14,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        autofocus: true,
                        onChanged: (v) {
                          // Barcode scans are handled globally by _handleGlobalKey
                          // (works even when this box isn't focused); here we only
                          // drive the live product filter as the user types.
                          setState(() => _searchQuery = v);
                        },
                        onSubmitted: (v) {
                          // If a scan was just processed globally, its Enter/text
                          // may still echo here — ignore it so we neither add twice
                          // nor flash a false "not found".
                          if (DateTime.now()
                                  .difference(_lastScanAddedAt)
                                  .inMilliseconds <
                              600) {
                            return;
                          }
                          final query = v.trim();
                          if (query.isEmpty) {
                            _searchFocus.requestFocus();
                            return;
                          }
                          // Manual lookup: variant code/SKU, then product barcode,
                          // exact SKU, exact name, partial SKU.
                          final variantMatch = _matchVariantByCode(query);
                          if (variantMatch != null) {
                            context.read<CartProvider>().addVariant(
                              variantMatch.$1,
                              variantMatch.$2,
                            );
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                            _showToast(
                              '${variantMatch.$1.name} (${variantMatch.$2.label}) added to cart',
                            );
                            _searchFocus.requestFocus();
                            return;
                          }
                          Product? match = _products
                              .cast<Product?>()
                              .firstWhere(
                                (p) => _barcodeMatches(p!.barcodeNo, query),
                                orElse: () => null,
                              );
                          match ??= _products.cast<Product?>().firstWhere(
                            (p) => p!.sku.toLowerCase() == query.toLowerCase(),
                            orElse: () => null,
                          );
                          match ??= _products.cast<Product?>().firstWhere(
                            (p) => p!.name.toLowerCase() == query.toLowerCase(),
                            orElse: () => null,
                          );
                          match ??= _products.cast<Product?>().firstWhere(
                            (p) => p!.sku.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                            orElse: () => null,
                          );
                          if (match != null) {
                            final hasVariants =
                                (_variantsByProduct[match.id] ?? const [])
                                    .isNotEmpty;
                            if (hasVariants) {
                              _addToCartOrPickVariant(
                                match,
                                context.read<CartProvider>(),
                              );
                            } else {
                              context.read<CartProvider>().addProduct(match);
                              _showToast('${match.name} added to cart');
                            }
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          } else {
                            _showToast(
                              'No product found for "$query"',
                              isError: true,
                            );
                          }
                          _searchFocus.requestFocus();
                        },
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Scan or type item name...',
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.textMuted.withValues(alpha: 0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () => setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(width: 16),
                  ],
                ),
              ),
            ), // _HoverShadowBox
            const SizedBox(height: 20),
            // Category chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    [
                      'All',
                      ..._userCategories.where(
                        (c) => _products.any((p) => p.category == c),
                      ),
                    ].map((cat) {
                      final selected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _CategoryChip(
                          label: cat,
                          selected: selected,
                          onTap: () => setState(() => _selectedCategory = cat),
                        ),
                      );
                    }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            // Product grid
            Expanded(
              child: Consumer<CartProvider>(
                builder: (context, cart, _) {
                  final controller = ScrollController();
                  return Scrollbar(
                    controller: controller,
                    thickness: 4,
                    radius: const Radius.circular(4),
                    thumbVisibility: false,
                    child: GridView.builder(
                      controller: controller,
                      padding: const EdgeInsets.only(right: 8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 20,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: _displayGridItems.length,
                      itemBuilder: (_, i) {
                        final item = _displayGridItems[i];
                        if (item is Product) {
                          return _ProductCard(
                            product: item,
                            onTap: () {
                              final variants =
                                  _variantsByProduct[item.id] ??
                                  const <ProductVariant>[];
                              if (variants.isEmpty) {
                                // No variants → add straight to the cart.
                                cart.addProduct(item);
                              } else {
                                // Has variants → slide the variant cards out
                                // inline (tap again to collapse), same as the
                                // chevron arrow.
                                setState(() {
                                  _expandedVariantProductId =
                                      _expandedVariantProductId == item.id
                                      ? null
                                      : item.id;
                                });
                              }
                            },
                            currencySymbol: _currencySymbol,
                            variants: _variantsByProduct[item.id] ?? const [],
                            effectiveTaxRate: item.taxPercent > 0
                                ? item.taxPercent
                                : (double.tryParse(_taxRateDisplay) ?? 0),
                            taxLabel: _taxLabel,
                            variantsExpanded:
                                _expandedVariantProductId == item.id,
                            onVariantArrowTap: () => setState(() {
                              _expandedVariantProductId =
                                  _expandedVariantProductId == item.id
                                  ? null
                                  : item.id;
                            }),
                          );
                        }
                        final pair = item as (Product, ProductVariant);
                        return _VariantCard(
                          product: pair.$1,
                          variant: pair.$2,
                          currencySymbol: _currencySymbol,
                          effectiveTaxRate: pair.$1.taxPercent > 0
                              ? pair.$1.taxPercent
                              : (double.tryParse(_taxRateDisplay) ?? 0),
                          taxLabel: _taxLabel,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Right Panel ──────────────────────────────────────────────────────────────

  Widget _buildResizeDivider() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _rightPanelWidth = (_rightPanelWidth - details.delta.dx).clamp(
            375.0,
            580.0,
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(child: Container(width: 1, color: AppColors.border)),
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      width: _rightPanelWidth,
      color: Colors.white,
      child: Consumer<CartProvider>(
        builder: (context, cart, _) => Column(
          children: [
            _buildCustomerBar(cart),
            _buildCartTable(cart),
            _buildSummary(cart),
            _buildPaymentMethods(cart),
            _buildActionButtons(context, cart),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerBar(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Customer Name with autocomplete
          Expanded(
            flex: 1,
            child: _customerAutocomplete(
              controller: _customerNameCtrl,
              focusNode: _customerNameFocus,
              icon: Icons.person_outline_rounded,
              hint: 'Customer Name',
              filterFn: (c, q) =>
                  c.name.toLowerCase().contains(q.toLowerCase()),
              displayFn: (c) => c.name,
              onChanged: (v) {
                cart.customerName = v;
                setState(() {});
              },
              textInputAction: TextInputAction.next,
              onOptionsChanged: (opts) => _nameAcOptions = opts,
              currentOptions: _nameAcOptions,
              onFieldSubmitted: () => _customerPhoneFocus.requestFocus(),
              onSelected: (c) {
                _customerNameCtrl.text = c.name;
                _customerPhoneCtrl.text = c.phone ?? '';
                cart.customerName = c.name;
                cart.customerPhone = c.phone ?? '';
                setState(() {});
                if (!_acSkipRefocus)
                  Future.microtask(() => _customerNameFocus.requestFocus());
                _acSkipRefocus = false;
              },
            ),
          ),
          const SizedBox(width: 10),
          // Phone with autocomplete
          Expanded(
            flex: 1,
            child: _customerAutocomplete(
              controller: _customerPhoneCtrl,
              focusNode: _customerPhoneFocus,
              icon: Icons.phone_outlined,
              hint: 'Phone Number',
              filterFn: (c, q) => (c.phone ?? '').contains(q),
              displayFn: (c) => c.phone ?? '',
              onChanged: (v) {
                cart.customerPhone = v;
                setState(() {});
              },
              onOptionsChanged: (opts) => _phoneAcOptions = opts,
              currentOptions: _phoneAcOptions,
              onSelected: (c) {
                _customerNameCtrl.text = c.name;
                _customerPhoneCtrl.text = c.phone ?? '';
                cart.customerName = c.name;
                cart.customerPhone = c.phone ?? '';
                setState(() {});
                if (!_acSkipRefocus)
                  Future.microtask(() => _customerPhoneFocus.requestFocus());
                _acSkipRefocus = false;
              },
              keyboardType: TextInputType.phone,
              onFieldSubmitted: () {
                final name = _customerNameCtrl.text.trim();
                final phone = _customerPhoneCtrl.text.trim();
                final hasData = name.isNotEmpty || phone.isNotEmpty;
                if (hasData) {
                  final isSaved = _savedCustomers.any(
                    (c) =>
                        (name.isNotEmpty &&
                            c.name.toLowerCase() == name.toLowerCase()) ||
                        (phone.isNotEmpty && (c.phone ?? '') == phone),
                  );
                  if (!isSaved) {
                    _customerPhoneFocus.unfocus();
                    _showAddCustomerDialog(cart);
                    return;
                  }
                }
                _addCustomerFocus.requestFocus();
              },
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          const SizedBox(width: 10),
          ListenableBuilder(
            listenable: Listenable.merge([
              _customerNameCtrl,
              _customerPhoneCtrl,
            ]),
            builder: (context, _) {
              final name = _customerNameCtrl.text.trim();
              final phone = _customerPhoneCtrl.text.trim();
              final hasData = name.isNotEmpty || phone.isNotEmpty;

              if (hasData) {
                final isSaved = _savedCustomers.any(
                  (c) =>
                      (name.isNotEmpty &&
                          c.name.toLowerCase() == name.toLowerCase()) ||
                      (phone.isNotEmpty && (c.phone ?? '') == phone),
                );

                if (isSaved) {
                  // saved customer → subtle clear-customer button
                  return Tooltip(
                    message: 'Clear customer',
                    child: GestureDetector(
                      onTap: () {
                        _customerNameCtrl.clear();
                        _customerPhoneCtrl.clear();
                        cart.customerName = '';
                        cart.customerPhone = '';
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.person_remove_outlined,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                      ),
                    ),
                  );
                } else {
                  // new customer → dark add-person button that saves directly
                  return GestureDetector(
                    onTap: () async {
                      if (name.isEmpty) return;
                      await LocalDbService.upsertCustomerByPhone(
                        name: name,
                        phone: phone.isEmpty ? null : phone,
                      );
                      cart.customerName = name;
                      cart.customerPhone = phone;
                      await _loadSavedCustomers();
                      if (ConnectivityService.instance.isOnline) {
                        ConnectivityService.instance.syncNow();
                      }
                      if (mounted) _showToast('Customer saved!');
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  );
                }
              }

              return Focus(
                focusNode: _addCustomerFocus,
                child: GestureDetector(
                  onTap: () => _showAddCustomerDialog(cart),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _customerAutocomplete({
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required String hint,
    required bool Function(Customer, String) filterFn,
    required String Function(Customer) displayFn,
    required ValueChanged<String> onChanged,
    required ValueChanged<Customer> onSelected,
    required void Function(List<Customer>) onOptionsChanged,
    required List<Customer> currentOptions,
    TextInputType? keyboardType,
    VoidCallback? onFieldSubmitted,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return RawAutocomplete<Customer>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (v) {
        if (v.text.trim().isEmpty) {
          onOptionsChanged([]);
          return const [];
        }
        final opts = _savedCustomers
            .where((c) => filterFn(c, v.text))
            .take(6)
            .toList();
        onOptionsChanged(opts);
        return opts;
      },
      displayStringForOption: displayFn,
      onSelected: onSelected,
      fieldViewBuilder: (context, textCtrl, fn, onSubmit) {
        return Container(
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.5),
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 10),
              Icon(icon, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: textCtrl,
                  focusNode: fn,
                  onChanged: onChanged,
                  textInputAction: textInputAction ?? TextInputAction.done,
                  onSubmitted: (_) {
                    if (currentOptions.isNotEmpty) {
                      final first = currentOptions.first;
                      _acSkipRefocus = true;
                      onOptionsChanged([]);
                      fn.unfocus();
                      onSelected(first);
                    } else {
                      onSubmit();
                      onFieldSubmitted?.call();
                    }
                  },
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        );
      },
      optionsViewBuilder: (context, onSel, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final c = options.elementAt(i);
                final isFirst = i == 0;
                return InkWell(
                  onTap: () => onSel(c),
                  child: Container(
                    color: isFirst
                        ? AppColors.primary.withValues(alpha: 0.07)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: isFirst
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: isFirst
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isFirst
                                      ? AppColors.primary
                                      : AppColors.textDark,
                                ),
                              ),
                              if (c.phone != null && c.phone!.isNotEmpty)
                                Text(
                                  c.phone!,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isFirst
                                        ? AppColors.primary.withValues(
                                            alpha: 0.7,
                                          )
                                        : AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerField({
    required IconData icon,
    required String hint,
    required Function(String) onChanged,
    TextInputType? keyboardType,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: onChanged,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textDark,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: AppColors.textMuted.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 16),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCartTable(CartProvider cart) {
    return Expanded(
      child: ClipRect(
        child: Column(
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: AppColors.surfaceVariant,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'DESCRIPTION',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'QTY',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'AMOUNT',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              ),
            ),
            // Cart items
            Expanded(
              child: (cart.items.isEmpty && !_addingCustomProduct)
                  ? Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 40,
                              color: AppColors.border,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No items added',
                              style: GoogleFonts.inter(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _addingCustomProduct = true;
                                _customNameCtrl.clear();
                                _customPriceCtrl.clear();
                              }),
                              icon: const Icon(Icons.add_rounded, size: 15),
                              label: Text(
                                'Custom Product',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                side: const BorderSide(color: AppColors.border),
                                foregroundColor: AppColors.textDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: cart.items.length + 1,
                      separatorBuilder: (_, i) => i < cart.items.length - 1
                          ? const Divider(
                              height: 1,
                              thickness: 0.5,
                              color: AppColors.border,
                              indent: 8,
                              endIndent: 8,
                            )
                          : const SizedBox.shrink(),
                      itemBuilder: (_, i) {
                        if (i == cart.items.length) {
                          return _addingCustomProduct
                              ? _buildInlineCustomRow(cart)
                              : _addCustomProductBtn(cart);
                        }
                        return _CartRow(
                          item: cart.items[i],
                          cart: cart,
                          currencySymbol: _currencySymbol,
                          taxLabel: _taxLabel,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addCustomProductBtn(CartProvider cart) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: OutlinedButton.icon(
        onPressed: () => setState(() {
          _addingCustomProduct = true;
          _customNameCtrl.clear();
          _customPriceCtrl.clear();
        }),
        icon: const Icon(Icons.add, size: 18, color: AppColors.primary),
        label: Text(
          'CUSTOM PRODUCT',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 0.8,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCustomRow(CartProvider cart) {
    void confirm() {
      final name = _customNameCtrl.text.trim();
      final price = double.tryParse(_customPriceCtrl.text) ?? 0;
      if (name.isNotEmpty && price > 0) {
        cart.addProduct(
          Product(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            price: price,
            category: 'Custom',
            emoji: '📦',
            sku: 'CUSTOM',
            stock: 99,
          ),
        );
        setState(() => _addingCustomProduct = false);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FF),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text('📦', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _customNameCtrl,
              autofocus: true,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration.collapsed(
                hintText: 'Item name',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              onSubmitted: (_) => confirm(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _customPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration.collapsed(
                hintText: 'Price',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              textAlign: TextAlign.right,
              onSubmitted: (_) => confirm(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: confirm,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _addingCustomProduct = false),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          _summaryRow('SUBTOTAL', cart.subtotal),
          const SizedBox(height: 10),
          // Discount row
          Row(
            children: [
              Text(
                'DISCOUNT',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 10),
              _DiscountToggle(cart: cart, currencySymbol: _currencySymbol),
              const Spacer(),
              Text(
                '-$_currencySymbol${cart.discountAmount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tax rows — one per distinct rate in the cart. Products carry their
          // own rate; the store-wide rate covers products that don't set one.
          ...() {
            final breakdown = cart.taxBreakdown;
            if (breakdown.isEmpty) {
              // Nothing taxable yet — keep the store rate visible and editable.
              return [
                _TaxSummaryRow(
                  label: 'TAX ($_taxLabel $_taxRateDisplay%)',
                  amount: 0,
                  currencySymbol: _currencySymbol,
                  rate: _taxRateDisplay,
                  onRateChanged: _applyTaxRate,
                ),
              ];
            }
            final rates = breakdown.keys.toList()..sort();
            return [
              for (int i = 0; i < rates.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _summaryRow(
                  'TAX ($_taxLabel ${_formatRate(rates[i])}%)',
                  breakdown[rates[i]]!,
                ),
              ],
            ];
          }(),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL PAYABLE',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_currencySymbol${cart.total.toStringAsFixed(2)}',
                    style: GoogleFonts.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${cart.itemCount} ITEMS',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Live price breakdown shown in the product dialogs: base price, the tax it
  /// attracts, and the final customer-facing price. An empty tax field falls
  /// back to the store-wide rate, matching how the cart charges it.
  Widget _finalPriceCard(String priceText, String taxText) {
    final base = double.tryParse(priceText) ?? 0;
    final typedRate = double.tryParse(taxText);
    final rate = (typedRate != null && typedRate > 0)
        ? typedRate
        : (double.tryParse(_taxRateDisplay) ?? 0);
    final taxAmount = base * rate / 100;
    final finalPrice = base + taxAmount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.055),
            AppColors.accentBlue.withValues(alpha: 0.045),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Base price',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '$_currencySymbol${base.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(
                '$_taxLabel ${_formatRate(rate)}%',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              if (typedRate == null || typedRate <= 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'store default',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '+ $_currencySymbol${taxAmount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: AppColors.primary.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FINAL PRICE',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'What the customer pays',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: AppColors.textMuted.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '$_currencySymbol${finalPrice.toStringAsFixed(2)}',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shelf price for a product: its price plus the tax it attracts (its own
  /// rate, or the store default). This is what goes on barcode labels so the
  /// sticker matches what the customer is charged at the till.
  double _finalPriceOf(Product p) {
    final rate = p.taxPercent > 0
        ? p.taxPercent
        : (double.tryParse(_taxRateDisplay) ?? 0);
    return p.price * (1 + rate / 100);
  }

  // Splits a "Product Name (Variant)" label into a product-name line and, if
  // present, a separate variant line below it — so the variant never gets
  // truncated off the edge of a barcode label.
  List<pw.Widget> _labelNameWidgets(String fullName, pw.Font bold) {
    String main = fullName;
    String? variant;
    final m = RegExp(r'^(.*)\s*\((.+)\)\s*$').firstMatch(fullName);
    if (m != null) {
      main = m.group(1)!.trim();
      variant = m.group(2)!.trim();
    }
    return [
      pw.Text(
        main,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(font: bold, fontSize: 4.5, letterSpacing: 0.4),
        textAlign: pw.TextAlign.center,
      ),
      if (variant != null && variant.isNotEmpty)
        pw.Text(
          variant,
          maxLines: 1,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(font: bold, fontSize: 3.8, letterSpacing: 0.3),
          textAlign: pw.TextAlign.center,
        ),
    ];
  }

  // 5.0 -> "5", 12.5 -> "12.5"
  String _formatRate(double r) =>
      r == r.truncateToDouble() ? r.toStringAsFixed(0) : r.toString();

  Widget _summaryRow(String label, double amount) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Text(
          '$_currencySymbol${amount.toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods(CartProvider cart) {
    const methods = [
      (PaymentMethod.cash, 'Cash'),
      (PaymentMethod.card, 'Card'),
      (PaymentMethod.upi, 'UPI/QR'),
      (PaymentMethod.hybrid, 'Hybrid'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT METHOD',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            spacing: 8,
            children: methods.map((m) {
              final selected = cart.paymentMethod == m.$1;
              return Expanded(
                child: GestureDetector(
                  onTap: () => cart.setPaymentMethod(m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accentBlue.withValues(alpha: 0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: selected
                            ? AppColors.accentBlue
                            : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accentBlue
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? AppColors.accentBlue
                                  : AppColors.border,
                              width: 1.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            m.$2.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              letterSpacing: 0.5,
                              color: selected
                                  ? AppColors.accentBlue
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, CartProvider cart) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cart.items.isEmpty
                      ? null
                      : () => _confirmClear(context, cart),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: Text(
                    'CLEAR BILL',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (cart.items.isEmpty || _isPrinting)
                      ? null
                      : () => _showPrintBillDialog(cart),
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: Text(
                    'PRINT BILL',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    disabledBackgroundColor: AppColors.border,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: cart.items.isEmpty
                  ? null
                  : () => _closeBill(context, cart),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
              label: Text(
                'Paid - Close Bill',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                disabledBackgroundColor: AppColors.border,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ───────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _bottomBarBtn(Icons.keyboard_outlined, 'SHORTCUTS'),
          const SizedBox(width: 4),
          _bottomBarBtn(
            Icons.inventory_2_outlined,
            'INVENTORY',
            onPressed: () => setState(() => _selectedTab = 2),
          ),
          const SizedBox(width: 4),
          _bottomBarBtn(Icons.receipt_outlined, 'LAST RECEIPT'),
          const Spacer(),
          Text(
            'POS T-01  •  SESSION: ${TimeOfDay.now().format(context)}  •  ${_sessionUserLabel()}',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w300,
              color: AppColors.textMuted.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBarBtn(IconData icon, String label, {VoidCallback? onPressed}) {
    return TextButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, size: 14, color: AppColors.textMuted),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
          letterSpacing: 0.8,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
      ),
    );
  }

  String _sessionUserLabel() {
    final email = SupabaseService.currentUser?.email ?? '';
    final local = email.split('@').first;
    final parts = local.split(RegExp(r'[._\-]'));
    if (parts.length >= 2) {
      return '${parts[0].toUpperCase()} ${parts[1][0].toUpperCase()}.';
    }
    return local.toUpperCase();
  }

  // ── Top bar helper ───────────────────────────────────────────────────────────

  Widget _topBarIconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.textMuted),
        ),
      ),
    );
  }

  // ── Profile menu ─────────────────────────────────────────────────────────────

  Widget _buildProfileMenu() {
    final user = SupabaseService.currentUser;
    final email = user?.email ?? 'user@example.com';
    final initials = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      color: Colors.white,
      onSelected: (value) {
        if (value == 'logout') _confirmLogout(context);
        if (value == 'profile') _showProfileDialog(email);
      },
      itemBuilder: (_) => [
        // Header — non-interactive user info
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Account',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'profile',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Text(
                'Profile',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'logout',
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 16,
                color: AppColors.error,
              ),
              const SizedBox(width: 10),
              Text(
                'Logout',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initials,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _uploadLogoToCloud(String localPath) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return '';
      final bytes = await File(localPath).readAsBytes();
      final ext = localPath.split('.').last.toLowerCase();
      await client.storage
          .from('logos')
          .uploadBinary(
            '$userId.$ext',
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final url = client.storage.from('logos').getPublicUrl('$userId.$ext');
      // Persist URL in auth user metadata so it syncs across devices
      await client.auth.updateUser(UserAttributes(data: {'logo_url': url}));
      return url;
    } catch (e) {
      debugPrint('Logo upload failed: $e');
      return '';
    }
  }

  void _showProfileDialog(String email) {
    _editStoreName = _storeName;
    _editStoreAddress = _storeAddress;
    _editStorePhone = _storePhone;
    _editStoreEmail = _storeEmail;
    _editStoreGstin = _storeGstin;
    _editStoreUpiId = _storeUpiId;
    _editBranchNumber = _branchNumber;
    _editLogoPath = _logoPath;
    _editLogoUrl = _logoUrl;

    String dialogLogoPath = _logoPath;
    String dialogLogoUrl = _logoUrl;
    bool isSaving = false;

    final initials = _storeName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: const Color(0xFFF2F2F7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  color: AppColors.primary,
                  child: Row(
                    children: [
                      // Tappable logo
                      GestureDetector(
                        onTap: () async {
                          final r = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                          );
                          if (r?.files.single.path != null) {
                            final copied =
                                await LocalDbService.copyImageToAppDir(
                                  r!.files.single.path!,
                                );
                            setDlg(() {
                              dialogLogoPath = copied;
                              _editLogoPath = copied;
                            });
                          }
                        },
                        child: Stack(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: dialogLogoPath.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Image.file(
                                        File(dialogLogoPath),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _logoFallback(initials),
                                      ),
                                    )
                                  : dialogLogoUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: Image.network(
                                        dialogLogoUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _logoFallback(initials),
                                      ),
                                    )
                                  : _logoFallback(initials),
                            ),
                            // Camera overlay
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _editStoreName.isNotEmpty
                                  ? _editStoreName
                                  : _storeName,
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () async {
                                final r = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                );
                                if (r?.files.single.path != null) {
                                  final copied =
                                      await LocalDbService.copyImageToAppDir(
                                        r!.files.single.path!,
                                      );
                                  setDlg(() {
                                    dialogLogoPath = copied;
                                    _editLogoPath = copied;
                                  });
                                }
                              },
                              child: Text(
                                dialogLogoPath.isNotEmpty ||
                                        dialogLogoUrl.isNotEmpty
                                    ? 'Change logo'
                                    : 'Upload logo',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.accent,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dialogLogoPath.isNotEmpty)
                        GestureDetector(
                          onTap: () => setDlg(() {
                            dialogLogoPath = '';
                            dialogLogoUrl = '';
                            _editLogoPath = '';
                            _editLogoUrl = '';
                          }),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Scrollable fields ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _settingsSectionHeader('BUSINESS DETAILS'),
                        _settingsCard([
                          _settingsTextField(
                            'Business Name',
                            _editStoreName,
                            (v) => _editStoreName = v,
                          ),
                          _settingsDivider(),
                          _settingsTextField(
                            'Address',
                            _editStoreAddress,
                            (v) => _editStoreAddress = v,
                            maxLines: 2,
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _settingsSectionHeader('CONTACT INFO'),
                        _settingsCard([
                          _settingsTextField(
                            'Phone Number',
                            _editStorePhone,
                            (v) => _editStorePhone = v,
                            keyboardType: TextInputType.phone,
                          ),
                          _settingsDivider(),
                          _settingsTextField(
                            'Business Email',
                            _editStoreEmail,
                            (v) => _editStoreEmail = v,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _settingsSectionHeader('TAX & PAYMENTS'),
                        _settingsCard([
                          _settingsTextField(
                            'GSTIN',
                            _editStoreGstin,
                            (v) => _editStoreGstin = v,
                          ),
                          _settingsDivider(),
                          _settingsTextField(
                            'UPI ID',
                            _editStoreUpiId,
                            (v) => _editStoreUpiId = v,
                          ),
                          _settingsDivider(),
                          _settingsTextField(
                            'Branch Number',
                            _editBranchNumber,
                            (v) => setState(() => _editBranchNumber = v),
                            hint: 'e.g. 01',
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _settingsSectionHeader('BILLCAT ACCOUNT'),
                        _settingsCard([
                          Builder(
                            builder: (_) {
                              final rawUid =
                                  Supabase
                                      .instance
                                      .client
                                      .auth
                                      .currentUser
                                      ?.id ??
                                  '';
                              final shortId = rawUid.isEmpty
                                  ? '—'
                                  : rawUid
                                        .replaceAll('-', '')
                                        .substring(
                                          0,
                                          rawUid.length >= 6
                                              ? 6
                                              : rawUid.length,
                                        )
                                        .toUpperCase();
                              return Container(
                                constraints: const BoxConstraints(
                                  minHeight: 46,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'BillCat ID',
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF1C1C1E),
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(
                                          ClipboardData(text: shortId),
                                        );
                                        _showToast('BillCat ID copied!');
                                      },
                                      child: Row(
                                        children: [
                                          Text(
                                            shortId,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: const Color(0xFF8E8E93),
                                              fontFeatures: [
                                                const FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.copy_rounded,
                                            size: 14,
                                            color: Color(0xFF8E8E93),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ]),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // ── Footer ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2F2F7),
                    border: Border(
                      top: BorderSide(color: Color(0xFFD8D8DC), width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: isSaving
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _confirmLogout(context);
                              },
                        icon: const Icon(
                          Icons.logout_rounded,
                          size: 14,
                          color: AppColors.error,
                        ),
                        label: Text(
                          'Logout',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.error,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: isSaving ? null : () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          foregroundColor: AppColors.textMuted,
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setDlg(() => isSaving = true);
                                // Upload logo to cloud if a new local file was picked
                                if (_editLogoPath.isNotEmpty) {
                                  final url = await _uploadLogoToCloud(
                                    _editLogoPath,
                                  );
                                  if (url.isNotEmpty) _editLogoUrl = url;
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                setState(() {
                                  _storeName = _editStoreName.trim().isEmpty
                                      ? 'BillCat Store'
                                      : _editStoreName.trim();
                                  _storeAddress = _editStoreAddress.trim();
                                  _storePhone = _editStorePhone.trim();
                                  _storeEmail = _editStoreEmail.trim();
                                  _storeGstin = _editStoreGstin.trim();
                                  _storeUpiId = _editStoreUpiId.trim();
                                  _branchNumber =
                                      _editBranchNumber.trim().isEmpty
                                      ? '01'
                                      : _editBranchNumber.trim();
                                  _logoPath = _editLogoPath;
                                  _logoUrl = _editLogoUrl;
                                });
                                _persistSettings();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Save Changes',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoFallback(String initials) => Center(
    child: Text(
      initials.isNotEmpty ? initials : 'B',
      style: GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  // ── Settings panel (Apple-style) ─────────────────────────────────────────────

  void _openSettings() {
    setState(() {
      _editStoreName = _storeName;
      _editStoreAddress = _storeAddress;
      _editStorePhone = _storePhone;
      _editStoreEmail = _storeEmail;
      _editStoreGstin = _storeGstin;
      _editReceiptFooter = _receiptFooter;
      _editTaxLabel = _taxLabel;
      _editTaxRate = _taxRateDisplay;
      _editCurrencyCode = _currencyCode;
      _editCurrencySymbol = _currencySymbol;
      _editDialCode = _dialCode;
      _editPaperSize = _paperSize;
      _editAutoPrint = _autoPrint;
      _editInvoiceLayout = _invoiceLayout;
      _editPrintOrientation = _printOrientation;
      // Derive the tab from the saved paper size — hardcoding 'Regular' while
      // paper is a thermal size (e.g. '3 inch') left the Paper Size dropdown
      // with a value not in its item list, crashing the Settings screen.
      _editPrinterTab = ['A4', 'A5'].contains(_paperSize)
          ? 'Regular'
          : 'Thermal';
      _editStoreTerms = _storeTerms;
      _editLogoPath = _logoPath;
      _editLogoUrl = _logoUrl;
      _editStoreUpiId = _storeUpiId;
      _editBranchNumber = _branchNumber;
      _settingsPage = 'General';
      _showSettings = true;
    });
  }

  void _saveSettings() {
    setState(() {
      _storeName = _editStoreName.trim().isEmpty
          ? 'BillCat Store'
          : _editStoreName.trim();
      _storeAddress = _editStoreAddress.trim();
      _storePhone = _editStorePhone.trim();
      _storeEmail = _editStoreEmail.trim();
      _storeGstin = _editStoreGstin.trim();
      _receiptFooter = _editReceiptFooter.trim();
      _taxLabel = _editTaxLabel.trim().isEmpty ? 'GST' : _editTaxLabel.trim();
      _taxRateDisplay = _editTaxRate.trim().isEmpty ? '0' : _editTaxRate.trim();
      _syncTaxRate();
      _currencyCode = _editCurrencyCode;
      _currencySymbol = _editCurrencySymbol;
      _dialCode = _editDialCode;
      _paperSize = _editPaperSize;
      _autoPrint = _editAutoPrint;
      _invoiceLayout = _editInvoiceLayout;
      _printOrientation = _editPrintOrientation;
      _storeTerms = _editStoreTerms;
      _logoPath = _editLogoPath;
      _logoUrl = _editLogoUrl;
      _storeUpiId = _editStoreUpiId.trim();
      _branchNumber = _editBranchNumber.trim().isEmpty
          ? '01'
          : _editBranchNumber.trim();
      _waPhoneNumberId = _editWaPhoneNumberId.trim();
      _waAccessToken = _editWaAccessToken.trim();
      _showSettings = false;
    });
    _persistSettings();
  }

  Future<void> _persistSettings() async {
    await LocalDbService.saveSettings({
      'store_name': _storeName,
      'store_address': _storeAddress,
      'store_phone': _storePhone,
      'store_email': _storeEmail,
      'store_gstin': _storeGstin,
      'receipt_footer': _receiptFooter,
      'tax_label': _taxLabel,
      'tax_rate': _taxRateDisplay,
      'currency_code': _currencyCode,
      'currency_symbol': _currencySymbol,
      'dial_code': _dialCode,
      'paper_size': _paperSize,
      'selected_printer': _selectedPrinter,
      'print_orientation': _printOrientation,
      'invoice_layout': _invoiceLayout,
      'store_terms': _storeTerms,
      'logo_path': _logoPath,
      'logo_url': _logoUrl,
      'auto_print': _autoPrint ? '1' : '0',
      'store_upi_id': _storeUpiId,
      'branch_number': _branchNumber,
      'wa_phone_number_id': _waPhoneNumberId,
      'wa_access_token': _waAccessToken,
    });
    ConnectivityService.instance.syncNow();
  }

  static const _settingsNavItems = [
    (icon: Icons.storefront_outlined, label: 'General'),
    (icon: Icons.percent_rounded, label: 'Tax'),
    (icon: Icons.print_outlined, label: 'Printer'),
    (icon: Icons.person_outline_rounded, label: 'Account'),
    (icon: Icons.shield_outlined, label: 'Security'),
    (icon: Icons.chat_bubble_outline_rounded, label: 'WhatsApp'),
  ];

  Widget _buildSettingsPanel() {
    return Container(
      key: const ValueKey('settings'),
      color: const Color(0xFFF2F2F7),
      child: Column(
        children: [
          // ── header bar ──
          Container(
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showSettings = false),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                  label: Text(
                    'Back',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Settings',
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D1D1F),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── body: sidebar + content ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSettingsSidebar(),
                Container(width: 1, color: const Color(0xFFD8D8DC)),
                Expanded(child: _buildSettingsContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSidebar() {
    return Container(
      width: 200,
      color: const Color(0xFFF5F5F7),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _settingsNavItems.map((item) {
          final selected = _settingsPage == item.label;
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() => _settingsPage = item.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 16,
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFF8E8E93),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.primary
                              : const Color(0xFF3C3C43),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingsContent() {
    if (_settingsPage == 'Printer') return _buildSettingsPrinter();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: switch (_settingsPage) {
            'General' => _buildSettingsStore(),
            'Tax' => _buildSettingsTax(),
            'Account' => _buildSettingsAccount(),
            'Security' => _buildSettingsSecurity(),
            'WhatsApp' => _buildSettingsWhatsApp(),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  // ── Store ──
  Widget _buildSettingsStore() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('General', Icons.storefront_outlined),
        const SizedBox(height: 24),
        _settingsCard([
          _settingsTextField(
            'Store Name',
            _editStoreName,
            (v) => setState(() => _editStoreName = v),
          ),
          _settingsDivider(),
          _settingsTextField(
            'Store Address',
            _editStoreAddress,
            (v) => setState(() => _editStoreAddress = v),
          ),
        ]),
        const SizedBox(height: 24),
        _settingsSectionHeader('CURRENCY'),
        const SizedBox(height: 8),
        _settingsCard([
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                final result = await _showCurrencyPicker(
                  context,
                  _editCurrencyCode,
                );
                if (result != null) {
                  setState(() {
                    _editCurrencyCode = result.code;
                    _editCurrencySymbol = result.symbol;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Text(
                      _currencies
                          .firstWhere(
                            (c) => c.code == _editCurrencyCode,
                            orElse: () => _currencies.first,
                          )
                          .flag,
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_editCurrencyCode  $_editCurrencySymbol',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1D1D1F),
                            ),
                          ),
                          Text(
                            _currencies
                                .firstWhere(
                                  (c) => c.code == _editCurrencyCode,
                                  orElse: () => _currencies.first,
                                )
                                .name,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF6E6E73),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFC7C7CC),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _settingsSectionHeader('REGION'),
        const SizedBox(height: 8),
        _settingsCard([
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                final picked = await _showDialCodePicker(
                  context,
                  _editDialCode,
                );
                if (picked != null) setState(() => _editDialCode = picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.language_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Country Dial Code',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1D1D1F),
                            ),
                          ),
                          Text(
                            'Used for WhatsApp: $_editDialCode',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF6E6E73),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _editDialCode,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFC7C7CC),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  static const _dialCodes = [
    ('+91', '🇮🇳', 'India'),
    ('+1', '🇺🇸', 'United States'),
    ('+44', '🇬🇧', 'United Kingdom'),
    ('+971', '🇦🇪', 'UAE'),
    ('+966', '🇸🇦', 'Saudi Arabia'),
    ('+65', '🇸🇬', 'Singapore'),
    ('+60', '🇲🇾', 'Malaysia'),
    ('+92', '🇵🇰', 'Pakistan'),
    ('+880', '🇧🇩', 'Bangladesh'),
    ('+94', '🇱🇰', 'Sri Lanka'),
    ('+977', '🇳🇵', 'Nepal'),
    ('+61', '🇦🇺', 'Australia'),
    ('+49', '🇩🇪', 'Germany'),
    ('+33', '🇫🇷', 'France'),
    ('+81', '🇯🇵', 'Japan'),
    ('+86', '🇨🇳', 'China'),
    ('+55', '🇧🇷', 'Brazil'),
    ('+27', '🇿🇦', 'South Africa'),
    ('+234', '🇳🇬', 'Nigeria'),
    ('+254', '🇰🇪', 'Kenya'),
  ];

  Future<String?> _showDialCodePicker(
    BuildContext context,
    String current,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Select Country',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final (code, flag, name) in _dialCodes)
            ListTile(
              leading: Text(flag, style: const TextStyle(fontSize: 22)),
              title: Text(name, style: GoogleFonts.inter(fontSize: 14)),
              trailing: Text(
                code,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              selected: code == current,
              selectedTileColor: AppColors.primary.withValues(alpha: 0.06),
              onTap: () => Navigator.pop(ctx, code),
            ),
        ],
      ),
    );
  }

  // ── Tax ──
  Widget _buildSettingsTax() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('Tax', Icons.percent_rounded),
        const SizedBox(height: 24),
        _settingsCard([
          _settingsTextField(
            'Tax Label',
            _editTaxLabel,
            (v) => setState(() => _editTaxLabel = v),
          ),
          _settingsDivider(),
          _settingsTextField(
            'Tax Rate (%)',
            _editTaxRate,
            (v) => setState(() => _editTaxRate = v),
            keyboardType: TextInputType.number,
          ),
        ]),
      ],
    );
  }

  // ── Receipt ──
  Widget _buildSettingsReceipt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('Receipt', Icons.receipt_long_outlined),
        const SizedBox(height: 24),
        _settingsCard([
          _settingsTextField(
            'Receipt Footer',
            _editReceiptFooter,
            (v) => setState(() => _editReceiptFooter = v),
            maxLines: 3,
          ),
        ]),
      ],
    );
  }

  // ── Printer ──
  Widget _buildSettingsPrinter() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Left: settings column ──────────────────────────────────────
        SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsPageTitle('Print Settings', Icons.print_outlined),
                const SizedBox(height: 20),

                // Printer type tabs (Regular / Thermal)
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEF0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (final t in ['Regular', 'Thermal'])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _editPrinterTab = t;
                              const reg = [
                                'Classic',
                                'Simple',
                                'Modern',
                                'GST',
                                'Landscape',
                              ];
                              const thm = [
                                'Theme 1',
                                'Theme 2',
                                'Theme 3',
                                'Theme 4',
                                'Theme 5',
                              ];
                              final valid = t == 'Regular' ? reg : thm;
                              if (!valid.contains(_editInvoiceLayout)) {
                                _editInvoiceLayout = t == 'Regular'
                                    ? 'Classic'
                                    : 'Theme 1';
                              }
                              _editPaperSize = t == 'Regular' ? 'A4' : '3 inch';
                              _previewRevision++;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: _editPrinterTab == t
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _editPrinterTab == t
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Center(
                                child: Text(
                                  '$t Printer',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: _editPrinterTab == t
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: _editPrinterTab == t
                                        ? const Color(0xFF1D1D1F)
                                        : const Color(0xFF6E6E73),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Invoice layout themes
                _settingsSectionHeader('INVOICE LAYOUT'),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    const reg = [
                      'Classic',
                      'Simple',
                      'Modern',
                      'GST',
                      'Landscape',
                    ];
                    const thm = [
                      'Theme 1',
                      'Theme 2',
                      'Theme 3',
                      'Theme 4',
                      'Theme 5',
                    ];
                    final layouts = _editPrinterTab == 'Regular' ? reg : thm;
                    return SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        itemCount: layouts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final layout = layouts[i];
                          final selected = _editInvoiceLayout == layout;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _editInvoiceLayout = layout;
                                _invoiceLayout = layout;
                                _previewRevision++;
                              });
                              LocalDbService.saveSettings({
                                'invoice_layout': layout,
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 88,
                              height: 100,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary.withValues(alpha: 0.06)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : const Color(0xFFD8D8DC),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _layoutThumb(layout, selected: selected),
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      layout,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: selected
                                            ? AppColors.primary
                                            : const Color(0xFF6E6E73),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Company info
                _settingsSectionHeader('COMPANY INFO / HEADER'),
                const SizedBox(height: 8),
                _settingsCard([
                  _settingsTextField(
                    'Company Name',
                    _editStoreName,
                    (v) => setState(() => _editStoreName = v),
                  ),
                  _settingsDivider(),
                  _settingsTextField(
                    'Address',
                    _editStoreAddress,
                    (v) => setState(() => _editStoreAddress = v),
                  ),
                  _settingsDivider(),
                  _settingsTextField(
                    'Phone Number',
                    _editStorePhone,
                    (v) => setState(() => _editStorePhone = v),
                    keyboardType: TextInputType.phone,
                  ),
                  _settingsDivider(),
                  _settingsTextField(
                    'Email',
                    _editStoreEmail,
                    (v) => setState(() => _editStoreEmail = v),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _settingsDivider(),
                  _settingsTextField(
                    'GSTIN',
                    _editStoreGstin,
                    (v) => setState(() => _editStoreGstin = v),
                  ),
                  _settingsDivider(),
                  _settingsTextField(
                    'UPI ID',
                    _editStoreUpiId,
                    (v) => setState(() => _editStoreUpiId = v),
                  ),
                  _settingsDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Company Logo',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        if (_editLogoPath.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(_editLogoPath),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _editLogoPath = ''),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        TextButton.icon(
                          onPressed: () async {
                            final r = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (r != null) {
                              final copied =
                                  await LocalDbService.copyImageToAppDir(
                                    r.files.single.path!,
                                  );
                              setState(() => _editLogoPath = copied);
                            }
                          },
                          icon: const Icon(Icons.upload_rounded, size: 16),
                          label: Text(
                            _editLogoPath.isEmpty ? 'Upload' : 'Change',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                // Page setup
                _settingsSectionHeader('PAGE SETUP'),
                const SizedBox(height: 8),
                _settingsCard([
                  _settingsDropdownRow(
                    'Paper Size',
                    _editPrinterTab == 'Regular'
                        ? ['A4', 'A5']
                        : ['2 inch', '3 inch', '4 inch', 'Custom'],
                    _editPaperSize,
                    (v) => setState(() {
                      _editPaperSize = v!;
                      _previewRevision++;
                    }),
                  ),
                  _settingsDivider(),
                  _settingsDropdownRow(
                    'Orientation',
                    ['Portrait', 'Landscape'],
                    _editPrintOrientation,
                    (v) => setState(() {
                      _editPrintOrientation = v!;
                      _previewRevision++;
                    }),
                  ),
                ]),
                const SizedBox(height: 24),

                // Receipt footer
                _settingsSectionHeader('RECEIPT FOOTER'),
                const SizedBox(height: 8),
                _settingsCard([
                  _settingsTextField(
                    'Footer Text',
                    _editReceiptFooter,
                    (v) => setState(() => _editReceiptFooter = v),
                    maxLines: 2,
                  ),
                ]),
                const SizedBox(height: 24),

                // Terms & Conditions (used in Tax Invoice layout)
                _settingsSectionHeader('TERMS & CONDITIONS'),
                const SizedBox(height: 8),
                _settingsCard([
                  _settingsTextField(
                    'Terms & Conditions',
                    _editStoreTerms,
                    (v) => setState(() => _editStoreTerms = v),
                    maxLines: 3,
                  ),
                ]),
                const SizedBox(height: 24),

                // Auto print
                _settingsSectionHeader('OPTIONS'),
                const SizedBox(height: 8),
                _settingsCard([
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto Print',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: const Color(0xFF1D1D1F),
                                ),
                              ),
                              Text(
                                'Automatically print receipt after checkout',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF6E6E73),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _editAutoPrint,
                          onChanged: (v) => setState(() => _editAutoPrint = v),
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),

        // Vertical divider
        Container(width: 1, color: const Color(0xFFD8D8DC)),

        // ── Right: live preview ────────────────────────────────────────
        Expanded(
          child: Container(
            color: const Color(0xFFE8E8ED),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Preview header bar
                Container(
                  height: 44,
                  color: const Color(0xFFF2F2F7),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: Color(0xFF6E6E73),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live Preview',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6E6E73),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _printRecord(_testReceipt()),
                        icon: const Icon(Icons.print_outlined, size: 13),
                        label: Text(
                          'Print Test',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: const Color(0xFFD8D8DC)),
                // Preview body — renders the actual PDF bytes
                Expanded(
                  child: PdfPreview(
                    key: ValueKey(_previewRevision),
                    build: (_) => ReceiptPrinter.buildPdf(
                      _testReceipt(),
                      storeName: _editStoreName,
                      storeAddress: _editStoreAddress,
                      storePhone: _editStorePhone,
                      storeEmail: _editStoreEmail,
                      storeGstin: _editStoreGstin,
                      receiptFooter: _editReceiptFooter,
                      taxLabel: _editTaxLabel,
                      taxRate: _editTaxRate,
                      currencySymbol: _editCurrencySymbol,
                      paperSize: _editPaperSize,
                      orientation: _editPrintOrientation,
                      layout: _editInvoiceLayout,
                      storeTerms: _editStoreTerms,
                      logoPath: _editLogoPath,
                      storeUpiId: _editStoreUpiId,
                    ),
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    useActions: false,
                    scrollViewDecoration: const BoxDecoration(
                      color: Color(0xFF3C3C3C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Layout theme thumbnail widget
  Widget _layoutThumb(String layout, {required bool selected}) {
    final c = selected ? AppColors.primary : const Color(0xFFBBBBBB);
    final line = (double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    final gap = const SizedBox(height: 2.5);

    switch (layout) {
      case 'Classic':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(28, 3),
            gap,
            line(36, 1.5),
            gap,
            line(36, 1.5),
            gap,
            line(36, 1.5),
            gap,
            line(24, 3),
          ],
        );
      case 'Simple':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(24, 2.5),
            const SizedBox(height: 1.5),
            line(36, 1),
            const SizedBox(height: 1.5),
            line(36, 1),
            const SizedBox(height: 1.5),
            line(36, 1),
            const SizedBox(height: 1.5),
            line(36, 1),
            const SizedBox(height: 1.5),
            line(20, 2.5),
          ],
        );
      case 'Modern':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                  ),
                ),
              ],
            ),
            gap,
            line(36, 1.5),
            gap,
            line(36, 1.5),
            gap,
            line(36, 1.5),
            gap,
            line(22, 3),
          ],
        );
      case 'GST':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(28, 2.5),
            gap,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 17,
                  height: 12,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 17,
                  height: 12,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
            gap,
            line(36, 8),
            gap,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 8,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 14,
                  height: 8,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
            gap,
            line(22, 2.5),
          ],
        );
      case 'Landscape':
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [line(16, 3), gap, line(16, 1.5), gap, line(16, 1.5)],
            ),
            const SizedBox(width: 3),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line(18, 1.5),
                gap,
                line(18, 1.5),
                gap,
                line(18, 1.5),
                gap,
                line(12, 3),
              ],
            ),
          ],
        );
      // ── Thermal ───────────────────────────────────────────────────────────
      case 'Theme 1':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(22, 2.5),
            gap,
            line(28, 1),
            gap,
            line(28, 1),
            gap,
            line(28, 1),
            gap,
            line(16, 2.5),
          ],
        );
      case 'Theme 2':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(20, 2),
            const SizedBox(height: 1.5),
            line(28, 0.8),
            const SizedBox(height: 1.5),
            line(28, 0.8),
            const SizedBox(height: 1.5),
            line(28, 0.8),
            const SizedBox(height: 1.5),
            line(28, 0.8),
            const SizedBox(height: 1.5),
            line(28, 0.8),
            const SizedBox(height: 1.5),
            line(14, 2),
          ],
        );
      case 'Theme 3':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(22, 3),
            gap,
            line(28, 2),
            gap,
            line(28, 2),
            gap,
            line(18, 4),
          ],
        );
      case 'Theme 4':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(22, 2.5),
            gap,
            line(28, 1),
            gap,
            line(28, 1),
            gap,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 5,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.5),
                  ),
                ),
                const SizedBox(width: 1),
                Container(
                  width: 7,
                  height: 5,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.5),
                  ),
                ),
                const SizedBox(width: 1),
                Container(
                  width: 7,
                  height: 5,
                  decoration: BoxDecoration(
                    border: Border.all(color: c, width: 0.5),
                  ),
                ),
              ],
            ),
            gap,
            line(16, 2.5),
          ],
        );
      case 'Theme 5':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            line(22, 2.5),
            gap,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Container(width: i == 1 ? 9 : 4, height: 3, color: c),
                ],
              ],
            ),
            gap,
            for (int r = 0; r < 3; r++) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Container(
                      width: i == 1 ? 9 : 4,
                      height: 2.5,
                      color: c.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
            ],
            line(16, 2.5),
          ],
        );
      default:
        return line(32, 20);
    }
  }

  // Receipt preview panel (Flutter-rendered, updates instantly)
  Widget _buildReceiptPreview() {
    if (_editInvoiceLayout == 'GST') return _buildTaxInvoicePreview();
    if (_editInvoiceLayout == 'Classic') return _buildClassicInvoicePreview();

    final isNarrow = _editPrinterTab == 'Thermal';
    final w = _editPaperSize == '2 inch'
        ? 175.0
        : isNarrow
        ? 220.0
        : _editPaperSize == 'A5'
        ? 260.0
        : 310.0;
    final isGst = false;
    final isCompact = _editInvoiceLayout == 'Simple';
    final double fs = isCompact
        ? 7.0
        : (isNarrow
              ? 8.0
              : _editPaperSize == 'A5'
              ? 8.8
              : 9.5);

    Widget sep() => Container(
      height: 0.5,
      color: const Color(0xFF888888),
      margin: EdgeInsets.symmetric(vertical: isCompact ? 3 : 5),
    );
    Widget row(String l, String r, {bool bold = false, double? fsize}) => Row(
      children: [
        Expanded(
          child: Text(
            l,
            style: TextStyle(
              fontSize: fsize ?? fs,
              color: bold ? const Color(0xFF1D1D1F) : const Color(0xFF555555),
            ),
          ),
        ),
        Text(
          r,
          style: TextStyle(
            fontSize: fsize ?? fs,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: const Color(0xFF1D1D1F),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = ((constraints.maxWidth - 48) / w).clamp(1.0, 4.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Center(
            child: SizedBox(
              width: w * scale,
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(isNarrow ? 10 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Center(
                          child: Text(
                            _editStoreName.isEmpty
                                ? 'BillCat Store'
                                : _editStoreName,
                            style: TextStyle(
                              fontSize: fs + 3,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1D1D1F),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (_editStoreAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Center(
                            child: Text(
                              _editStoreAddress,
                              style: TextStyle(
                                fontSize: fs - 1,
                                color: const Color(0xFF777777),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if (_editStorePhone.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Center(
                            child: Text(
                              'Tel: $_editStorePhone',
                              style: TextStyle(
                                fontSize: fs - 1,
                                color: const Color(0xFF777777),
                              ),
                            ),
                          ),
                        ],
                        if (_editStoreEmail.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Center(
                            child: Text(
                              _editStoreEmail,
                              style: TextStyle(
                                fontSize: fs - 1,
                                color: const Color(0xFF777777),
                              ),
                            ),
                          ),
                        ],
                        if (isGst && _editStoreGstin.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Center(
                            child: Text(
                              'GSTIN: $_editStoreGstin',
                              style: TextStyle(
                                fontSize: fs - 1,
                                color: const Color(0xFF555555),
                              ),
                            ),
                          ),
                        ],
                        sep(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Bill #A1B2C3D4',
                              style: TextStyle(
                                fontSize: fs - 1.5,
                                color: const Color(0xFF888888),
                              ),
                            ),
                            Text(
                              '28/04/2026  14:30',
                              style: TextStyle(
                                fontSize: fs - 1.5,
                                color: const Color(0xFF888888),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 2 : 3),
                        Text(
                          'Customer: Sample Customer',
                          style: TextStyle(
                            fontSize: fs - 1.5,
                            color: const Color(0xFF888888),
                          ),
                        ),
                        sep(),
                        // Column headers
                        Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                'ITEM',
                                style: TextStyle(
                                  fontSize: fs - 1,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF888888),
                                ),
                              ),
                            ),
                            Text(
                              'QTY',
                              style: TextStyle(
                                fontSize: fs - 1,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF888888),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'TOTAL',
                              style: TextStyle(
                                fontSize: fs - 1,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF888888),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isCompact ? 2 : 4),
                        // Sample items
                        for (final item in [
                          (
                            'Sample Product A',
                            'x2',
                            '${_editCurrencySymbol}500',
                          ),
                          (
                            'Sample Product B',
                            'x1',
                            '${_editCurrencySymbol}180',
                          ),
                        ])
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: isCompact ? 1 : 2,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    item.$1,
                                    style: TextStyle(
                                      fontSize: fs,
                                      color: const Color(0xFF1D1D1F),
                                    ),
                                  ),
                                ),
                                Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontSize: fs,
                                    color: const Color(0xFF555555),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.$3,
                                  style: TextStyle(
                                    fontSize: fs,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1D1D1F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        sep(),
                        row('Subtotal', '${_editCurrencySymbol}680'),
                        row(
                          '$_editTaxLabel ($_editTaxRate%)',
                          '${_editCurrencySymbol}${(680 * (double.tryParse(_editTaxRate) ?? 18) / 100).toStringAsFixed(2)}',
                        ),
                        SizedBox(height: isCompact ? 2 : 3),
                        Container(height: 1, color: const Color(0xFF1D1D1F)),
                        SizedBox(height: isCompact ? 2 : 3),
                        row(
                          'TOTAL',
                          '${_editCurrencySymbol}${(680 * (1 + (double.tryParse(_editTaxRate) ?? 18) / 100)).toStringAsFixed(2)}',
                          bold: true,
                          fsize: fs + 2,
                        ),
                        SizedBox(height: isCompact ? 1 : 2),
                        row('Payment', 'CASH'),
                        // GST table
                        if (isGst) ...[
                          sep(),
                          Text(
                            'Tax Summary',
                            style: TextStyle(
                              fontSize: fs - 0.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF555555),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFCCCCCC),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  color: const Color(0xFFF5F5F5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'HSN',
                                          style: TextStyle(
                                            fontSize: fs - 1.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Taxable',
                                          style: TextStyle(
                                            fontSize: fs - 1.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'CGST',
                                          style: TextStyle(
                                            fontSize: fs - 1.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'SGST',
                                          style: TextStyle(
                                            fontSize: fs - 1.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Total',
                                          style: TextStyle(
                                            fontSize: fs - 1.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '1234',
                                          style: TextStyle(fontSize: fs - 1.5),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_editCurrencySymbol}680',
                                          style: TextStyle(fontSize: fs - 1.5),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_editCurrencySymbol}61',
                                          style: TextStyle(fontSize: fs - 1.5),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_editCurrencySymbol}61',
                                          style: TextStyle(fontSize: fs - 1.5),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${_editCurrencySymbol}122',
                                          style: TextStyle(fontSize: fs - 1.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        sep(),
                        Center(
                          child: Text(
                            _editReceiptFooter.isEmpty
                                ? 'Thank you for your purchase!'
                                : _editReceiptFooter,
                            style: TextStyle(
                              fontSize: fs - 1,
                              color: const Color(0xFF888888),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Tax Invoice A4 preview (Flutter-rendered)
  Widget _buildTaxInvoicePreview() {
    const fs = 8.5;
    const c555 = Color(0xFF555555);
    const c888 = Color(0xFF888888);
    const c1d = Color(0xFF1D1D1F);
    const cBorder = Color(0xFFCCCCCC);

    Widget sep() => Container(
      height: 0.5,
      color: c888,
      margin: const EdgeInsets.symmetric(vertical: 5),
    );

    Widget labelVal(String lbl, String val) => Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            lbl,
            style: const TextStyle(fontSize: fs - 1, color: c888),
          ),
        ),
        Text(
          ': ',
          style: const TextStyle(fontSize: fs - 1, color: c888),
        ),
        Expanded(
          child: Text(
            val,
            style: const TextStyle(
              fontSize: fs - 1,
              fontWeight: FontWeight.bold,
              color: c1d,
            ),
          ),
        ),
      ],
    );

    Widget totalRow(
      String l,
      String r, {
      bool bold = false,
      double fsize = fs,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l,
              style: TextStyle(fontSize: fsize, color: c555),
            ),
          ),
          Text(
            r,
            style: TextStyle(
              fontSize: fsize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: c1d,
            ),
          ),
        ],
      ),
    );

    final taxPct = double.tryParse(_editTaxRate) ?? 18.0;
    final cgst = (680 * taxPct / 100) / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        const cardW = 380.0;
        final scale = ((constraints.maxWidth - 48) / cardW).clamp(1.0, 4.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Center(
            child: SizedBox(
              width: cardW * scale,
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: cardW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        const Center(
                          child: Text(
                            'TAX INVOICE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Company header
                        Text(
                          _editStoreName.isEmpty
                              ? 'BillCat Store'
                              : _editStoreName,
                          style: const TextStyle(
                            fontSize: fs + 1,
                            fontWeight: FontWeight.bold,
                            color: c1d,
                          ),
                        ),
                        if (_editStoreAddress.isNotEmpty)
                          Text(
                            _editStoreAddress,
                            style: const TextStyle(
                              fontSize: fs - 1,
                              color: c888,
                            ),
                          ),
                        if (_editStorePhone.isNotEmpty)
                          Text(
                            'Phone: $_editStorePhone',
                            style: const TextStyle(
                              fontSize: fs - 1,
                              color: c888,
                            ),
                          ),
                        if (_editStoreGstin.isNotEmpty)
                          Text(
                            'GSTIN: $_editStoreGstin',
                            style: const TextStyle(
                              fontSize: fs,
                              fontWeight: FontWeight.bold,
                              color: c555,
                            ),
                          ),
                        sep(),
                        // Bill To / Invoice Details two-column
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: cBorder,
                                    width: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Bill To:',
                                      style: TextStyle(
                                        fontSize: fs - 1.5,
                                        fontWeight: FontWeight.bold,
                                        color: c888,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    const Text(
                                      'Walk-In Customer',
                                      style: TextStyle(
                                        fontSize: fs,
                                        fontWeight: FontWeight.bold,
                                        color: c1d,
                                      ),
                                    ),
                                    const Text(
                                      '9876543210',
                                      style: TextStyle(
                                        fontSize: fs - 1,
                                        color: c888,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: cBorder,
                                    width: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Invoice Details:',
                                      style: TextStyle(
                                        fontSize: fs - 1.5,
                                        fontWeight: FontWeight.bold,
                                        color: c888,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    labelVal('Invoice No.', 'INV-A1B2C3D4'),
                                    labelVal('Date', '28/04/2026'),
                                    labelVal('Time', '14:30'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Items table header
                        Container(
                          color: const Color(0xFF2D2D2D),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Row(
                            children: const [
                              SizedBox(
                                width: 14,
                                child: Text(
                                  '#',
                                  style: TextStyle(
                                    fontSize: fs - 2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(
                                  'Item',
                                  style: TextStyle(
                                    fontSize: fs - 2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 24,
                                child: Text(
                                  'Qty',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: fs - 2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  'Price',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: fs - 2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  'Amount',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: fs - 2,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items
                        for (final item in [
                          ('1', 'Sample Product A', '2', '250.00', '500.00'),
                          ('2', 'Sample Product B', '1', '180.00', '180.00'),
                        ])
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: cBorder, width: 0.5),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  child: Text(
                                    item.$1,
                                    style: const TextStyle(
                                      fontSize: fs - 2,
                                      color: c555,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    item.$2,
                                    style: const TextStyle(
                                      fontSize: fs - 1,
                                      color: c1d,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    item.$3,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: fs - 1,
                                      color: c555,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '$_editCurrencySymbol${item.$4}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: fs - 1,
                                      color: c555,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '$_editCurrencySymbol${item.$5}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: fs - 1,
                                      fontWeight: FontWeight.bold,
                                      color: c1d,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Tax summary + totals
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tax summary
                            Expanded(
                              flex: 55,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tax Summary:',
                                    style: TextStyle(
                                      fontSize: fs,
                                      fontWeight: FontWeight.bold,
                                      color: c555,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: cBorder,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          color: const Color(0xFF5A5A5A),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          child: Row(
                                            children: const [
                                              Expanded(
                                                child: Text(
                                                  'Tax%',
                                                  style: TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'CGST',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'SGST',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'Total',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '$_editTaxRate%',
                                                  style: const TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: c555,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '$_editCurrencySymbol${cgst.toStringAsFixed(0)}',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: c555,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '$_editCurrencySymbol${cgst.toStringAsFixed(0)}',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: c555,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '$_editCurrencySymbol${(cgst * 2).toStringAsFixed(0)}',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                    fontSize: fs - 2.5,
                                                    color: c555,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Totals
                            Expanded(
                              flex: 42,
                              child: Column(
                                children: [
                                  totalRow(
                                    'Sub Total',
                                    '$_editCurrencySymbol 680.00',
                                  ),
                                  totalRow(
                                    'CGST',
                                    '$_editCurrencySymbol${cgst.toStringAsFixed(2)}',
                                  ),
                                  totalRow(
                                    'SGST',
                                    '$_editCurrencySymbol${cgst.toStringAsFixed(2)}',
                                  ),
                                  const Divider(height: 8, thickness: 0.5),
                                  totalRow(
                                    'Total',
                                    '$_editCurrencySymbol${(680 + cgst * 2).toStringAsFixed(2)}',
                                    bold: true,
                                    fsize: fs + 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        sep(),
                        // Amount in words
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Amount In Words: ',
                                style: TextStyle(
                                  fontSize: fs - 1,
                                  fontWeight: FontWeight.bold,
                                  color: c555,
                                ),
                              ),
                              TextSpan(
                                text: 'Six Hundred Eighty Rupees Only',
                                style: const TextStyle(
                                  fontSize: fs - 1,
                                  color: c888,
                                ),
                              ),
                            ],
                          ),
                        ),
                        sep(),
                        // Footer
                        if (_editReceiptFooter.isNotEmpty ||
                            _editStoreTerms.isNotEmpty)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_editReceiptFooter.isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Description:',
                                        style: TextStyle(
                                          fontSize: fs - 1,
                                          fontWeight: FontWeight.bold,
                                          color: c555,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _editReceiptFooter,
                                        style: const TextStyle(
                                          fontSize: fs - 2,
                                          color: c888,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_editReceiptFooter.isNotEmpty &&
                                  _editStoreTerms.isNotEmpty)
                                const SizedBox(width: 8),
                              if (_editStoreTerms.isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Terms & Conditions:',
                                        style: TextStyle(
                                          fontSize: fs - 1,
                                          fontWeight: FontWeight.bold,
                                          color: c555,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _editStoreTerms,
                                        style: const TextStyle(
                                          fontSize: fs - 2,
                                          color: c888,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Classic Tax Invoice preview (Flutter-rendered)
  Widget _buildClassicInvoicePreview() {
    const w = 310.0;
    const fs = 7.5;
    const c1d = Color(0xFF1D1D1F);
    const c55 = Color(0xFF555555);
    const c88 = Color(0xFF888888);
    const cBorder = Color(0xFFCCCCCC);
    const cGrey = Color(0xFFF0F0F0);

    final invoiceNo = 'Inv. PREVIEW';
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';

    Widget cell(
      String v, {
      bool bold = false,
      Color? c,
      TextAlign a = TextAlign.left,
      double? size,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Text(
        v,
        textAlign: a,
        style: TextStyle(
          fontSize: size ?? fs - 1,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: c ?? c1d,
        ),
      ),
    );

    Widget greyHeader(String t) => Container(
      color: cGrey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        t,
        style: TextStyle(
          fontSize: fs - 0.5,
          fontWeight: FontWeight.w700,
          color: c1d,
        ),
      ),
    );

    Widget detLine(String lbl, String val) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            lbl,
            style: TextStyle(fontSize: fs - 1.5, color: c88),
          ),
          Text(
            ': ',
            style: TextStyle(fontSize: fs - 1.5, color: c88),
          ),
          Text(
            val,
            style: TextStyle(fontSize: fs - 1.5, color: c1d),
          ),
        ],
      ),
    );

    Widget totLine(String lbl, String val, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            lbl,
            style: TextStyle(
              fontSize: fs - 1.5,
              color: bold ? c1d : c55,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: fs - 1.5,
              color: bold ? c1d : c55,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = ((constraints.maxWidth - 48) / w).clamp(1.0, 4.0);
        return SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: w * scale,
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: cBorder, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        Container(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: cBorder)),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Center(
                            child: Text(
                              'Tax Invoice',
                              style: TextStyle(
                                fontSize: fs + 1,
                                fontWeight: FontWeight.w700,
                                color: c1d,
                              ),
                            ),
                          ),
                        ),
                        // Company info (left) | Invoice details (right)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 55,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: cBorder),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: cGrey,
                                          border: Border.all(
                                            color: cBorder,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: _editLogoPath.isNotEmpty
                                            ? ClipRRect(
                                                child: Image.file(
                                                  File(_editLogoPath),
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  'IMG',
                                                  style: TextStyle(
                                                    fontSize: 7,
                                                    color: c88,
                                                  ),
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _editStoreName.isNotEmpty
                                                  ? _editStoreName
                                                  : 'Company',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: c1d,
                                              ),
                                            ),
                                            if (_editStoreAddress.isNotEmpty)
                                              Text(
                                                _editStoreAddress,
                                                style: TextStyle(
                                                  fontSize: fs - 2,
                                                  color: c55,
                                                ),
                                              ),
                                            if (_editStorePhone.isNotEmpty)
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: 'Phone: ',
                                                      style: TextStyle(
                                                        fontSize: fs - 2,
                                                        color: c88,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: _editStorePhone,
                                                      style: TextStyle(
                                                        fontSize: fs - 2,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: c1d,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (_editStoreEmail.isNotEmpty)
                                              RichText(
                                                text: TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: 'Email: ',
                                                      style: TextStyle(
                                                        fontSize: fs - 2,
                                                        color: c88,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: _editStoreEmail,
                                                      style: TextStyle(
                                                        fontSize: fs - 2,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: c1d,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 0.5, color: cBorder),
                              Expanded(
                                flex: 45,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: cBorder),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      detLine('Invoice No.', invoiceNo),
                                      detLine('Date', dateStr),
                                      detLine('Time', '12:00 PM'),
                                      detLine('Due Date', dateStr),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Bill To | Invoice Details
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 55,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    greyHeader('Bill To:'),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Sample Customer',
                                            style: TextStyle(
                                              fontSize: fs - 1,
                                              color: c1d,
                                            ),
                                          ),
                                          Text(
                                            'Contact No.: 9999999999',
                                            style: TextStyle(
                                              fontSize: fs - 2,
                                              color: c55,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 0.5, color: cBorder),
                              Expanded(
                                flex: 45,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    greyHeader('Invoice Details:'),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          detLine('Invoice No.', invoiceNo),
                                          detLine('Date', dateStr),
                                          detLine('Time', '12:00 PM'),
                                          detLine('Due Date', dateStr),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 0.5, color: cBorder),
                        // Ship To
                        greyHeader('Ship To:'),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: cBorder)),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            '—',
                            style: TextStyle(fontSize: fs - 1, color: c55),
                          ),
                        ),
                        // Items header
                        Container(
                          color: cGrey,
                          child: Row(
                            children: [
                              for (final h in [
                                ('#', 14.0, TextAlign.center),
                                ('Item name', 80.0, TextAlign.left),
                                ('HSC/SAC', 38.0, TextAlign.center),
                                ('Qty', 28.0, TextAlign.center),
                                ('Price', 38.0, TextAlign.right),
                                ('Disc', 36.0, TextAlign.right),
                                ('GST', 34.0, TextAlign.right),
                                ('Amt', 36.0, TextAlign.right),
                              ])
                                SizedBox(
                                  width: h.$2,
                                  child: cell(h.$1, bold: true, a: h.$3),
                                ),
                            ],
                          ),
                        ),
                        Container(height: 0.5, color: cBorder),
                        // Sample rows
                        for (final row in [
                          (
                            '1',
                            'Sample Product A',
                            '—',
                            '2',
                            '₹250',
                            '₹0',
                            '₹0',
                            '₹500',
                          ),
                          (
                            '2',
                            'Sample Product B',
                            '—',
                            '1',
                            '₹180',
                            '₹0',
                            '₹0',
                            '₹180',
                          ),
                        ])
                          Column(
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    child: cell(row.$1, a: TextAlign.center),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: cell(row.$2, bold: true),
                                  ),
                                  SizedBox(
                                    width: 38,
                                    child: cell(row.$3, a: TextAlign.center),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: cell(row.$4, a: TextAlign.center),
                                  ),
                                  SizedBox(
                                    width: 38,
                                    child: cell(row.$5, a: TextAlign.right),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: cell(row.$6, a: TextAlign.right),
                                  ),
                                  SizedBox(
                                    width: 34,
                                    child: cell(row.$7, a: TextAlign.right),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: cell(
                                      row.$8,
                                      bold: true,
                                      a: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              Container(height: 0.5, color: cBorder),
                            ],
                          ),
                        // TOTAL row
                        Container(
                          color: cGrey,
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 80,
                                child: cell('TOTAL', bold: true),
                              ),
                              const SizedBox(width: 38),
                              SizedBox(
                                width: 28,
                                child: cell(
                                  '3',
                                  bold: true,
                                  a: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 38),
                              SizedBox(
                                width: 36,
                                child: cell(
                                  '₹0',
                                  bold: true,
                                  a: TextAlign.right,
                                ),
                              ),
                              SizedBox(
                                width: 34,
                                child: cell(
                                  '₹0',
                                  bold: true,
                                  a: TextAlign.right,
                                ),
                              ),
                              SizedBox(
                                width: 36,
                                child: cell(
                                  '₹680',
                                  bold: true,
                                  a: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 0.5, color: cBorder),
                        // Tax Summary | Totals
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 55,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Tax table header
                                    Container(
                                      color: cGrey,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 28,
                                            child: cell(
                                              'HSN',
                                              bold: true,
                                              a: TextAlign.center,
                                              size: fs - 3,
                                            ),
                                          ),
                                          Container(width: 0.5, color: cBorder),
                                          SizedBox(
                                            width: 38,
                                            child: cell(
                                              'Taxable',
                                              bold: true,
                                              a: TextAlign.center,
                                              size: fs - 3,
                                            ),
                                          ),
                                          Container(width: 0.5, color: cBorder),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: cBorder,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      'CGST',
                                                      style: TextStyle(
                                                        fontSize: fs - 3,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Center(
                                                        child: Text(
                                                          'Rate',
                                                          style: TextStyle(
                                                            fontSize: fs - 3.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 0.5,
                                                      color: cBorder,
                                                    ),
                                                    Expanded(
                                                      child: Center(
                                                        child: Text(
                                                          'Amt',
                                                          style: TextStyle(
                                                            fontSize: fs - 3.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(width: 0.5, color: cBorder),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      bottom: BorderSide(
                                                        color: cBorder,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      'SGST',
                                                      style: TextStyle(
                                                        fontSize: fs - 3,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Center(
                                                        child: Text(
                                                          'Rate',
                                                          style: TextStyle(
                                                            fontSize: fs - 3.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 0.5,
                                                      color: cBorder,
                                                    ),
                                                    Expanded(
                                                      child: Center(
                                                        child: Text(
                                                          'Amt',
                                                          style: TextStyle(
                                                            fontSize: fs - 3.5,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(width: 0.5, color: cBorder),
                                          SizedBox(
                                            width: 32,
                                            child: cell(
                                              'Total Tax',
                                              bold: true,
                                              a: TextAlign.center,
                                              size: fs - 3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(height: 0.5, color: cBorder),
                                    // Data row
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 28,
                                          child: cell(
                                            '—',
                                            a: TextAlign.center,
                                            size: fs - 2.5,
                                          ),
                                        ),
                                        Container(width: 0.5, color: cBorder),
                                        SizedBox(
                                          width: 38,
                                          child: cell(
                                            '₹680',
                                            a: TextAlign.right,
                                            size: fs - 2.5,
                                          ),
                                        ),
                                        Container(width: 0.5, color: cBorder),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: cell(
                                                  '${_editTaxRate}%',
                                                  a: TextAlign.right,
                                                  size: fs - 2.5,
                                                ),
                                              ),
                                              Container(
                                                width: 0.5,
                                                color: cBorder,
                                              ),
                                              Expanded(
                                                child: cell(
                                                  '₹0',
                                                  a: TextAlign.right,
                                                  size: fs - 2.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 0.5, color: cBorder),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: cell(
                                                  '${_editTaxRate}%',
                                                  a: TextAlign.right,
                                                  size: fs - 2.5,
                                                ),
                                              ),
                                              Container(
                                                width: 0.5,
                                                color: cBorder,
                                              ),
                                              Expanded(
                                                child: cell(
                                                  '₹0',
                                                  a: TextAlign.right,
                                                  size: fs - 2.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 0.5, color: cBorder),
                                        SizedBox(
                                          width: 32,
                                          child: cell(
                                            '₹0',
                                            a: TextAlign.right,
                                            size: fs - 2.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(height: 0.5, color: cBorder),
                                    // Payment mode
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Payment Mode: ',
                                              style: TextStyle(
                                                fontSize: fs - 1.5,
                                                color: c88,
                                              ),
                                            ),
                                            TextSpan(
                                              text: 'Cash',
                                              style: TextStyle(
                                                fontSize: fs - 1.5,
                                                fontWeight: FontWeight.w700,
                                                color: c1d,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 0.5, color: cBorder),
                              // Totals right column
                              Expanded(
                                flex: 45,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      totLine('Sub Total', '₹680.00'),
                                      totLine('Tax ($_editTaxRate%)', '₹0.00'),
                                      Container(
                                        height: 0.5,
                                        color: cBorder,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                      ),
                                      totLine(
                                        'Total',
                                        '$_editCurrencySymbol 680.00',
                                        bold: true,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Invoice Amount In Words:',
                                        style: TextStyle(
                                          fontSize: fs - 2,
                                          color: c55,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Six Hundred Eighty only',
                                        style: TextStyle(
                                          fontSize: fs - 2.5,
                                          color: c88,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      totLine('Received', '₹680.00'),
                                      totLine('Balance', '₹0.00'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 0.5, color: cBorder),
                        // Footer
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 55,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    greyHeader('Description:'),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        _editReceiptFooter.isNotEmpty
                                            ? _editReceiptFooter
                                            : 'Sale Description',
                                        style: TextStyle(
                                          fontSize: fs - 2,
                                          color: c55,
                                        ),
                                      ),
                                    ),
                                    Container(height: 0.5, color: cBorder),
                                    greyHeader('Bank Details:'),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            color: cGrey,
                                            child: Center(
                                              child: Text(
                                                'QR',
                                                style: TextStyle(
                                                  fontSize: 7,
                                                  color: c88,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Bank Name: —',
                                                style: TextStyle(
                                                  fontSize: fs - 2.5,
                                                  color: c55,
                                                ),
                                              ),
                                              Text(
                                                'Account No.: —',
                                                style: TextStyle(
                                                  fontSize: fs - 2.5,
                                                  color: c55,
                                                ),
                                              ),
                                              Text(
                                                'IFSC Code: —',
                                                style: TextStyle(
                                                  fontSize: fs - 2.5,
                                                  color: c55,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 0.5, color: cBorder),
                              Expanded(
                                flex: 45,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    greyHeader('Terms & Conditions:'),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        _editStoreTerms.isNotEmpty
                                            ? _editStoreTerms
                                            : 'Thanks for doing business with us!',
                                        style: TextStyle(
                                          fontSize: fs - 2,
                                          color: c55,
                                        ),
                                      ),
                                    ),
                                    Container(height: 0.5, color: cBorder),
                                    greyHeader(
                                      'For: ${_editStoreName.isNotEmpty ? _editStoreName : "Company"}:',
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 34,
                                            color: cGrey,
                                            child: Center(
                                              child: Text(
                                                'Image',
                                                style: TextStyle(
                                                  fontSize: 7,
                                                  color: c88,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Authorized Signatory',
                                            style: TextStyle(
                                              fontSize: fs - 2,
                                              color: c55,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsDropdownRow(
    String label,
    List<String> options,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF1D1D1F),
              ),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                items: options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o,
                        child: Text(
                          o,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF1D1D1F),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
                alignment: Alignment.centerRight,
                isDense: true,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF1D1D1F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Account ──
  Widget _buildSettingsAccount() {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final name = user?.userMetadata?['full_name'] as String? ?? 'User';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('Account', Icons.person_outline_rounded),
        const SizedBox(height: 24),
        _settingsCard([
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1D1D1F),
                        ),
                      ),
                      Text(
                        email,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF6E6E73),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _settingsCard([
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _manualCheckForUpdate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    _isCheckingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.system_update_alt_rounded,
                            size: 18,
                            color: Color(0xFF1D1D1F),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Check for Updates',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1D1D1F),
                        ),
                      ),
                    ),
                    if (_updateInfo != null && !_updateDismissed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'v${_updateInfo!.version} available',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Text(
                        'v${_appVersion()}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF6E6E73),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        _settingsCard([
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                setState(() => _showSettings = false);
                await Future.delayed(const Duration(milliseconds: 200));
                await Supabase.instance.client.auth.signOut();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'BillCat v${_appVersion()}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF6E6E73),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSecurity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('Security', Icons.shield_outlined),
        const SizedBox(height: 24),
        _settingsSectionHeader('STAFF ACCESS CONTROL'),
        const SizedBox(height: 12),
        _settingsCard([
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: Color(0xFF1D1D1F),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable Staff Mode',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1D1D1F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hide Dashboard & Reports from staff. A passcode unlocks owner access.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF6E6E73),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _ownerLockEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (val) async {
                    if (val) {
                      // Enabling — require a passcode first
                      if (_ownerPasscode.isEmpty) {
                        _showSetPasscodeDialog(
                          isFirstTime: true,
                          onSet: () async {
                            setState(() {
                              _ownerLockEnabled = true;
                              _isOwnerMode = true;
                            });
                            await LocalDbService.saveSettings({
                              'owner_lock_enabled': '1',
                            });
                            ConnectivityService.instance.syncNow();
                          },
                        );
                      } else {
                        setState(() {
                          _ownerLockEnabled = true;
                          _isOwnerMode = true;
                        });
                        await LocalDbService.saveSettings({
                          'owner_lock_enabled': '1',
                        });
                        ConnectivityService.instance.syncNow();
                      }
                    } else {
                      setState(() {
                        _ownerLockEnabled = false;
                        _isOwnerMode = false;
                      });
                      await LocalDbService.saveSettings({
                        'owner_lock_enabled': '0',
                      });
                      ConnectivityService.instance.syncNow();
                    }
                  },
                ),
              ],
            ),
          ),
        ]),
        if (_ownerLockEnabled) ...[
          const SizedBox(height: 16),
          _settingsSectionHeader('OWNER PASSCODE'),
          const SizedBox(height: 12),
          _settingsCard([
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showSetPasscodeDialog(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pin_outlined,
                        size: 18,
                        color: Color(0xFF1D1D1F),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _ownerPasscode.isEmpty
                              ? 'Set Passcode'
                              : 'Change Passcode',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1D1D1F),
                          ),
                        ),
                      ),
                      Text(
                        _ownerPasscode.isEmpty ? 'Not set' : '••••',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF6E6E73),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Color(0xFFAAAAAA),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  // ── WhatsApp Settings ──
  Widget _buildSettingsWhatsApp() {
    final configured = _waPhoneNumberId.isNotEmpty && _waAccessToken.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingsPageTitle('WhatsApp', Icons.chat_bubble_outline_rounded),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 16),
          child: Text(
            'Send invoices automatically via WhatsApp using Meta Cloud API. Free 1,000 conversations/month.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF6E6E73),
            ),
          ),
        ),
        if (configured) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FFF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF34C759).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: Color(0xFF1AAD56),
                ),
                const SizedBox(width: 8),
                Text(
                  'WhatsApp API configured',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1AAD56),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _settingsSectionHeader('META CLOUD API'),
        const SizedBox(height: 12),
        _settingsCard([
          _settingsTextField(
            'Phone Number ID',
            _editWaPhoneNumberId,
            (v) => setState(() => _editWaPhoneNumberId = v),
            hint: '1149269661601168',
          ),
          _settingsDivider(),
          _settingsTextField(
            'Access Token',
            _editWaAccessToken,
            (v) => setState(() => _editWaAccessToken = v),
            hint: 'EAAxxxxxxxx...',
            obscureText: true,
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Get Phone Number ID and Access Token from Meta for Developers → BillCat app → WhatsApp → API Setup.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Settings UI helpers ──

  Widget _settingsPageTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1D1D1F),
          ),
        ),
      ],
    );
  }

  Widget _settingsSectionHeader(String text) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 6),
    child: Row(
      children: [
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF8E8E93),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.5, color: const Color(0xFFD8D8DC))),
      ],
    ),
  );

  Widget _settingsCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8E8ED), width: 0.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _settingsDivider() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, color: Color(0xFFF2F2F7)),
  );

  Widget _settingsTextField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool obscureText = false,
    String? hint,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: maxLines > 1 ? 0 : 46),
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: maxLines > 1 ? 12 : 0,
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: const Color(0xFF3C3C43),
              ),
            ),
          ),
          Expanded(
            // Keyed so Flutter doesn't recycle one settings page's field state
            // onto another page's field.
            child: _SettingsInput(
              key: ValueKey('settings-field-$label'),
              value: value,
              onChanged: onChanged,
              keyboardType: keyboardType,
              maxLines: maxLines,
              obscureText: obscureText,
              hintText: hint ?? label,
            ),
          ),
        ],
      ),
    );
  }

  String _appVersion() =>
      _currentVersion.isNotEmpty ? _currentVersion : '1.0.0';

  // ── Settings dialog (legacy — kept for reference) ─────────────────────────────────────────────

  void _showSettingsDialog() {
    String storeName = _storeName;
    String storeAddress = _storeAddress;
    String receiptFooter = _receiptFooter;
    String taxLabel = _taxLabel;
    String taxRate = _taxRateDisplay;
    String currencyCode = _currencyCode;
    String currencySymbol = _currencySymbol;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Settings',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 20),

                // Store info
                _dialogSectionLabel('STORE INFORMATION'),
                const SizedBox(height: 14),
                _dialogField(
                  'Store Name',
                  storeName,
                  (v) => setLocal(() => storeName = v),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  'Store Address',
                  storeAddress,
                  (v) => setLocal(() => storeAddress = v),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  'Receipt Footer',
                  receiptFooter,
                  (v) => setLocal(() => receiptFooter = v),
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 20),

                // Tax config
                _dialogSectionLabel('TAX CONFIGURATION'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _dialogField(
                        'Tax Label',
                        taxLabel,
                        (v) => setLocal(() => taxLabel = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dialogField(
                        'Tax Rate (%)',
                        taxRate,
                        (v) => setLocal(() => taxRate = v),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 20),

                // Currency
                _dialogSectionLabel('CURRENCY'),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final result = await _showCurrencyPicker(ctx, currencyCode);
                    if (result != null) {
                      setLocal(() {
                        currencyCode = result.code;
                        currencySymbol = result.symbol;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _currencies
                              .firstWhere(
                                (c) => c.code == currencyCode,
                                orElse: () => _currencies.first,
                              )
                              .flag,
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$currencyCode  $currencySymbol',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                _currencies
                                    .firstWhere(
                                      (c) => c.code == currencyCode,
                                      orElse: () => _currencies.first,
                                    )
                                    .name,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w300,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.unfold_more_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _storeName = storeName.trim().isEmpty
                              ? 'BillCat Store'
                              : storeName.trim();
                          _storeAddress = storeAddress.trim();
                          _receiptFooter = receiptFooter.trim();
                          _taxLabel = taxLabel.trim().isEmpty
                              ? 'VAT'
                              : taxLabel.trim();
                          _taxRateDisplay = taxRate.trim().isEmpty
                              ? '0'
                              : taxRate.trim();
                          _syncTaxRate();
                          _currencyCode = currencyCode;
                          _currencySymbol = currencySymbol;
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Save Changes',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogSectionLabel(String text) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 1.0,
    ),
  );

  Widget _dialogField(
    String label,
    String value,
    Function(String) onChanged, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textDark),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ── Currency picker ──────────────────────────────────────────────────────────

  Future<_Currency?> _showCurrencyPicker(BuildContext ctx, String currentCode) {
    String query = '';
    return showDialog<_Currency>(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setLocal) {
          final filtered = query.isEmpty
              ? _currencies
              : _currencies
                    .where(
                      (c) =>
                          c.name.toLowerCase().contains(query.toLowerCase()) ||
                          c.code.toLowerCase().contains(query.toLowerCase()) ||
                          c.symbol.contains(query),
                    )
                    .toList();
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 420,
              height: 560,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
                    child: Row(
                      children: [
                        Text(
                          'Select Currency',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(dlgCtx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Search
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (v) => setLocal(() => query = v),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search currency or code…',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w300,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.border),
                  // List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final selected = c.code == currentCode;
                        return InkWell(
                          onTap: () => Navigator.pop(dlgCtx, c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.05)
                                : null,
                            child: Row(
                              children: [
                                Text(
                                  c.flag,
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                      Text(
                                        c.code,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w300,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  c.symbol,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                  ),
                                ),
                                if (selected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Printer dialog ───────────────────────────────────────────────────────────

  // Heuristic: does this printer name look like an 80mm thermal/receipt unit?
  bool _looksThermal(String name) {
    final n = name.toLowerCase();
    return n.contains('thermal') ||
        n.contains('receipt') ||
        n.contains('pos') ||
        n.contains('80mm') ||
        n.contains('58mm') ||
        RegExp(r'\b(pos|rp|tm|xp)[-_ ]?\d').hasMatch(n) ||
        n.contains('80');
  }

  void _showPrinterDialog() async {
    if (!mounted) return;
    // Open dialog immediately — load printers in the background
    List<Printer> systemPrinters = [];

    Printer? selPrinter = _activePrinter;
    bool isPdfExport = _selectedPrinter == 'PDF Export';
    String paper = _paperSize;
    // Regular = A4/A5, Thermal = 80mm roll (stored as a thermal paper size).
    bool isThermal = !['A4', 'A5'].contains(paper);
    bool autoPrint = _autoPrint;

    Widget printerRow(
      String name, {
      bool selected = false,
      required VoidCallback onTap,
      IconData icon = Icons.print_rounded,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.05)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.primary : AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    bool _loadingPrinters = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (_loadingPrinters) {
            _loadingPrinters = false;
            Future(() async {
              try {
                final printers = await Printing.listPrinters().timeout(
                  const Duration(seconds: 5),
                );
                if (ctx.mounted) {
                  setLocal(() {
                    systemPrinters = printers;
                    // Re-select the last-saved printer by name, so reopening
                    // the dialog shows it already chosen.
                    if (selPrinter == null && !isPdfExport) {
                      for (final pr in printers) {
                        if (pr.name == _selectedPrinter) {
                          selPrinter = pr;
                          break;
                        }
                      }
                    }
                  });
                }
              } catch (_) {
                if (ctx.mounted) setLocal(() {});
              }
            });
          }
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.print_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Printer Settings',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 20),

                  // Printer list
                  _dialogSectionLabel('SELECT PRINTER'),
                  const SizedBox(height: 10),

                  if (systemPrinters.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'No printers found. Add one in System Settings.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...systemPrinters.map(
                      (p) => printerRow(
                        p.name,
                        selected: !isPdfExport && selPrinter?.url == p.url,
                        icon: Icons.print_rounded,
                        onTap: () => setLocal(() {
                          selPrinter = p;
                          isPdfExport = false;
                          // Auto-switch to Thermal when the printer name looks
                          // like an 80mm thermal/receipt printer.
                          if (_looksThermal(p.name)) {
                            isThermal = true;
                            paper = '3 inch';
                          }
                        }),
                      ),
                    ),

                  const SizedBox(height: 20),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 20),

                  // Printer type
                  _dialogSectionLabel('PRINTER TYPE'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setLocal(() {
                            isThermal = false;
                            paper = 'A4';
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !isThermal
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !isThermal
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.print_rounded,
                                  size: 20,
                                  color: !isThermal
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Regular',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: !isThermal
                                        ? Colors.white
                                        : AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  'A4 / A5',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: !isThermal
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setLocal(() {
                            isThermal = true;
                            paper = '3 inch';
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isThermal
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isThermal
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 20,
                                  color: isThermal
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Thermal',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isThermal
                                        ? Colors.white
                                        : AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  '80mm roll',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: isThermal
                                        ? Colors.white.withValues(alpha: 0.8)
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 16),

                  // Auto-print toggle
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-print on Close Bill',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textDark,
                              ),
                            ),
                            Text(
                              'Automatically print receipt when bill is closed',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: autoPrint,
                        onChanged: (v) => setLocal(() => autoPrint = v),
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppColors.primary,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _printRecord(_testReceipt(), paperSize: paper);
                          },
                          icon: const Icon(Icons.print_outlined, size: 16),
                          label: Text(
                            'Print Test Page',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final printerName = isPdfExport
                                ? 'PDF Export'
                                : (selPrinter?.name ?? 'System Default');
                            setState(() {
                              _activePrinter = selPrinter;
                              _selectedPrinter = printerName;
                              _paperSize = paper;
                              _autoPrint = autoPrint;
                            });
                            LocalDbService.saveSettings({
                              'selected_printer': printerName,
                              'paper_size': paper,
                              'auto_print': autoPrint ? '1' : '0',
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Save',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Logout',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              // Push any pending offline work before signing out. No
              // clearAll: the DB file is per-user, and wiping it would
              // destroy unsynced sales / pending deletions forever.
              try {
                await ConnectivityService.instance.syncNow();
              } catch (_) {}
              await SupabaseService.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (r) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Logout',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear Bill',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove all items from the current bill?',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              cart.clearCart();
              _pendingInvoiceNumber = null;
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Clear',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Print helpers ────────────────────────────────────────────────────────────

  TransactionRecord _snapshotCart(CartProvider cart, {String? invoiceNumber}) =>
      TransactionRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        customerName: cart.customerName.isEmpty ? null : cart.customerName,
        customerPhone: cart.customerPhone.isEmpty ? null : cart.customerPhone,
        items: cart.items
            .map(
              (i) => TransactionItem(
                productId: i.product.id,
                productName: i.product.name,
                // Variant lines must price and label off the variant, not the
                // base product, or the preview won't match the real bill.
                price: i.unitPrice,
                quantity: i.quantity,
                description: i.product.description,
                variantId: i.variant?.id,
                variantLabel: i.variant?.label,
                taxPercent: i.product.taxPercent > 0
                    ? i.product.taxPercent
                    : cart.taxRate,
              ),
            )
            .toList(),
        subtotal: cart.subtotal,
        discountAmount: cart.discountAmount,
        taxAmount: cart.taxAmount,
        total: cart.total,
        paymentMethod: cart.paymentMethod.name,
        createdAt: DateTime.now(),
        invoiceNumber: invoiceNumber,
      );

  /// Invoice number for the bill currently being rung up. Generated the
  /// first time the bill is printed and reused at checkout, so the number on
  /// the printed receipt always matches the saved sale. Cleared when the
  /// bill is closed or cleared.
  String? _pendingInvoiceNumber;

  // ── Return / exchange ────────────────────────────────────────────────────
  //
  // A return is saved as its own bill with negative amounts and negative item
  // quantities, numbered RTN-/EXC- after the bill it reverses. That makes the
  // stock arithmetic put the goods back with no new code, nets the money off
  // in every existing total, and needs no new database column — so it syncs
  // to the other tills through the engine already in place. The whole
  // exchange — goods back, goods out, and the difference — is settled inside
  // the one dialog, so nothing is ever carried into the ordinary cart.

  /// Invoice reference a reversal points back at.
  String _reversalBaseRef(TransactionRecord t) =>
      t.invoiceNumber?.isNotEmpty == true
      ? t.invoiceNumber!
      : t.id.substring(0, 6).toUpperCase();

  /// Quantity of each line of [original] that earlier returns already took
  /// back, keyed the same way the cart keys lines. Stops the same item being
  /// returned twice and inflating stock.
  Map<String, int> _alreadyReturned(
    TransactionRecord original,
    List<TransactionRecord> all,
  ) {
    final ref = _reversalBaseRef(original);
    final out = <String, int>{};
    for (final r in all) {
      if (r.returnOfInvoice != ref) continue;
      for (final i in r.items) {
        final key = '${i.productId}::${i.variantId ?? ''}';
        out[key] = (out[key] ?? 0) + i.quantity.abs();
      }
    }
    return out;
  }

  /// Builds the reversing record for [qtyByIndex] of [original]'s lines.
  /// Discount and tax come back in the same proportion they were charged, so
  /// a partial return refunds exactly what that part of the bill collected.
  TransactionRecord _buildReversalRecord({
    required TransactionRecord original,
    required Map<int, int> qtyByIndex,
    required String paymentMethod,
    required bool exchange,
  }) {
    final origSub = original.subtotal;
    final discountFactor = origSub > 0
        ? (origSub - original.discountAmount) / origSub
        : 1.0;
    // Bills predating per-item rates carry taxPercent 0 on EVERY line, and
    // only those need the blended fallback. Once any line carries its own
    // rate, a stored 0 means the line really was sold exempt — the cart skips
    // rate <= 0 when charging — so it has to come back exempt too, or a
    // partial return refunds tax that was never collected on it.
    final anyLineRate = original.items.any((l) => l.taxPercent > 0);
    final taxedBase = origSub - original.discountAmount;
    final fallbackRate = (!anyLineRate && taxedBase > 0)
        ? original.taxAmount / taxedBase * 100
        : 0.0;

    final items = <TransactionItem>[];
    var sub = 0.0;
    // Each line's share of the tax, weighted by its own rate, for the lines
    // coming back and for the whole bill. Scaling one against the other means
    // a full return reproduces the tax the bill actually charged to the paisa,
    // even when the lines carry different rates, while a partial return takes
    // back only what those lines contributed.
    var taxWeightReturned = 0.0;
    var taxWeightAll = 0.0;
    for (var i = 0; i < original.items.length; i++) {
      final line = original.items[i];
      final rate = line.taxPercent > 0 ? line.taxPercent : fallbackRate;
      taxWeightAll += line.price * line.quantity * discountFactor * rate / 100;
      final qty = qtyByIndex[i] ?? 0;
      if (qty <= 0) continue;
      final gross = line.price * qty;
      sub += gross;
      taxWeightReturned += gross * discountFactor * rate / 100;
      items.add(
        TransactionItem(
          productId: line.productId,
          productName: line.productName,
          description: line.description,
          price: line.price,
          // Negative quantity is what puts the stock back.
          quantity: -qty,
          variantId: line.variantId,
          variantLabel: line.variantLabel,
          taxPercent: line.taxPercent,
        ),
      );
    }
    final tax = taxWeightAll > 0
        ? original.taxAmount * (taxWeightReturned / taxWeightAll)
        : 0.0;
    final discount = origSub > 0
        ? original.discountAmount * (sub / origSub)
        : 0.0;
    final prefix = exchange
        ? TransactionRecord.exchangePrefix
        : TransactionRecord.returnPrefix;
    return TransactionRecord(
      id: const Uuid().v4(),
      invoiceNumber: '$prefix${_reversalBaseRef(original)}',
      customerName: original.customerName,
      customerPhone: original.customerPhone,
      items: items,
      subtotal: -sub,
      discountAmount: -discount,
      taxAmount: -tax,
      total: -(sub - discount + tax),
      paymentMethod: paymentMethod,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _saveReversal(TransactionRecord record) async {
    await LocalDbService.insertReturn(record);
    await ConnectivityService.instance.refreshUnsyncedCount();
    if (ConnectivityService.instance.isOnline) {
      ConnectivityService.instance.syncNow();
    }
    _loadProducts();
    _loadDashboardData();
  }

  /// Prices the goods handed over in an exchange exactly as the cart would:
  /// each line at its own rate, falling back to the store rate, no discount.
  TransactionRecord _buildExchangeSale(
    List<_ExchangeAdd> adds, {
    required String paymentMethod,
    String? invoiceNumber,
    String? customerName,
    String? customerPhone,
  }) {
    final storeRate = double.tryParse(_taxRateDisplay) ?? 0;
    final items = <TransactionItem>[];
    var sub = 0.0;
    var tax = 0.0;
    for (final a in adds) {
      final gross = a.price * a.qty;
      final rate = a.product.taxPercent > 0 ? a.product.taxPercent : storeRate;
      sub += gross;
      if (rate > 0) tax += gross * rate / 100;
      items.add(
        TransactionItem(
          productId: a.product.id,
          productName: a.product.name,
          description: a.product.description,
          price: a.price,
          quantity: a.qty,
          variantId: a.variant?.id,
          variantLabel: a.variant?.label,
          taxPercent: rate,
        ),
      );
    }
    return TransactionRecord(
      id: const Uuid().v4(),
      invoiceNumber: invoiceNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      items: items,
      subtotal: sub,
      discountAmount: 0,
      taxAmount: tax,
      total: sub + tax,
      paymentMethod: paymentMethod,
      createdAt: DateTime.now(),
    );
  }

  /// Every sellable line, base products and variants alike, for the
  /// add-a-product search inside the return dialog.
  List<_ExchangeAdd> _sellableMatches(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <_ExchangeAdd>[];
    for (final p in _products) {
      final variants = _variantsByProduct[p.id] ?? const <ProductVariant>[];
      if (variants.isEmpty) {
        if (p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            (p.barcodeNo.isNotEmpty && p.barcodeNo.toLowerCase() == q)) {
          out.add(_ExchangeAdd(product: p));
        }
        continue;
      }
      for (final v in variants) {
        if (p.name.toLowerCase().contains(q) ||
            v.label.toLowerCase().contains(q) ||
            v.sku.toLowerCase().contains(q) ||
            (v.barcodeNo.isNotEmpty && v.barcodeNo.toLowerCase() == q)) {
          out.add(_ExchangeAdd(product: p, variant: v));
        }
      }
    }
    return out.take(6).toList();
  }

  /// An exact barcode hit, so a scanner gun can add straight off Enter.
  _ExchangeAdd? _scanMatch(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return null;
    for (final p in _products) {
      final variants = _variantsByProduct[p.id] ?? const <ProductVariant>[];
      for (final v in variants) {
        if (v.barcodeNo.isNotEmpty && v.barcodeNo == code) {
          return _ExchangeAdd(product: p, variant: v);
        }
      }
      if (variants.isEmpty && p.barcodeNo.isNotEmpty && p.barcodeNo == code) {
        return _ExchangeAdd(product: p);
      }
    }
    return null;
  }

  Future<void> _showReturnDialog() async {
    final all = await LocalDbService.getTransactions();
    if (!mounted) return;
    // Only real sales can be returned — never a return itself.
    final sales = all.where((t) => !t.isReturn).toList();

    var query = '';
    TransactionRecord? picked;
    // Line index -> 'return' or 'exchange'. Absent means "keeping it".
    var mode = <int, String>{};
    var cap = <int, int>{};
    final adds = <_ExchangeAdd>[];
    final addCtrl = TextEditingController();
    var addQuery = '';
    var payMethod = 'cash';
    var busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Map<int, int> selectedQty() => {
            for (final e in mode.entries)
              if ((cap[e.key] ?? 0) > 0) e.key: cap[e.key]!,
          };

          TransactionRecord? reversalOf(TransactionRecord bill) {
            final q = selectedQty();
            if (q.isEmpty) return null;
            return _buildReversalRecord(
              original: bill,
              qtyByIndex: q,
              paymentMethod: payMethod,
              // Anything handed back out makes this an exchange.
              exchange: adds.isNotEmpty ||
                  mode.values.any((m) => m == 'exchange'),
            );
          }

          final returningTotal = picked == null
              ? 0.0
              : (reversalOf(picked!)?.total.abs() ?? 0.0);
          final newSale = adds.isEmpty
              ? null
              : _buildExchangeSale(adds, paymentMethod: payMethod);
          final newTotal = newSale?.total ?? 0.0;
          final difference = newTotal - returningTotal;
          final collecting = difference > 0;
          final nothingChosen = returningTotal <= 0 && adds.isEmpty;

          void selectBill(TransactionRecord t) {
            final done = _alreadyReturned(t, all);
            final caps = <int, int>{};
            for (var i = 0; i < t.items.length; i++) {
              final line = t.items[i];
              final key = '${line.productId}::${line.variantId ?? ''}';
              final left = line.quantity - (done[key] ?? 0);
              caps[i] = left < 0 ? 0 : left;
            }
            setLocal(() {
              picked = t;
              cap = caps;
              mode = {};
              adds.clear();
              payMethod = const {
                'cash': 'cash',
                'card': 'card',
                'upi': 'upi',
              }[t.paymentMethod] ??
                  'cash';
            });
          }

          void addLine(_ExchangeAdd a) {
            final i = adds.indexWhere((e) => e.key == a.key);
            setLocal(() {
              if (i >= 0) {
                adds[i].qty++;
              } else {
                adds.add(a);
              }
              addCtrl.clear();
              addQuery = '';
            });
          }

          /// Builds the receipt for what the customer walks out with: the new
          /// goods when there are any, otherwise the returned ones.
          TransactionRecord? receiptRecord() {
            if (picked == null) return null;
            if (adds.isNotEmpty) {
              return _buildExchangeSale(
                adds,
                paymentMethod: payMethod,
                invoiceNumber: LocalDbService.generateInvoiceId(),
                customerName: picked!.customerName,
                customerPhone: picked!.customerPhone,
              );
            }
            return reversalOf(picked!);
          }

          Future<void> complete() async {
            if (busy || picked == null || nothingChosen) return;
            setLocal(() => busy = true);
            try {
              // Re-check the allowance against live data: another till (or
              // another dialog) may have returned these lines meanwhile.
              final fresh = await LocalDbService.getTransactions();
              final done = _alreadyReturned(picked!, fresh);
              final safe = <int, int>{};
              final counted = <String, int>{};
              for (final e in selectedQty().entries) {
                final line = picked!.items[e.key];
                final key = '${line.productId}::${line.variantId ?? ''}';
                final left =
                    line.quantity - (done[key] ?? 0) - (counted[key] ?? 0);
                final take = e.value < left ? e.value : left;
                if (take <= 0) continue;
                safe[e.key] = take;
                counted[key] = (counted[key] ?? 0) + take;
              }
              if (safe.isNotEmpty) {
                await _saveReversal(
                  _buildReversalRecord(
                    original: picked!,
                    qtyByIndex: safe,
                    paymentMethod: payMethod,
                    exchange: adds.isNotEmpty ||
                        mode.values.any((m) => m == 'exchange'),
                  ),
                );
              }
              if (adds.isNotEmpty) {
                await LocalDbService.insertTransaction(
                  _buildExchangeSale(
                    adds,
                    paymentMethod: payMethod,
                    invoiceNumber: LocalDbService.generateInvoiceId(),
                    customerName: picked!.customerName,
                    customerPhone: picked!.customerPhone,
                  ),
                );
                await ConnectivityService.instance.refreshUnsyncedCount();
                if (ConnectivityService.instance.isOnline) {
                  ConnectivityService.instance.syncNow();
                }
                _loadProducts();
                _loadDashboardData();
              }
            } catch (e) {
              if (ctx.mounted) setLocal(() => busy = false);
              if (!mounted) return;
              _showToast('Could not save: $e', isError: true);
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (!mounted) return;
            final amt =
                '$_currencySymbol${difference.abs().toStringAsFixed(2)}';
            _showToast(
              adds.isEmpty
                  ? 'Return complete — $amt refunded.'
                  : collecting
                      ? 'Exchange complete — $amt collected.'
                      : 'Exchange complete — $amt refunded.',
            );
          }

          final filteredBills = () {
            final q = query.trim().toLowerCase();
            final list = q.isEmpty
                ? sales
                : sales.where((t) {
                    return (t.invoiceNumber?.toLowerCase().contains(q) ??
                            false) ||
                        (t.customerName?.toLowerCase().contains(q) ?? false) ||
                        (t.customerPhone?.toLowerCase().contains(q) ?? false) ||
                        t.id.substring(0, 6).toLowerCase().contains(q) ||
                        t.items.any(
                          (i) => i.productName.toLowerCase().contains(q),
                        );
                  }).toList();
            return list.take(40).toList();
          }();

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 12, 14),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assignment_return_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            picked == null
                                ? 'Return / Exchange'
                                : 'Return / Exchange — '
                                    '${_reversalBaseRef(picked!)}',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        if (picked != null)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setLocal(() {
                                      picked = null;
                                      mode = {};
                                      cap = {};
                                      adds.clear();
                                      query = '';
                                      addCtrl.clear();
                                      addQuery = '';
                                    }),
                            child: Text(
                              'Change bill',
                              style: GoogleFonts.inter(fontSize: 12),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: busy ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  if (picked == null) ...[
                    // ── Pick the bill ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setLocal(() => query = v),
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: _dlgInputDecor(
                          'Search invoice, customer, phone or item...',
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 340,
                      child: filteredBills.isEmpty
                          ? Center(
                              child: Text(
                                'No bills found',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: filteredBills.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: AppColors.border,
                              ),
                              itemBuilder: (_, i) {
                                final t = filteredBills[i];
                                final n = t.items.fold(
                                  0,
                                  (s, e) => s + e.quantity,
                                );
                                return InkWell(
                                  onTap: () => selectBill(t),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _reversalBaseRef(t),
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              Text(
                                                '${t.createdAt.day.toString().padLeft(2, '0')}/'
                                                '${t.createdAt.month.toString().padLeft(2, '0')}/'
                                                '${t.createdAt.year}  ·  $n item'
                                                '${n == 1 ? '' : 's'}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            t.customerName?.isNotEmpty == true
                                                ? t.customerName!
                                                : '—',
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              color: AppColors.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '$_currencySymbol'
                                          '${t.total.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    // ── Add a product (typed or scanned) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: addCtrl,
                            autofocus: true,
                            enabled: !busy,
                            onChanged: (v) => setLocal(() => addQuery = v),
                            onSubmitted: (v) {
                              final hit =
                                  _scanMatch(v) ?? _sellableMatches(v).firstOrNull;
                              if (hit != null) addLine(hit);
                            },
                            style: GoogleFonts.inter(fontSize: 13),
                            decoration: _dlgInputDecor(
                              'Scan barcode or search a product to add...',
                            ).copyWith(
                              prefixIcon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          ...() {
                            final matches = _sellableMatches(addQuery);
                            if (matches.isEmpty) return <Widget>[];
                            return [
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    for (final m in matches)
                                      InkWell(
                                        onTap: () => addLine(m),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 9,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  m.name,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12.5,
                                                    color: AppColors.textDark,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '$_currencySymbol'
                                                '${m.price.toStringAsFixed(2)}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ];
                          }(),
                        ],
                      ),
                    ),

                    // ── The bill's lines, and anything being given out ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dlgLabel('ITEMS ON THIS BILL'),
                            const SizedBox(height: 8),
                            for (var i = 0; i < picked!.items.length; i++)
                              _returnLineRow(
                                line: picked!.items[i],
                                remaining: cap[i] ?? 0,
                                selected: mode[i],
                                onPick: busy
                                    ? null
                                    : (m) => setLocal(() {
                                          if (mode[i] == m) {
                                            mode.remove(i);
                                          } else {
                                            mode[i] = m;
                                          }
                                        }),
                              ),
                            if (adds.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _dlgLabel('NEW ITEMS ON THIS INVOICE'),
                              const SizedBox(height: 8),
                              for (final a in adds)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textDark,
                                              ),
                                            ),
                                            Text(
                                              '$_currencySymbol'
                                              '${a.price.toStringAsFixed(2)}'
                                              '  ·  in stock ${a.stock}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _qtyStepBtn(
                                        Icons.remove_rounded,
                                        busy
                                            ? null
                                            : () => setLocal(() {
                                                  if (a.qty > 1) {
                                                    a.qty--;
                                                  } else {
                                                    adds.remove(a);
                                                  }
                                                }),
                                      ),
                                      SizedBox(
                                        width: 34,
                                        child: Text(
                                          '${a.qty}',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                      ),
                                      _qtyStepBtn(
                                        Icons.add_rounded,
                                        busy
                                            ? null
                                            : () => setLocal(() => a.qty++),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        iconSize: 16,
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: AppColors.textMuted,
                                        ),
                                        onPressed: busy
                                            ? null
                                            : () =>
                                                setLocal(() => adds.remove(a)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),

                    // ── Money and actions ──
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Column(
                        children: [
                          _reviewRow(
                            'OLD BILL AMOUNT',
                            '$_currencySymbol'
                                '${picked!.total.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 6),
                          _reviewRow(
                            'RETURNING',
                            '-$_currencySymbol'
                                '${returningTotal.toStringAsFixed(2)}',
                            color: AppColors.success,
                          ),
                          const SizedBox(height: 6),
                          _reviewRow(
                            'NEW ITEMS',
                            '$_currencySymbol'
                                '${newTotal.toStringAsFixed(2)}',
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: AppColors.border),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                collecting
                                    ? 'COLLECT FROM CUSTOMER'
                                    : 'REFUND TO CUSTOMER',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$_currencySymbol'
                                '${difference.abs().toStringAsFixed(2)}',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: collecting
                                      ? AppColors.primary
                                      : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: busy || nothingChosen
                                    ? null
                                    : () {
                                        final r = receiptRecord();
                                        if (r != null) {
                                          _printRecord(r, toPrinter: true);
                                        }
                                      },
                                icon: const Icon(Icons.print_outlined, size: 15),
                                label: Text(
                                  'PRINT RECEIPT',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: busy || nothingChosen
                                    ? null
                                    : () {
                                        final r = receiptRecord();
                                        if (r == null) return;
                                        _sendInvoiceViaWhatsApp(
                                          r,
                                          picked!.customerPhone ?? '',
                                        );
                                      },
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 15,
                                ),
                                label: Text(
                                  'E-BILL',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: busy || nothingChosen
                                      ? null
                                      : complete,
                                  icon: busy
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    adds.isEmpty
                                        ? 'COMPLETE REFUND'
                                        : 'COMPLETE EXCHANGE',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    addCtrl.dispose();
  }

  Widget _reviewRow(String label, String value, {Color? color}) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textDark,
          ),
        ),
      ],
    );
  }

  /// One line of the original bill: pick RETURN or EXCHANGE and the row turns
  /// green. A line already sent back on an earlier return is locked.
  Widget _returnLineRow({
    required TransactionItem line,
    required int remaining,
    required String? selected,
    required void Function(String mode)? onPick,
  }) {
    final exhausted = remaining <= 0;
    final on = selected != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: on
            ? AppColors.success.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: on ? AppColors.success : AppColors.border,
          width: on ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.displayName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: exhausted ? AppColors.textMuted : AppColors.textDark,
                  ),
                ),
                Text(
                  exhausted
                      ? 'already returned'
                      : '$_currencySymbol${line.price.toStringAsFixed(2)}'
                          '  ·  ${remaining < line.quantity ? '$remaining of ${line.quantity} left' : 'qty ${line.quantity}'}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!exhausted) ...[
            _pickChip(
              'RETURN',
              selected == 'return',
              onPick == null ? null : () => onPick('return'),
            ),
            const SizedBox(width: 6),
            _pickChip(
              'EXCHANGE',
              selected == 'exchange',
              onPick == null ? null : () => onPick('exchange'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickChip(String label, bool on, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.success : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: on ? AppColors.success : AppColors.border,
            width: on ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: on ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _qtyStepBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? AppColors.border : AppColors.textDark,
        ),
      ),
    );
  }

  void _printCurrentBill(
    CartProvider cart, {
    String docType = 'Invoice',
    bool toPrinter = false,
  }) {
    _pendingInvoiceNumber ??= LocalDbService.generateInvoiceId();
    _printRecord(
      _snapshotCart(cart, invoiceNumber: _pendingInvoiceNumber),
      docType: docType,
      toPrinter: toPrinter,
    );
  }

  void _showPrintBillDialog(CartProvider cart) {
    // Restore the toggles to however they were last left.
    bool sendToPrinter = _sendToPrinterPref;
    bool sendWhatsApp = _sendWhatsAppPref;
    String docType = 'Invoice';
    final phoneCtrl = TextEditingController(text: cart.customerPhone);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Print Bill',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 16),
                // Document type selector
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocal(() => docType = 'Invoice'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: docType == 'Invoice'
                                ? AppColors.primary
                                : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: docType == 'Invoice'
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 14,
                                color: docType == 'Invoice'
                                    ? Colors.white
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Invoice',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: docType == 'Invoice'
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocal(() => docType = 'Quotation'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: docType == 'Quotation'
                                ? AppColors.primary
                                : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: docType == 'Quotation'
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 14,
                                color: docType == 'Quotation'
                                    ? Colors.white
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Quotation',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: docType == 'Quotation'
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Printer toggle
                InkWell(
                  onTap: () => setLocal(() => sendToPrinter = !sendToPrinter),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: sendToPrinter
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sendToPrinter
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.print_rounded,
                          size: 16,
                          color: sendToPrinter
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Send to Printer',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sendToPrinter
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                ),
                              ),
                              Text(
                                'Sends directly to default printer',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: sendToPrinter,
                          onChanged: (v) => setLocal(() => sendToPrinter = v),
                          activeTrackColor: AppColors.primary,
                          activeThumbColor: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setLocal(() => sendWhatsApp = !sendWhatsApp),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: sendWhatsApp
                          ? const Color(0xFF25D366).withValues(alpha: 0.08)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sendWhatsApp
                            ? const Color(0xFF25D366)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 16,
                          color: sendWhatsApp
                              ? const Color(0xFF1AAD56)
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Send via WhatsApp',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sendWhatsApp
                                      ? const Color(0xFF1AAD56)
                                      : AppColors.textMuted,
                                ),
                              ),
                              Text(
                                'Opens WhatsApp Web with invoice',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: sendWhatsApp,
                          onChanged: (v) => setLocal(() => sendWhatsApp = v),
                          activeTrackColor: const Color(0xFF25D366),
                          activeThumbColor: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final snapshot = _snapshotCart(cart);
                          // Remember the toggle states for next time.
                          _sendToPrinterPref = sendToPrinter;
                          _sendWhatsAppPref = sendWhatsApp;
                          LocalDbService.saveSettings({
                            'print_send_to_printer': sendToPrinter ? '1' : '0',
                            'print_send_whatsapp': sendWhatsApp ? '1' : '0',
                          });
                          Navigator.pop(ctx);
                          if (sendToPrinter)
                            _printCurrentBill(
                              cart,
                              docType: docType,
                              toPrinter: true,
                            );
                          if (sendWhatsApp) {
                            _sendInvoiceViaWhatsApp(
                              snapshot,
                              phoneCtrl.text.trim(),
                              docType: docType,
                            );
                          }
                        },
                        icon: sendToPrinter
                            ? const Icon(Icons.print_rounded, size: 15)
                            : const SizedBox.shrink(),
                        label: Text(
                          sendToPrinter ? 'Print' : 'Confirm',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearPrintingState() {
    _printSafetyTimer?.cancel();
    _printSafetyTimer = null;
    if (mounted && _isPrinting) setState(() => _isPrinting = false);
  }

  Future<void> _printRecord(
    TransactionRecord tx, {
    String? paperSize,
    String docType = 'Invoice',
    bool toPrinter = false,
  }) async {
    _clearPrintingState();
    if (!mounted) return;
    setState(() => _isPrinting = true);
    _printSafetyTimer = Timer(const Duration(seconds: 30), _clearPrintingState);

    try {
      final Uint8List pdfBytes = await ReceiptPrinter.buildPdf(
        tx,
        storeName: _storeName,
        storeAddress: _storeAddress,
        storePhone: _storePhone,
        storeEmail: _storeEmail,
        storeGstin: _storeGstin,
        receiptFooter: _receiptFooter,
        taxLabel: _taxLabel,
        taxRate: _taxRateDisplay,
        currencySymbol: _currencySymbol,
        paperSize: paperSize ?? _paperSize,
        orientation: _printOrientation,
        layout: _invoiceLayout,
        storeTerms: _storeTerms,
        logoPath: _logoPath,
        storeUpiId: _storeUpiId,
        docType: docType,
      );

      _clearPrintingState();

      final receiptName = tx.invoiceNumber != null
          ? 'Receipt-${tx.invoiceNumber}'
          : 'Receipt-${tx.id.substring(0, 6).toUpperCase()}';

      if (toPrinter) {
        // Send directly to the selected printer silently — no UI opens
        Printer? target;
        final printers = await Printing.listPrinters();
        if (_selectedPrinter != 'System Default' &&
            _selectedPrinter != 'PDF Export' &&
            _selectedPrinter.isNotEmpty) {
          for (final pr in printers) {
            if (pr.name == _selectedPrinter) {
              target = pr;
              break;
            }
          }
        }
        if (target == null) {
          for (final pr in printers) {
            if (pr.isDefault) {
              target = pr;
              break;
            }
          }
        }
        // Thermal printers ignore rasterised PDFs — send raw ESC/POS text
        // straight to the spooler instead. Only the PDF path handles A4/A5.
        final effPaper = paperSize ?? _paperSize;
        final isThermal = !['A4', 'A5'].contains(effPaper);
        if (isThermal && target != null) {
          final logo = await decodeReceiptLogo(_logoPath);
          final escBytes = ThermalPrinter.buildReceipt(
            tx,
            storeName: _storeName,
            storeAddress: _storeAddress,
            storePhone: _storePhone,
            storeGstin: _storeGstin,
            receiptFooter: _receiptFooter,
            taxLabel: _taxLabel,
            taxRate: _taxRateDisplay,
            currencySymbol: _currencySymbol,
            storeUpiId: _storeUpiId,
            logo: logo,
          );
          final printed = ThermalPrinter.rawPrint(target.name, escBytes);
          if (printed) return; // printed via ESC/POS
          // Fall through to the PDF path if text printing failed.
        }
        if (target != null) {
          final ok = await Printing.directPrintPdf(
            printer: target,
            onLayout: (_) async => pdfBytes,
            name: receiptName,
          );
          if (!ok && mounted) _showToast('Could not print', isError: true);
        } else {
          await Printing.layoutPdf(
            onLayout: (_) async => pdfBytes,
            name: receiptName,
          );
        }
      } else {
        // Open the system print dialog with the PDF
        await Printing.layoutPdf(
          onLayout: (_) async => pdfBytes,
          name: receiptName,
        );
      }
    } catch (e) {
      if (mounted) _showToast('Could not open PDF: $e', isError: true);
    } finally {
      _clearPrintingState();
    }
  }

  TransactionRecord _testReceipt() => TransactionRecord(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    customerName: 'Test Customer',
    items: const [
      TransactionItem(
        productId: '1',
        productName: 'Sample Product A',
        price: 250,
        quantity: 2,
      ),
      TransactionItem(
        productId: '2',
        productName: 'Sample Product B',
        price: 180,
        quantity: 1,
      ),
    ],
    subtotal: 680,
    discountAmount: 0,
    taxAmount: 102,
    total: 782,
    paymentMethod: 'cash',
    createdAt: DateTime.now(),
  );

  void _closeBill(BuildContext context, CartProvider cart) {
    bool sendWaAfterClose = false;
    final hasPhone = cart.customerPhone.isNotEmpty;
    final hasWa = _waPhoneNumberId.isNotEmpty && _waAccessToken.isNotEmpty;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Confirm Payment',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Charge $_currencySymbol${cart.total.toStringAsFixed(2)} for ${cart.itemCount} item(s)?',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
              ),
              if (hasPhone && hasWa) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: () =>
                      setLocal(() => sendWaAfterClose = !sendWaAfterClose),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: sendWaAfterClose
                          ? const Color(0xFF25D366).withValues(alpha: 0.08)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: sendWaAfterClose
                            ? const Color(0xFF25D366)
                            : const Color(0xFFE0E0E0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: sendWaAfterClose
                              ? const Color(0xFF1AAD56)
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Send invoice via WhatsApp',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: sendWaAfterClose
                                  ? const Color(0xFF1AAD56)
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                        Switch(
                          value: sendWaAfterClose,
                          onChanged: (v) =>
                              setLocal(() => sendWaAfterClose = v),
                          activeTrackColor: const Color(0xFF25D366),
                          activeThumbColor: Colors.white,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: AppColors.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Reuse the number already printed on this bill, if any.
                final invNum =
                    _pendingInvoiceNumber ?? LocalDbService.generateInvoiceId();
                _pendingInvoiceNumber = null;
                final snapshot = _snapshotCart(cart, invoiceNumber: invNum);
                final phone = cart.customerPhone;
                Navigator.pop(ctx);
                try {
                  await cart.checkout(invoiceNumber: invNum);
                } catch (e) {
                  // The checkout is atomic, so nothing was saved: keep the
                  // cart and the invoice number intact for a clean retry and
                  // tell the user, instead of leaving a dead-looking button.
                  _pendingInvoiceNumber = invNum;
                  // Guard on the State, not on `context`: that one belongs to
                  // the cart's Consumer, which is unmounted whenever the view
                  // swaps (opening Settings mid-checkout) — and dropping the
                  // reason is the exact silence this fix exists to remove.
                  if (!mounted) return;
                  _showToast('Could not save the bill: $e', isError: true);
                  return;
                }
                _customerNameCtrl.clear();
                _customerPhoneCtrl.clear();
                _loadProducts();
                _loadDashboardData();
                if (!context.mounted) return;
                _showToast('Payment successful!');
                if (_autoPrint) {
                  await _printRecord(snapshot);
                }
                _autoSavePdf(snapshot);
                if (sendWaAfterClose) {
                  _sendInvoiceViaWhatsApp(snapshot, phone);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Confirm',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoSavePdf(TransactionRecord tx) async {
    try {
      final pdfBytes = await ReceiptPrinter.buildPdf(
        tx,
        storeName: _storeName,
        storeAddress: _storeAddress,
        storePhone: _storePhone,
        storeEmail: _storeEmail,
        storeGstin: _storeGstin,
        receiptFooter: _receiptFooter,
        taxLabel: _taxLabel,
        taxRate: _taxRateDisplay,
        currencySymbol: _currencySymbol,
        paperSize: _paperSize,
        orientation: _printOrientation,
        layout: _invoiceLayout,
        storeTerms: _storeTerms,
        logoPath: _logoPath,
        storeUpiId: _storeUpiId,
      );
      final receiptName = tx.invoiceNumber != null
          ? 'Receipt-${tx.invoiceNumber}'
          : 'Receipt-${tx.id.substring(0, 6).toUpperCase()}';
      final home = Platform.environment['HOME'] ?? '';
      final safeName = _storeName.trim().isEmpty
          ? 'BillCat'
          : _storeName.trim();
      final folder = Directory('$home/Documents/$safeName Receipts');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      await File('${folder.path}/$receiptName.pdf').writeAsBytes(pdfBytes);
    } catch (_) {}
  }

  Future<void> _sendInvoiceViaWhatsApp(
    TransactionRecord tx,
    String phone, {
    String docType = 'Invoice',
  }) async {
    if (phone.isEmpty) {
      _showToast('No customer phone number to send to.', isError: true);
      return;
    }

    final invoiceNo = tx.invoiceNumber ?? tx.id.substring(0, 6).toUpperCase();
    final rawUid = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';
    final shortUid = rawUid
        .replaceAll('-', '')
        .substring(0, rawUid.length >= 6 ? 6 : rawUid.length)
        .toUpperCase();
    final invoiceLink =
        'https://billcat.in/invoices/$shortUid/$_branchNumber/Bill-$invoiceNo';

    // If Meta API is configured, send directly
    if (_waPhoneNumberId.isNotEmpty && _waAccessToken.isNotEmpty) {
      _showToast('Sending via WhatsApp...');
      try {
        final pdfBytes = await ReceiptPrinter.buildPdf(
          tx,
          storeName: _storeName,
          storeAddress: _storeAddress,
          storePhone: _storePhone,
          storeEmail: _storeEmail,
          storeGstin: _storeGstin,
          receiptFooter: _receiptFooter,
          taxLabel: _taxLabel,
          taxRate: _taxRateDisplay,
          currencySymbol: _currencySymbol,
          paperSize: _paperSize,
          orientation: _printOrientation,
          layout: _invoiceLayout,
          storeTerms: _storeTerms,
          logoPath: _logoPath,
          storeUpiId: _storeUpiId,
          docType: docType,
        );
        final svc = _wa.WhatsAppService(
          phoneNumberId: _waPhoneNumberId,
          accessToken: _waAccessToken,
        );
        final ok = await svc.sendInvoicePdf(
          toPhone: phone,
          pdfBytes: pdfBytes,
          invoiceNo: invoiceNo,
          storeName: _storeName,
          customerName: tx.customerName ?? '',
          amount: '$_currencySymbol${tx.total.toStringAsFixed(2)}',
          date:
              '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
          docType: docType,
          invoiceLink: invoiceLink,
        );
        if (mounted)
          _showToast(
            ok ? 'Invoice sent via WhatsApp!' : 'WhatsApp send failed.',
            isError: !ok,
          );
      } catch (e) {
        if (mounted) _showToast('WhatsApp error: $e', isError: true);
      }
      return;
    }

    // Fallback: open WhatsApp Web with pre-filled message
    try {
      // Normalize: strip formatting, prepend dial code if no country code present
      String normalized = phone.replaceAll(RegExp(r'[\s\-().]'), '');
      if (!normalized.startsWith('+') && !normalized.startsWith('00')) {
        normalized = _dialCode + normalized.replaceFirst(RegExp(r'^0'), '');
      }
      normalized = normalized.replaceAll('+', '');

      final customerName = (tx.customerName?.isNotEmpty ?? false)
          ? tx.customerName!
          : 'Valued Customer';
      final dateStr =
          '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}';
      final message = Uri.encodeComponent(
        'Hello $customerName,\n\n'
        'Thank you for choosing $_storeName.\n'
        'Your e-bill for $docType #$invoiceNo has been generated successfully.\n\n'
        'Amount: $_currencySymbol${tx.total.toStringAsFixed(2)}\n'
        'Date: $dateStr\n'
        'Payment Status: Paid\n\n'
        'For any queries, feel free to contact us.\n'
        'Thank you for your support!\n\n'
        '— $_storeName\n\n'
        '$invoiceLink',
      );
      final url =
          'https://web.whatsapp.com/send?phone=$normalized&text=$message';
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        // Reuse existing WhatsApp Web tab in Chrome if open, else open new tab
        final appleScript =
            '''
tell application "Google Chrome"
  set didReuse to false
  repeat with w in windows
    set tabIdx to 0
    repeat with t in tabs of w
      set tabIdx to tabIdx + 1
      if (URL of t) starts with "https://web.whatsapp.com" then
        set URL of t to "$url"
        set index of w to 1
        set active tab index of w to tabIdx
        set didReuse to true
        exit repeat
      end if
    end repeat
    if didReuse then exit repeat
  end repeat
  if not didReuse then
    if (count of windows) > 0 then
      tell front window to make new tab with properties {URL:"$url"}
    else
      open location "$url"
    end if
  end if
  activate
end tell
''';
        final result = await Process.run('osascript', ['-e', appleScript]);
        if (result.exitCode != 0) {
          // Fallback if Chrome isn't running
          await Process.run('open', [url]);
        }
      }

      if (mounted) _showToast('Opening WhatsApp Web...');
    } catch (e) {
      if (mounted) _showToast('Error: $e', isError: true);
    }
  }

  void _showAddCustomerDialog(CartProvider cart) {
    final nameCtrl = TextEditingController(text: _customerNameCtrl.text);
    final phoneCtrl = TextEditingController(text: _customerPhoneCtrl.text);
    final addressCtrl = TextEditingController();
    final phoneFocus = FocusNode();
    final addressFocus = FocusNode();

    Future<void> doSave(BuildContext ctx) async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;
      await LocalDbService.upsertCustomerByPhone(
        name: name,
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        address: addressCtrl.text.trim().isEmpty
            ? null
            : addressCtrl.text.trim(),
      );
      _customerNameCtrl.text = name;
      _customerPhoneCtrl.text = phoneCtrl.text.trim();
      cart.customerName = name;
      cart.customerPhone = phoneCtrl.text.trim();
      if (ConnectivityService.instance.isOnline) {
        ConnectivityService.instance.syncNow();
      }
      if (context.mounted) {
        Navigator.pop(ctx);
        _showToast('Customer saved!');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_add_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Add Customer',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Fields ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dlgLabel('CUSTOMER NAME'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) {
                        if (phoneCtrl.text.trim().isNotEmpty) {
                          doSave(ctx);
                        } else {
                          phoneFocus.requestFocus();
                        }
                      },
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                      decoration: _dlgInputDecor('e.g. Ravi Kumar'),
                    ),
                    const SizedBox(height: 16),
                    _dlgLabel('PHONE NUMBER'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneCtrl,
                      focusNode: phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => doSave(ctx),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                      decoration: _dlgInputDecor('e.g. 9876543210'),
                    ),
                    const SizedBox(height: 16),
                    _dlgLabel('ADDRESS (OPTIONAL)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressCtrl,
                      focusNode: addressFocus,
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => doSave(ctx),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                      decoration: _dlgInputDecor('Street, city…'),
                    ),
                    const SizedBox(height: 24),
                    // ── Actions ───────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => doSave(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Save Customer',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomProductDialog(CartProvider cart) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Custom Product',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Product Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '\$',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              if (name.isNotEmpty && price > 0) {
                cart.addProduct(
                  Product(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    price: price,
                    category: 'Custom',
                    emoji: '📦',
                    sku: 'CUSTOM',
                    stock: 99,
                  ),
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bulk Barcode Print View ──────────────────────────────────────────────────

  Future<void> _showBulkPrintDialog() async {
    final labelWCtrl = TextEditingController(
      text: _barcodeLabelW.toStringAsFixed(
        _barcodeLabelW == _barcodeLabelW.truncateToDouble() ? 0 : 1,
      ),
    );
    final labelHCtrl = TextEditingController(
      text: _barcodeLabelH.toStringAsFixed(
        _barcodeLabelH == _barcodeLabelH.truncateToDouble() ? 0 : 1,
      ),
    );
    final perRowCtrl = TextEditingController(text: '$_barcodePerRow');
    final searchCtrl = TextEditingController();
    final qtys = Map<String, int>.from(_bulkPrintQtys);
    final selected = Map<String, bool>.from(_bulkPrintSelected);
    List<String> printers = List<String>.from(_bulkPrinters);
    String printer = _barcodePrinter;
    String searchQ = '';

    // Every variant gets its own barcode number and its own label entry.
    await LocalDbService.assignMissingVariantBarcodeNos();
    final variantsByProduct =
        await LocalDbService.getVariantsGroupedByProduct();
    if (mounted) setState(() => _variantsByProduct = variantsByProduct);
    final printItems = <Product>[];
    for (final p in _products) {
      final pVariants = variantsByProduct[p.id] ?? const <ProductVariant>[];
      if (pVariants.isEmpty) {
        printItems.add(p);
      } else {
        for (final v in pVariants) {
          printItems.add(
            Product(
              id: v.id,
              // Matches TransactionItem.displayName so labels, receipts and
              // history all read the same way.
              name: '${p.name} (${v.label})',
              price: v.price,
              category: p.category,
              emoji: p.emoji,
              sku: v.sku.isNotEmpty ? v.sku : p.sku,
              stock: v.stock,
              barcodeNo: v.barcodeNo,
              // Variants are taxed at the parent product's rate — without this
              // the label would price them at 0% tax.
              taxPercent: p.taxPercent,
            ),
          );
        }
      }
    }
    if (!mounted) return;

    // Per-item qty TextEditingControllers
    final qtyCtrlMap = <String, TextEditingController>{
      for (final p in printItems)
        p.id: TextEditingController(text: '${qtys[p.id] ?? 1}'),
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (printers.length <= 1) {
            Printing.listPrinters().then((list) {
              final names = <String>[
                'System Default',
                ...list.map((p) => p.name),
              ];
              if (ctx.mounted)
                setLocal(() {
                  printers = names;
                  if (names.contains(_barcodePrinter))
                    printer = _barcodePrinter;
                });
            });
          }
          final filteredProducts = searchQ.isEmpty
              ? printItems
              : printItems.where((p) {
                  final q = searchQ.toLowerCase();
                  return p.name.toLowerCase().contains(q) ||
                      p.sku.toLowerCase().contains(q);
                }).toList();
          final total = printItems
              .where((p) => selected[p.id] == true)
              .fold<int>(0, (s, p) => s + (qtys[p.id] ?? 0));

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 60,
              vertical: 40,
            ),
            child: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
                    child: Row(
                      children: [
                        Text(
                          'Print Barcodes',
                          style: GoogleFonts.manrope(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Settings bar ──
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Size',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 7),
                        _miniNumField(labelWCtrl, 'W', 60),
                        const SizedBox(width: 5),
                        _miniNumField(labelHCtrl, 'H', 60),
                        const SizedBox(width: 16),
                        Text(
                          'Per Row',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 7),
                        _miniNumField(perRowCtrl, '', 44),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.print_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: printers.contains(printer)
                                  ? printer
                                  : 'System Default',
                              isDense: true,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              items: printers
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text(
                                        n,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppColors.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setLocal(
                                () => printer = v ?? 'System Default',
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Search bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.search_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchCtrl,
                              onChanged: (v) => setLocal(() => searchQ = v),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Search products…',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (searchQ.isNotEmpty)
                            InkWell(
                              onTap: () {
                                searchCtrl.clear();
                                setLocal(() => searchQ = '');
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                  ),
                  // ── Products grid ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: filteredProducts.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 32,
                                      color: AppColors.textMuted.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No products found',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 1.3,
                                  ),
                              itemCount: filteredProducts.length,
                              itemBuilder: (_, i) {
                                final p = filteredProducts[i];
                                final isSelected = selected[p.id] == true;
                                final qty = qtys[p.id] ?? 1;
                                final qtyCtrl = qtyCtrlMap[p.id] ??=
                                    TextEditingController(text: '$qty');
                                return GestureDetector(
                                  onTap: () {
                                    setLocal(() {
                                      if (isSelected) {
                                        selected[p.id] = false;
                                      } else {
                                        selected[p.id] = true;
                                        if (!qtys.containsKey(p.id)) {
                                          qtys[p.id] = p.stock > 0
                                              ? p.stock
                                              : 1;
                                          qtyCtrlMap[p.id]?.text =
                                              '${qtys[p.id]}';
                                        }
                                      }
                                    });
                                  },
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary.withValues(
                                                  alpha: 0.04,
                                                )
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.border,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            8,
                                            8,
                                            8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 14,
                                                ),
                                                child: Text(
                                                  p.name,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: isSelected
                                                        ? AppColors.primary
                                                        : AppColors.textDark,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Container(
                                                width: double.infinity,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF5F5F5,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                child: CustomPaint(
                                                  painter: _BarcodePainter(
                                                    p.sku,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                p.sku,
                                                style: GoogleFonts.inter(
                                                  fontSize: 9,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                              const Spacer(),
                                              if (isSelected)
                                                Container(
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: AppColors
                                                        .surfaceVariant,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          7,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      InkWell(
                                                        onTap: qty > 1
                                                            ? () {
                                                                setLocal(
                                                                  () =>
                                                                      qtys[p.id] =
                                                                          qty -
                                                                          1,
                                                                );
                                                                qtyCtrl.text =
                                                                    '${qty - 1}';
                                                              }
                                                            : null,
                                                        borderRadius:
                                                            const BorderRadius.horizontal(
                                                              left:
                                                                  Radius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                        child: Container(
                                                          width: 26,
                                                          height: 28,
                                                          alignment:
                                                              Alignment.center,
                                                          child: Icon(
                                                            Icons
                                                                .remove_rounded,
                                                            size: 11,
                                                            color: qty > 1
                                                                ? AppColors
                                                                      .textDark
                                                                : AppColors
                                                                      .textMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      Container(
                                                        width: 1,
                                                        height: 16,
                                                        color: AppColors.border,
                                                      ),
                                                      Expanded(
                                                        child: TextFormField(
                                                          controller: qtyCtrl,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          inputFormatters: [
                                                            FilteringTextInputFormatter
                                                                .digitsOnly,
                                                          ],
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: AppColors
                                                                    .textDark,
                                                              ),
                                                          decoration:
                                                              const InputDecoration(
                                                                isDense: true,
                                                                border:
                                                                    InputBorder
                                                                        .none,
                                                                contentPadding:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                          onChanged: (v) {
                                                            final n =
                                                                int.tryParse(v);
                                                            if (n != null &&
                                                                n > 0)
                                                              setLocal(
                                                                () =>
                                                                    qtys[p.id] =
                                                                        n,
                                                              );
                                                          },
                                                        ),
                                                      ),
                                                      Container(
                                                        width: 1,
                                                        height: 16,
                                                        color: AppColors.border,
                                                      ),
                                                      InkWell(
                                                        onTap: () {
                                                          setLocal(
                                                            () => qtys[p.id] =
                                                                qty + 1,
                                                          );
                                                          qtyCtrl.text =
                                                              '${qty + 1}';
                                                        },
                                                        borderRadius:
                                                            const BorderRadius.horizontal(
                                                              right:
                                                                  Radius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                        child: Container(
                                                          width: 26,
                                                          height: 28,
                                                          alignment:
                                                              Alignment.center,
                                                          child: const Icon(
                                                            Icons.add_rounded,
                                                            size: 11,
                                                            color: AppColors
                                                                .textDark,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    '${p.stock} in stock',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 9,
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ── Footer ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      children: [
                        Text(
                          '$total label${total != 1 ? 's' : ''} to print',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textMuted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: total == 0
                              ? null
                              : () async {
                                  final w =
                                      double.tryParse(labelWCtrl.text) ??
                                      _barcodeLabelW;
                                  final h =
                                      double.tryParse(labelHCtrl.text) ??
                                      _barcodeLabelH;
                                  final perRow =
                                      int.tryParse(perRowCtrl.text) ??
                                      _barcodePerRow;
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _barcodeLabelW = w;
                                    _barcodeLabelH = h;
                                    _barcodePerRow = perRow;
                                    _barcodePrinter = printer;
                                  });
                                  LocalDbService.saveSettings({
                                    'barcode_label_w': w.toString(),
                                    'barcode_label_h': h.toString(),
                                    'barcode_per_row': perRow.toString(),
                                    'barcode_printer': printer,
                                  });
                                  final selProducts = printItems
                                      .where((p) => selected[p.id] == true)
                                      .toList();
                                  await _printAllBarcodesWithQty(
                                    selProducts,
                                    qtys,
                                    labelW: w,
                                    labelH: h,
                                    labelsPerRow: perRow,
                                    printerName: printer,
                                  );
                                },
                          icon: const Icon(Icons.print_rounded, size: 15),
                          label: Text(
                            'Print $total Label${total != 1 ? 's' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniNumField(
    TextEditingController ctrl,
    String suffix,
    double width,
  ) => Container(
    width: width,
    height: 30,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            ),
          ),
        ),
        if (suffix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(
              suffix,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _printAllBarcodesWithQty(
    List<Product> products,
    Map<String, int> qtys, {
    double labelW = 58,
    double labelH = 30,
    int labelsPerRow = 1,
    String? printerName,
  }) async {
    if (products.isEmpty) return;

    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final doc = pw.Document();
    // labelW x labelH = ONE sticker; page = perRow stickers + gaps + side margins
    const gapMm = 0.5;
    const marginMm = 2.0;
    final gap = gapMm * PdfPageFormat.mm;
    final margin = marginMm * PdfPageFormat.mm;
    final cellW = labelW * PdfPageFormat.mm;
    final cellH = labelH * PdfPageFormat.mm;
    final pageW = margin * 2 + labelsPerRow * cellW + (labelsPerRow - 1) * gap;
    final pageH = cellH;
    final pageFormat = PdfPageFormat(pageW, pageH);
    final pad = 0.5 * PdfPageFormat.mm;

    // Collect all labels across all products in order
    final allLabels = <pw.Widget>[];
    for (final p in products) {
      final count = qtys[p.id] ?? 1;
      final barcodeVal = p.barcodeNo.isNotEmpty ? p.barcodeNo : p.sku;
      String svgStr;
      try {
        svgStr = bc.Barcode.ean13().toSvg(
          barcodeVal,
          width: 200,
          height: 80,
          drawText: false,
        );
      } catch (_) {
        svgStr = bc.Barcode.code128().toSvg(
          barcodeVal,
          width: 200,
          height: 80,
          drawText: false,
        );
      }
      final innerPad = 5.0 * PdfPageFormat.mm;
      pw.Widget labelCell() => pw.Container(
        width: cellW,
        height: cellH,
        padding: pw.EdgeInsets.symmetric(
          horizontal: innerPad,
          vertical: 1.5 * PdfPageFormat.mm,
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.SvgImage(
              svg: svgStr,
              width: (cellW - innerPad * 2),
              height: (cellH - 2 * PdfPageFormat.mm) * 0.58,
            ),
            ..._labelNameWidgets(p.name, bold),
            pw.Text(
              '$_currencySymbol${_finalPriceOf(p).toStringAsFixed(2)}',
              style: pw.TextStyle(font: bold, fontSize: 4.5),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
      for (int i = 0; i < count; i++) allLabels.add(labelCell());
    }

    for (int start = 0; start < allLabels.length; start += labelsPerRow) {
      final rowCells = allLabels.sublist(
        start,
        (start + labelsPerRow).clamp(0, allLabels.length),
      );
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: margin),
          build: (_) {
            final cells = <pw.Widget>[];
            for (int i = 0; i < rowCells.length; i++) {
              if (i > 0) cells.add(pw.SizedBox(width: gap));
              cells.add(rowCells[i]);
            }
            return pw.Row(children: cells);
          },
        ),
      );
    }

    final bytes = await doc.save();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Print Preview',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  height: 260,
                  child: PdfPreview(
                    build: (_) async => bytes,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    scrollViewDecoration: const BoxDecoration(
                      color: Color(0xFFF5F5F5),
                    ),
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final targetPrinter =
                            (printerName != null &&
                                printerName != 'System Default')
                            ? printerName
                            : null;
                        try {
                          Printer? target;
                          final printers = await Printing.listPrinters();
                          if (targetPrinter != null) {
                            for (final pr in printers) {
                              if (pr.name == targetPrinter) {
                                target = pr;
                                break;
                              }
                            }
                          }
                          if (target == null) {
                            for (final pr in printers) {
                              if (pr.isDefault) {
                                target = pr;
                                break;
                              }
                            }
                          }
                          if (target != null) {
                            bool ok;
                            if (Platform.isWindows &&
                                LabelPrinter.isTsplCompatible(target.name)) {
                              // Native TSPL: the app owns label size/gap/columns,
                              // no printer driver stock configuration needed.
                              final labels = <LabelData>[];
                              for (final p in products) {
                                final count = qtys[p.id] ?? 1;
                                for (int i = 0; i < count; i++) {
                                  labels.add(
                                    LabelData(
                                      name: p.name,
                                      sku: p.sku,
                                      price: p.price,
                                      barcode: p.barcodeNo,
                                    ),
                                  );
                                }
                              }
                              ok = LabelPrinter.printBarcodeLabels(
                                printerName: target.name,
                                labels: labels,
                                labelWmm: labelW,
                                labelHmm: labelH,
                                perRow: labelsPerRow,
                                currencySymbol: _currencySymbol,
                              );
                            } else {
                              ok = await Printing.directPrintPdf(
                                printer: target,
                                format: pageFormat,
                                onLayout: (_) async => bytes,
                              );
                            }
                            if (mounted) {
                              _showToast(
                                ok ? 'Sent to ${target.name}' : 'Print failed',
                                isError: !ok,
                              );
                            }
                          } else {
                            // No printer resolved — fall back to the system dialog
                            await Printing.layoutPdf(
                              format: pageFormat,
                              onLayout: (_) async => bytes,
                              name: 'Barcodes',
                            );
                          }
                        } catch (e) {
                          if (mounted)
                            _showToast('Print failed: $e', isError: true);
                        }
                      },
                      icon: const Icon(Icons.print_rounded, size: 15),
                      label: Text(
                        'Print',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Inventory View ───────────────────────────────────────────────────────────

  Widget _buildInventoryView() {
    final lowStock = _products.where((p) => p.stock > 0 && p.stock < 10).length;
    final outOfStock = _products.where((p) => p.stock == 0).length;

    final filtered = _products.where((p) {
      final matchCat =
          _inventoryCategoryFilter == 'All' ||
          p.category == _inventoryCategoryFilter;
      if (!matchCat) return false;
      if (_inventorySearchQuery.isEmpty) return true;
      final q = _inventorySearchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_products.length} products in catalogue',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Stats + Print Barcodes row
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statCell(
                      '${_products.length}',
                      'TOTAL',
                      AppColors.textDark,
                      first: true,
                    ),
                    _statDivider(),
                    _statCell(
                      '$lowStock',
                      'LOW STOCK',
                      const Color(0xFFF59E0B),
                    ),
                    _statDivider(),
                    _statCell(
                      '$outOfStock',
                      'OUT OF STOCK',
                      AppColors.error,
                      last: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _inventorySearchQuery = v),
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: 'Search by name, SKU or category...',
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Category chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _inventoryCategoryChip('All'),
                ..._userCategories.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _inventoryCategoryChip(cat, editable: true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Product grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                childAspectRatio: 0.82,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: filtered.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _addProductCard();
                return _inventoryCard(filtered[i - 1]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryCategoryChip(String label, {bool editable = false}) {
    final selected = _inventoryCategoryFilter == label;
    return _InventoryCatChip(
      label: label,
      selected: selected,
      editable: editable,
      onTap: () => setState(() => _inventoryCategoryFilter = label),
      onEdit: () => _showEditCategoryDialog(label),
    );
  }

  void _showEditCategoryDialog(String category) {
    final ctrl = TextEditingController(text: category);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Edit Category',
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: 'Category name',
            hintStyle: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDbService.deleteCategory(category);
              final affected = _products
                  .where((p) => p.category == category)
                  .toList();
              for (final p in affected) {
                // copyWith preserves dealerName / purchaseDate / barcodeNo —
                // reconstructing via the full constructor would silently drop
                // those (local-only) fields.
                await LocalDbService.updateProduct(p.copyWith(category: ''));
              }
              setState(() {
                _userCategories.remove(category);
                for (int i = 0; i < _products.length; i++) {
                  if (_products[i].category == category) {
                    _products[i] = _products[i].copyWith(category: '');
                  }
                }
                if (_inventoryCategoryFilter == category)
                  _inventoryCategoryFilter = 'All';
              });
              ConnectivityService.instance.syncNow();
            },
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == category) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              await LocalDbService.renameCategory(category, newName);
              final affected = _products
                  .where((p) => p.category == category)
                  .toList();
              for (final p in affected) {
                // copyWith preserves dealerName / purchaseDate / barcodeNo —
                // reconstructing via the full constructor would silently drop
                // those (local-only) fields.
                await LocalDbService.updateProduct(
                  p.copyWith(category: newName),
                );
              }
              setState(() {
                final idx = _userCategories.indexOf(category);
                if (idx != -1) _userCategories[idx] = newName;
                for (int i = 0; i < _products.length; i++) {
                  if (_products[i].category == category) {
                    _products[i] = _products[i].copyWith(category: newName);
                  }
                }
                if (_inventoryCategoryFilter == category)
                  _inventoryCategoryFilter = newName;
              });
              ConnectivityService.instance.syncNow();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Rename',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(
    String value,
    String label,
    Color color, {
    bool first = false,
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: first ? 20 : 16, right: last ? 20 : 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 24, color: AppColors.border);

  Widget _colHeader(String text) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 0.8,
    ),
  );

  Widget _addProductCard() {
    return GestureDetector(
      onTap: _showAddProductDialog,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add Product',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to add new item',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _variantPriceRangeLabel(List<ProductVariant> variants) {
    final prices = variants.map((v) => v.price).toList()..sort();
    if (prices.first == prices.last) {
      return '$_currencySymbol${prices.first.toStringAsFixed(2)}';
    }
    return '$_currencySymbol${prices.first.toStringAsFixed(0)}–${prices.last.toStringAsFixed(0)}';
  }

  Widget _inventoryCard(Product p) {
    final variants = _variantsByProduct[p.id] ?? const <ProductVariant>[];
    final hasVariants = variants.isNotEmpty;
    final displayStock = hasVariants
        ? variants.fold<int>(0, (s, v) => s + v.stock)
        : p.stock;
    final tags = p.description.isNotEmpty
        ? p.description
              .split(RegExp(r'[,\n]'))
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList()
        : <String>[];
    final (statusLabel, statusColor, statusBg) = displayStock == 0
        ? (
            'Out of Stock',
            AppColors.error,
            AppColors.error.withValues(alpha: 0.08),
          )
        : displayStock < 10
        ? (
            'Low Stock',
            const Color(0xFFF59E0B),
            const Color(0xFFF59E0B).withValues(alpha: 0.08),
          )
        : (
            'In Stock',
            AppColors.success,
            AppColors.success.withValues(alpha: 0.08),
          );
    final topRank = _topProductsToday.indexWhere((t) => t.$1 == p.name);
    final topMedal = topRank == 0
        ? '🥇'
        : topRank == 1
        ? '🥈'
        : topRank == 2
        ? '🥉'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: p.emoji.startsWith('/')
                      ? Image.file(
                          File(p.emoji),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _MediumInitialsBox(name: p.name, radius: 10),
                        )
                      : _MediumInitialsBox(name: p.name, radius: 10),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                color: Colors.white,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    height: 38,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Edit',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'stock',
                    height: 38,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Update Stock',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'barcode',
                    height: 38,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.barcode_reader,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Print Barcode',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    height: 38,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (v) async {
                  if (v == 'edit') {
                    _showEditProductDialog(p);
                  } else if (v == 'stock') {
                    _showUpdateStockDialog(p);
                  } else if (v == 'barcode') {
                    _showPrintBarcodeDialog(p);
                  } else if (v == 'delete') {
                    _confirmDeleteProduct(p);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (topMedal != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: const Color(0xFFFFD54F),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '$topMedal Top',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9E7D00),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    tags.first,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            p.sku,
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  p.category,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                hasVariants
                    ? _variantPriceRangeLabel(variants)
                    : '$_currencySymbol${p.price.toStringAsFixed(2)}',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '$displayStock pcs',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: displayStock < 10
                      ? AppColors.error
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
          if (hasVariants) ...[
            const SizedBox(height: 4),
            Text(
              '${variants.length} variant${variants.length == 1 ? '' : 's'}',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Edit / Delete Product ─────────────────────────────────────────────────────

  void _showPrintBarcodeDialog(Product p) {
    int qty = p.stock > 0 ? p.stock : 1;
    int labelsPerRow = _barcodePerRow;
    final labelWCtrl = TextEditingController(
      text: _barcodeLabelW.toStringAsFixed(
        _barcodeLabelW == _barcodeLabelW.truncateToDouble() ? 0 : 1,
      ),
    );
    final labelHCtrl = TextEditingController(
      text: _barcodeLabelH.toStringAsFixed(
        _barcodeLabelH == _barcodeLabelH.truncateToDouble() ? 0 : 1,
      ),
    );
    final qtyCtrl = TextEditingController(text: '$qty');
    final perRowCtrl = TextEditingController(text: '$labelsPerRow');
    List<String> availablePrinters = ['System Default'];
    String selectedDialogPrinter = _barcodePrinter;

    // helper for clean stepper
    Widget _stepper({
      required TextEditingController ctrl,
      required int val,
      required VoidCallback onDec,
      required VoidCallback onInc,
      required ValueChanged<String> onChange,
    }) => Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onDec,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(9),
            ),
            child: Container(
              width: 34,
              height: 38,
              alignment: Alignment.center,
              child: Icon(
                Icons.remove_rounded,
                size: 15,
                color: val > 1 ? AppColors.textDark : AppColors.textMuted,
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.border),
          SizedBox(
            width: 52,
            height: 38,
            child: Center(
              child: TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChange,
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.border),
          InkWell(
            onTap: onInc,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(9),
            ),
            child: Container(
              width: 34,
              height: 38,
              alignment: Alignment.center,
              child: const Icon(
                Icons.add_rounded,
                size: 15,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );

    Widget _field(String label, TextEditingController ctrl) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Load printers on first render so saved printer is pre-selected
          if (availablePrinters.length <= 1) {
            Printing.listPrinters()
                .then((printers) {
                  final list = <String>[
                    'System Default',
                    ...printers.map((p) => p.name),
                  ];
                  if (ctx.mounted)
                    setLocal(() {
                      availablePrinters = list;
                      if (list.contains(_barcodePrinter))
                        selectedDialogPrinter = _barcodePrinter;
                    });
                })
                .catchError((_) {});
          }
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Text(
                        'Print Barcode',
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Barcode preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Container(
                        width: 210,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Split "Name (Variant)" so the variant shows on its
                            // own line, matching the printed label.
                            ...() {
                              final mm = RegExp(r'^(.*)\s*\((.+)\)\s*$')
                                  .firstMatch(p.name);
                              final main =
                                  mm != null ? mm.group(1)!.trim() : p.name;
                              final variant = mm?.group(2)?.trim();
                              return [
                                Text(
                                  main,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (variant != null && variant.isNotEmpty)
                                  Text(
                                    variant,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black54,
                                    ),
                                  ),
                              ];
                            }(),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _BarcodePainter(
                                  p.barcodeNo.isNotEmpty ? p.barcodeNo : p.sku,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.sku,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                                letterSpacing: 1.5,
                                fontFamily: 'Courier',
                              ),
                            ),
                            Text(
                              '$_currencySymbol${_finalPriceOf(p).toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Quantity + Per Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quantity',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 5),
                            _stepper(
                              ctrl: qtyCtrl,
                              val: qty,
                              onDec: qty > 1
                                  ? () => setLocal(() {
                                      qty--;
                                      qtyCtrl.text = '$qty';
                                    })
                                  : () {},
                              onInc: () => setLocal(() {
                                qty++;
                                qtyCtrl.text = '$qty';
                              }),
                              onChange: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n > 0) setLocal(() => qty = n);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Per Row',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _stepper(
                            ctrl: perRowCtrl,
                            val: labelsPerRow,
                            onDec: labelsPerRow > 1
                                ? () => setLocal(() {
                                    labelsPerRow--;
                                    perRowCtrl.text = '$labelsPerRow';
                                  })
                                : () {},
                            onInc: () => setLocal(() {
                              labelsPerRow++;
                              perRowCtrl.text = '$labelsPerRow';
                            }),
                            onChange: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n >= 1)
                                setLocal(() => labelsPerRow = n);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Label size
                  Row(
                    children: [
                      Expanded(child: _field('Width (mm)', labelWCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _field('Height (mm)', labelHCtrl)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Printer — styled like a segmented/filled selector
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Printer',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: ButtonTheme(
                            alignedDropdown: true,
                            child: DropdownButton<String>(
                              value:
                                  availablePrinters.contains(
                                    selectedDialogPrinter,
                                  )
                                  ? selectedDialogPrinter
                                  : 'System Default',
                              isExpanded: true,
                              items: availablePrinters
                                  .map(
                                    (name) => DropdownMenuItem(
                                      value: name,
                                      child: Row(
                                        children: [
                                          Icon(
                                            name == 'System Default'
                                                ? Icons.print_outlined
                                                : Icons.print_rounded,
                                            size: 14,
                                            color: name == selectedDialogPrinter
                                                ? AppColors.primary
                                                : AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color:
                                                    name ==
                                                        selectedDialogPrinter
                                                    ? AppColors.primary
                                                    : AppColors.textDark,
                                                fontWeight:
                                                    name ==
                                                        selectedDialogPrinter
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setLocal(
                                () => selectedDialogPrinter =
                                    v ?? 'System Default',
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textDark,
                              ),
                              isDense: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              selectedItemBuilder: (ctx) => availablePrinters
                                  .map(
                                    (name) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textDark,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.textMuted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            final w = double.tryParse(labelWCtrl.text) ?? 58;
                            final h = double.tryParse(labelHCtrl.text) ?? 30;
                            final finalQty = int.tryParse(qtyCtrl.text) ?? qty;
                            final finalPerRow =
                                int.tryParse(perRowCtrl.text) ?? labelsPerRow;
                            // Persist last-used barcode settings
                            setState(() {
                              _barcodeLabelW = w;
                              _barcodeLabelH = h;
                              _barcodePerRow = finalPerRow;
                              _barcodePrinter = selectedDialogPrinter;
                            });
                            LocalDbService.saveSettings({
                              'barcode_label_w': w.toString(),
                              'barcode_label_h': h.toString(),
                              'barcode_per_row': finalPerRow.toString(),
                              'barcode_printer': selectedDialogPrinter,
                            });
                            _printBarcode(
                              p,
                              quantity: finalQty,
                              labelW: w,
                              labelH: h,
                              labelsPerRow: finalPerRow,
                              printerName: selectedDialogPrinter,
                            );
                          },
                          icon: const Icon(Icons.print_rounded, size: 15),
                          label: Text(
                            'Print ${int.tryParse(qtyCtrl.text) ?? qty} Label${(int.tryParse(qtyCtrl.text) ?? qty) > 1 ? 's' : ''}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _printBarcode(
    Product p, {
    int quantity = 1,
    double labelW = 58,
    double labelH = 30,
    int labelsPerRow = 1,
    String? printerName,
  }) async {
    final barcodeVal = p.barcodeNo.isNotEmpty ? p.barcodeNo : p.sku;
    String svgStr;
    try {
      svgStr = bc.Barcode.ean13().toSvg(
        barcodeVal,
        width: 200,
        height: 60,
        drawText: false,
      );
    } catch (_) {
      svgStr = bc.Barcode.code128().toSvg(
        barcodeVal,
        width: 200,
        height: 60,
        drawText: false,
      );
    }

    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final doc = pw.Document();
    // labelW x labelH = ONE sticker; page = perRow stickers + gaps + side margins
    const gapMm = 0.5;
    const marginMm = 2.0;
    final gap = gapMm * PdfPageFormat.mm;
    final margin = marginMm * PdfPageFormat.mm;
    final cellW = labelW * PdfPageFormat.mm;
    final cellH = labelH * PdfPageFormat.mm;
    final pageW = margin * 2 + labelsPerRow * cellW + (labelsPerRow - 1) * gap;
    final pageH = cellH;
    final pageFormat = PdfPageFormat(pageW, pageH);

    final pad = 5.0 * PdfPageFormat.mm;
    pw.Widget labelCell() => pw.Container(
      width: cellW,
      height: cellH,
      padding: pw.EdgeInsets.symmetric(
        horizontal: pad,
        vertical: 1.5 * PdfPageFormat.mm,
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SvgImage(
            svg: svgStr,
            width: cellW - pad * 2,
            height: (cellH - 2 * PdfPageFormat.mm) * 0.58,
          ),
          // Same design as the bulk Print Barcodes label: variant on its own
          // line, tax-inclusive final price.
          ..._labelNameWidgets(p.name, bold),
          pw.Text(
            '$_currencySymbol${_finalPriceOf(p).toStringAsFixed(2)}',
            style: pw.TextStyle(font: bold, fontSize: 4.5),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    int printed = 0;
    while (printed < quantity) {
      final n = ((quantity - printed) < labelsPerRow)
          ? (quantity - printed)
          : labelsPerRow;
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.symmetric(horizontal: margin),
          build: (_) {
            final cells = <pw.Widget>[];
            for (int i = 0; i < n; i++) {
              if (i > 0) cells.add(pw.SizedBox(width: gap));
              cells.add(labelCell());
            }
            return pw.Row(children: cells);
          },
        ),
      );
      printed += n;
    }

    final bytes = await doc.save();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Print Preview',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  height: 260,
                  child: PdfPreview(
                    build: (_) async => bytes,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: false,
                    allowSharing: false,
                    scrollViewDecoration: const BoxDecoration(
                      color: Color(0xFFF5F5F5),
                    ),
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        // Sheet dimensions: side margins + perRow stickers + gaps
                        const gapMm = 0.5;
                        const marginMm = 2.0;
                        final sheetW =
                            marginMm * 2 +
                            labelsPerRow * labelW +
                            (labelsPerRow - 1) * gapMm;
                        final sheetH = labelH;
                        final sheetFormat = PdfPageFormat(
                          sheetW * PdfPageFormat.mm,
                          sheetH * PdfPageFormat.mm,
                        );
                        final targetPrinter =
                            (printerName != null &&
                                printerName != 'System Default')
                            ? printerName
                            : null;
                        try {
                          Printer? target;
                          final printers = await Printing.listPrinters();
                          if (targetPrinter != null) {
                            for (final pr in printers) {
                              if (pr.name == targetPrinter) {
                                target = pr;
                                break;
                              }
                            }
                          }
                          if (target == null) {
                            for (final pr in printers) {
                              if (pr.isDefault) {
                                target = pr;
                                break;
                              }
                            }
                          }
                          if (target != null) {
                            bool ok;
                            if (Platform.isWindows &&
                                LabelPrinter.isTsplCompatible(target.name)) {
                              // Native TSPL: the app owns label size/gap/columns,
                              // no printer driver stock configuration needed.
                              ok = LabelPrinter.printBarcodeLabels(
                                printerName: target.name,
                                labels: List.filled(
                                  quantity,
                                  LabelData(
                                    name: p.name,
                                    sku: p.sku,
                                    price: p.price,
                                    barcode: p.barcodeNo,
                                  ),
                                ),
                                labelWmm: labelW,
                                labelHmm: labelH,
                                perRow: labelsPerRow,
                                currencySymbol: _currencySymbol,
                              );
                            } else {
                              ok = await Printing.directPrintPdf(
                                printer: target,
                                format: sheetFormat,
                                onLayout: (_) async => bytes,
                              );
                            }
                            if (mounted) {
                              _showToast(
                                ok ? 'Sent to ${target.name}' : 'Print failed',
                                isError: !ok,
                              );
                            }
                          } else {
                            await Printing.layoutPdf(
                              format: sheetFormat,
                              onLayout: (_) async => bytes,
                              name: 'Barcode-${p.sku}',
                            );
                          }
                        } catch (e) {
                          if (mounted)
                            _showToast('Print failed: $e', isError: true);
                        }
                      },
                      icon: const Icon(Icons.print_rounded, size: 15),
                      label: Text(
                        'Print',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerMacOSPaperSize(double wMm, double hMm) async {
    final wPt = wMm * 72.0 / 25.4;
    final hPt = hMm * 72.0 / 25.4;
    final key = 'BillCat_${wMm.round()}x${hMm.round()}';
    final displayName = '${wMm.round()} x ${hMm.round()} mm';

    // Clean up wrong entry from previous attempt, then write correct format
    // macOS custom papers use: id, name, width, height, top/bottom/left/right, custom, printer
    // Must use `defaults write` so cfprefsd picks it up immediately (PlistBuddy bypasses cache)
    await Process.run('defaults', [
      'delete',
      'com.apple.print.custompapers',
      '0',
    ]);
    await Process.run('defaults', [
      'write',
      'com.apple.print.custompapers',
      key,
      '{custom = 1; id = "$key"; name = "$displayName"; width = $wPt; height = $hPt; top = 0; bottom = 0; left = 0; right = 0; printer = "";}',
    ]);
  }

  Future<void> _printAllBarcodes(List<Product> products) async {
    if (products.isEmpty) return;

    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final doc = pw.Document();
    final lw = 58 * PdfPageFormat.mm;
    final lh = 30 * PdfPageFormat.mm;
    // Use A4 so printer receives standard paper size
    const pageFormat = PdfPageFormat.a4;
    const pageMargin = 8.0 * PdfPageFormat.mm;
    final cols = ((pageFormat.width - pageMargin * 2) / lw).floor().clamp(
      1,
      999,
    );
    final rowsPerPage = ((pageFormat.height - pageMargin * 2) / lh)
        .floor()
        .clamp(1, 999);

    final allLabels = <pw.Widget>[];
    for (final p in products) {
      final barcodeVal = p.barcodeNo.isNotEmpty ? p.barcodeNo : p.sku;
      String svgStr;
      try {
        svgStr = bc.Barcode.ean13().toSvg(
          barcodeVal,
          width: 200,
          height: 80,
          drawText: false,
        );
      } catch (_) {
        svgStr = bc.Barcode.code128().toSvg(
          barcodeVal,
          width: 200,
          height: 80,
          drawText: false,
        );
      }
      allLabels.add(
        pw.Container(
          width: lw,
          height: lh,
          padding: pw.EdgeInsets.symmetric(
            horizontal: 5 * PdfPageFormat.mm,
            vertical: 1.5 * PdfPageFormat.mm,
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.SvgImage(
                svg: svgStr,
                width: lw - 10 * PdfPageFormat.mm,
                height: 17 * PdfPageFormat.mm,
              ),
              pw.SizedBox(height: 1 * PdfPageFormat.mm),
              pw.Text(
                p.sku,
                style: pw.TextStyle(font: bold, fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                p.name,
                maxLines: 1,
                style: pw.TextStyle(font: regular, fontSize: 6),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                '$_currencySymbol${_finalPriceOf(p).toStringAsFixed(2)}',
                style: pw.TextStyle(font: bold, fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final labelsPerPage = cols * rowsPerPage;
    for (int start = 0; start < allLabels.length; start += labelsPerPage) {
      final chunk = allLabels.sublist(
        start,
        (start + labelsPerPage).clamp(0, allLabels.length),
      );
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(pageMargin),
          build: (_) {
            final rows = <pw.Widget>[];
            for (int r = 0; r * cols < chunk.length; r++) {
              final rowCells = chunk.skip(r * cols).take(cols).toList();
              rows.add(pw.Row(children: rowCells));
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: rows,
            );
          },
        ),
      );
    }

    final bytes = await doc.save();
    // Open the system print dialog with the generated sheet
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Barcodes');
  }

  void _confirmDeleteProduct(Product p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Delete "${p.name}"?',
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        content: Text(
          'This will permanently remove the product from your inventory.',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocalDbService.deleteProduct(p.id);
              ConnectivityService.instance.syncNow();
              setState(() => _products.removeWhere((x) => x.id == p.id));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline replacement for the variant dropdown while naming a new (or
  /// renaming an existing) variant — keeps the interaction in the same slot
  /// instead of throwing a modal over the form.
  Widget _inlineVariantField({
    required TextEditingController ctrl,
    required String hint,
    required VoidCallback onCancel,
    required ValueChanged<String> onSubmit,
  }) {
    void commit() {
      final t = ctrl.text.trim();
      if (t.isEmpty) {
        onCancel();
      } else {
        onSubmit(t);
      }
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accentBlue, width: 1.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              autofocus: true,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => commit(),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: AppColors.textMuted,
              ),
            ),
          ),
          GestureDetector(
            onTap: commit,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantDropdown({
    required List<ProductVariant> variants,
    required String? selectedId,
    required ValueChanged<String?> onSelect,
    required VoidCallback onAdd,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: Builder(
          builder: (context) {
            // Once a product has variants, the plain "Base product" is no
            // longer a sellable option — only the variants are shown.
            final showBase = variants.isEmpty;
            final effectiveValue = showBase
                ? (selectedId ?? '__base__')
                : (selectedId ?? variants.first.id);
            return DropdownButton<String>(
              value: effectiveValue,
              isExpanded: true,
              isDense: true,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              items: [
                DropdownMenuItem(
                  value: '__add__',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Add variant',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showBase)
                  const DropdownMenuItem(
                    value: '__base__',
                    child: Text('Base product'),
                  ),
                ...variants.map(
                  (v) => DropdownMenuItem(
                    value: v.id,
                    child: Text(v.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val == '__add__') {
                  onAdd();
                  return;
                }
                onSelect(val == '__base__' ? null : val);
              },
            );
          },
        ),
      ),
    );
  }

  /// Quick restock: add to (or set) stock without opening the full edit form.
  /// Products with variants get a row per variant, since that's where the
  /// stock actually lives.
  Future<void> _showUpdateStockDialog(Product p) async {
    final variants = await LocalDbService.getVariantsForProduct(p.id);
    if (!mounted) return;
    bool addMode = true; // true = add to stock, false = set exact
    final dealerCtrl = TextEditingController(text: p.dealerName);
    // Restocking is a fresh purchase: default to today, but keep an existing
    // date if the product already has one so a dealer-only edit doesn't move it.
    DateTime? purchaseDate = _parseDate(p.purchaseDate) ?? DateTime.now();
    final ctrls = <String, TextEditingController>{
      if (variants.isEmpty) p.id: TextEditingController(),
      for (final v in variants) v.id: TextEditingController(),
    };

    int resultFor(int current, String raw) {
      final n = int.tryParse(raw.trim());
      if (n == null) return current;
      return addMode ? (current + n).clamp(0, 1 << 30) : n.clamp(0, 1 << 30);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Stock',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dlgLabel('DEALER / SUPPLIER'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: dealerCtrl,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textDark,
                        ),
                        decoration: _dlgInputDecor('e.g. Metro Wholesale'),
                      ),
                      const SizedBox(height: 14),
                      _dlgLabel('PURCHASE DATE'),
                      const SizedBox(height: 6),
                      _dlgDateField(
                        ctx: ctx,
                        value: purchaseDate,
                        onChanged: (d) => setLocal(() => purchaseDate = d),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
                  child: Row(
                    children: [
                      for (final mode in [true, false])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setLocal(() => addMode = mode),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: addMode == mode
                                    ? AppColors.primary
                                    : AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                mode ? 'Add to stock' : 'Set exact',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: addMode == mode
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Column(
                      children: [
                        if (variants.isEmpty)
                          _stockRow(
                            label: p.name,
                            current: p.stock,
                            ctrl: ctrls[p.id]!,
                            addMode: addMode,
                            onChanged: () => setLocal(() {}),
                            resultFor: resultFor,
                          )
                        else
                          ...variants.map(
                            (v) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _stockRow(
                                label: v.label,
                                current: v.stock,
                                ctrl: ctrls[v.id]!,
                                addMode: addMode,
                                onChanged: () => setLocal(() {}),
                                resultFor: resultFor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () async {
                          final dealer = dealerCtrl.text.trim();
                          final pd = purchaseDate != null
                              ? _isoDate(purchaseDate!)
                              : '';
                          if (variants.isEmpty) {
                            final next = resultFor(p.stock, ctrls[p.id]!.text);
                            final stockChanged = next != p.stock;
                            // Only stamp the purchase date on an actual restock;
                            // a dealer-only edit must not invent a date the
                            // product never had.
                            final newPd = stockChanged ? pd : p.purchaseDate;
                            if (stockChanged ||
                                dealer != p.dealerName ||
                                newPd != p.purchaseDate) {
                              await LocalDbService.updateProduct(
                                p.copyWith(
                                  stock: next,
                                  dealerName: dealer,
                                  purchaseDate: newPd,
                                ),
                              );
                            }
                          } else {
                            var anyStockChanged = false;
                            for (final v in variants) {
                              final next = resultFor(
                                v.stock,
                                ctrls[v.id]!.text,
                              );
                              if (next != v.stock) {
                                anyStockChanged = true;
                                await LocalDbService.updateVariant(
                                  v.copyWith(stock: next),
                                );
                              }
                            }
                            // Dealer and purchase date are recorded on the
                            // parent product; only stamp the date on a real
                            // restock (some variant's stock changed).
                            final newPd = anyStockChanged ? pd : p.purchaseDate;
                            if (dealer != p.dealerName ||
                                newPd != p.purchaseDate) {
                              await LocalDbService.updateProduct(
                                p.copyWith(
                                  dealerName: dealer,
                                  purchaseDate: newPd,
                                ),
                              );
                            }
                          }
                          ConnectivityService.instance.syncNow();
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          await _loadProducts();
                          _showToast('Stock updated for ${p.name}');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Update',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    dealerCtrl.dispose();
    for (final c in ctrls.values) {
      c.dispose();
    }
  }

  Widget _stockRow({
    required String label,
    required int current,
    required TextEditingController ctrl,
    required bool addMode,
    required VoidCallback onChanged,
    required int Function(int, String) resultFor,
  }) {
    final next = resultFor(current, ctrl.text);
    final changed = ctrl.text.trim().isNotEmpty && next != current;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  changed ? 'now $current  →  $next' : 'in stock: $current',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: changed ? FontWeight.w600 : FontWeight.w400,
                    color: changed ? AppColors.success : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            height: 36,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: addMode ? '+ qty' : '$current',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.accentBlue,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditProductDialog(Product p) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: p.name);
    final skuCtrl = TextEditingController(text: p.sku);
    final priceCtrl = TextEditingController(text: p.price.toStringAsFixed(2));
    final buyingPriceCtrl = TextEditingController(
      text: p.buyingPrice > 0 ? p.buyingPrice.toStringAsFixed(2) : '',
    );
    final taxPercentCtrl = TextEditingController(
      text: p.taxPercent > 0 ? p.taxPercent.toStringAsFixed(2) : '',
    );
    final stockCtrl = TextEditingController(text: '${p.stock}');
    final dealerCtrl = TextEditingController(text: p.dealerName);
    DateTime? purchaseDate = _parseDate(p.purchaseDate);
    // Enter advances through the fields top-to-bottom, last one saves.
    final nameFocus = FocusNode();
    final skuFocus = FocusNode();
    final priceFocus = FocusNode();
    final stockFocus = FocusNode();
    final buyingFocus = FocusNode();
    final taxFocus = FocusNode();
    final dealerFocus = FocusNode();
    final dateFocus = FocusNode();
    // Arrow keys move between fields (Up/Down always; Left/Right at caret edges).
    _wireArrowNav([
      (nameFocus, nameCtrl),
      (skuFocus, skuCtrl),
      (dealerFocus, dealerCtrl),
      (dateFocus, null),
      (priceFocus, priceCtrl),
      (stockFocus, stockCtrl),
      (buyingFocus, buyingPriceCtrl),
      (taxFocus, taxPercentCtrl),
    ]);
    List<String> tags = p.description.isNotEmpty
        ? p.description
              .split(RegExp(r'[,\n]'))
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList()
        : [];
    final tagInputCtrl = TextEditingController();
    final tagFocusNode = FocusNode();
    bool isAddingTag = false;
    String emoji = p.emoji;
    String category = _userCategories.contains(p.category)
        ? p.category
        : (_userCategories..add(p.category)).last;
    final originalVariants = await LocalDbService.getVariantsForProduct(p.id);
    final originalVariantIds = originalVariants.map((v) => v.id).toSet();
    List<ProductVariant> variants = List.of(originalVariants);
    if (!mounted) return;

    // Which variant the price/stock fields currently edit (null = base product).
    // If the product already has variants, the base is no longer sellable, so
    // start editing the first variant rather than the hidden base.
    String? selectedVariantId = variants.isNotEmpty ? variants.first.id : null;
    // Inline naming state: 'new' while adding, or the id being renamed.
    String? variantNameMode;
    final variantNameCtrl = TextEditingController();
    String basePriceText = priceCtrl.text;
    String baseBuyingText = buyingPriceCtrl.text;
    String baseStockText = stockCtrl.text;

    void commitFields() {
      if (selectedVariantId == null) {
        basePriceText = priceCtrl.text;
        baseBuyingText = buyingPriceCtrl.text;
        baseStockText = stockCtrl.text;
      } else {
        final idx = variants.indexWhere((v) => v.id == selectedVariantId);
        if (idx != -1) {
          variants[idx] = variants[idx].copyWith(
            price: double.tryParse(priceCtrl.text) ?? variants[idx].price,
            buyingPrice: double.tryParse(buyingPriceCtrl.text) ?? 0.0,
            stock: int.tryParse(stockCtrl.text) ?? variants[idx].stock,
          );
        }
      }
    }

    void loadFields() {
      if (selectedVariantId == null) {
        priceCtrl.text = basePriceText;
        buyingPriceCtrl.text = baseBuyingText;
        stockCtrl.text = baseStockText;
      } else {
        final v = variants.firstWhere((x) => x.id == selectedVariantId);
        priceCtrl.text = v.price.toStringAsFixed(2);
        buyingPriceCtrl.text = v.buyingPrice > 0
            ? v.buyingPrice.toStringAsFixed(2)
            : '';
        stockCtrl.text = '${v.stock}';
      }
    }

    // Sync the price/stock fields to the initially-selected entry.
    loadFields();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> saveEdit() async {
            if (!formKey.currentState!.validate()) return;
            commitFields();
            final pendingTag = tagInputCtrl.text.trim();
            if (pendingTag.isNotEmpty && !tags.contains(pendingTag)) {
              tags.add(pendingTag);
            }
            final updated = Product(
              id: p.id,
              name: nameCtrl.text.trim(),
              price: double.tryParse(basePriceText) ?? p.price,
              buyingPrice: double.tryParse(baseBuyingText) ?? 0.0,
              taxPercent: double.tryParse(taxPercentCtrl.text) ?? 0.0,
              category: category,
              emoji: emoji,
              sku: skuCtrl.text.trim().isEmpty ? p.sku : skuCtrl.text.trim(),
              stock: int.tryParse(baseStockText) ?? p.stock,
              description: tags.join(', '),
              dealerName: dealerCtrl.text.trim(),
              purchaseDate: purchaseDate != null ? _isoDate(purchaseDate!) : '',
              barcodeNo: p.barcodeNo,
            );
            await LocalDbService.updateProduct(updated);
            final currentIds = variants.map((v) => v.id).toSet();
            for (final removedId in originalVariantIds.difference(currentIds)) {
              await LocalDbService.deleteVariant(removedId);
            }
            for (final v in variants) {
              if (originalVariantIds.contains(v.id)) {
                await LocalDbService.updateVariant(v);
              } else {
                await LocalDbService.insertVariant(v);
              }
            }
            ConnectivityService.instance.syncNow();
            if (!ctx.mounted) return;
            setState(() {
              final idx = _products.indexWhere((x) => x.id == p.id);
              if (idx != -1) _products[idx] = updated;
              _variantsByProduct[p.id] = variants;
            });
            Navigator.pop(ctx);
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Edit Product',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _dlgLabel('IMAGE'),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () async {
                                            final r = await FilePicker.platform
                                                .pickFiles(
                                                  type: FileType.image,
                                                );
                                            if (r?.files.single.path != null) {
                                              final copied =
                                                  await LocalDbService.copyImageToAppDir(
                                                    r!.files.single.path!,
                                                  );
                                              setLocal(() => emoji = copied);
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceVariant,
                                                border: Border.all(
                                                  color: AppColors.border,
                                                ),
                                              ),
                                              child: emoji.startsWith('/')
                                                  ? Image.file(
                                                      File(emoji),
                                                      fit: BoxFit.cover,
                                                      width: 64,
                                                      height: 64,
                                                      errorBuilder:
                                                          (
                                                            _,
                                                            __,
                                                            ___,
                                                          ) => const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                              color: AppColors
                                                                  .textMuted,
                                                            ),
                                                          ),
                                                    )
                                                  : Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        emoji.isNotEmpty
                                                            ? Text(
                                                                emoji,
                                                                style:
                                                                    const TextStyle(
                                                                      fontSize:
                                                                          24,
                                                                    ),
                                                              )
                                                            : Icon(
                                                                Icons
                                                                    .add_photo_alternate_outlined,
                                                                color: AppColors
                                                                    .textMuted,
                                                                size: 22,
                                                              ),
                                                        if (emoji.isEmpty) ...[
                                                          const SizedBox(
                                                            height: 3,
                                                          ),
                                                          Text(
                                                            'Photo',
                                                            style: GoogleFonts.inter(
                                                              fontSize: 9,
                                                              color: AppColors
                                                                  .textMuted,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _dlgLabel(
                                                  'PRODUCT NAME',
                                                ),
                                              ),
                                              SizedBox(
                                                width: 158,
                                                child: _dlgLabel('VARIANT'),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: nameCtrl,
                                                  focusNode: nameFocus,
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  onFieldSubmitted: (_) =>
                                                      skuFocus.requestFocus(),
                                                  validator: (v) =>
                                                      v != null &&
                                                          v.trim().isNotEmpty
                                                      ? null
                                                      : 'Required',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: AppColors.textDark,
                                                  ),
                                                  decoration: _dlgInputDecor(
                                                    'e.g. Wireless Keyboard',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              SizedBox(
                                                width: 148,
                                                child: variantNameMode != null
                                                    ? _inlineVariantField(
                                                        ctrl: variantNameCtrl,
                                                        hint:
                                                            'e.g. 128GB / Blue',
                                                        onCancel: () =>
                                                            setLocal(() {
                                                              variantNameMode =
                                                                  null;
                                                              variantNameCtrl
                                                                  .clear();
                                                            }),
                                                        onSubmit: (name) => setLocal(() {
                                                          if (variantNameMode ==
                                                              'new') {
                                                            commitFields();
                                                            final v = ProductVariant(
                                                              id: const Uuid()
                                                                  .v4(),
                                                              productId: p.id,
                                                              label: name,
                                                              price:
                                                                  double.tryParse(
                                                                    priceCtrl
                                                                        .text,
                                                                  ) ??
                                                                  p.price,
                                                              stock: 0,
                                                            );
                                                            variants.add(v);
                                                            selectedVariantId =
                                                                v.id;
                                                            loadFields();
                                                          } else {
                                                            final idx = variants
                                                                .indexWhere(
                                                                  (x) =>
                                                                      x.id ==
                                                                      variantNameMode,
                                                                );
                                                            if (idx != -1) {
                                                              variants[idx] =
                                                                  variants[idx]
                                                                      .copyWith(
                                                                        label:
                                                                            name,
                                                                      );
                                                            }
                                                          }
                                                          variantNameMode =
                                                              null;
                                                          variantNameCtrl
                                                              .clear();
                                                        }),
                                                      )
                                                    : _variantDropdown(
                                                        variants: variants,
                                                        selectedId:
                                                            selectedVariantId,
                                                        onSelect: (id) =>
                                                            setLocal(() {
                                                              commitFields();
                                                              selectedVariantId =
                                                                  id;
                                                              loadFields();
                                                            }),
                                                        onAdd: () =>
                                                            setLocal(() {
                                                              variantNameCtrl
                                                                  .clear();
                                                              variantNameMode =
                                                                  'new';
                                                            }),
                                                      ),
                                              ),
                                            ],
                                          ),
                                          if (selectedVariantId != null) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Price & stock below apply to this variant',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () => setLocal(() {
                                                    final v = variants
                                                        .firstWhere(
                                                          (x) =>
                                                              x.id ==
                                                              selectedVariantId,
                                                        );
                                                    variantNameCtrl.text =
                                                        v.label;
                                                    variantNameMode = v.id;
                                                  }),
                                                  child: Text(
                                                    'Rename',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                  onTap: () => setLocal(() {
                                                    variants.removeWhere(
                                                      (x) =>
                                                          x.id ==
                                                          selectedVariantId,
                                                    );
                                                    selectedVariantId = null;
                                                    loadFields();
                                                  }),
                                                  child: Text(
                                                    'Remove',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('SKU'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: skuCtrl,
                                            focusNode: skuFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                dealerFocus.requestFocus(),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor(
                                              'e.g. WK-00123',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('CATEGORY'),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<String>(
                                            value: category.isEmpty
                                                ? null
                                                : category,
                                            items: [
                                              ..._userCategories.map(
                                                (c) => DropdownMenuItem(
                                                  value: c,
                                                  child: Text(
                                                    c,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      color: AppColors.textDark,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: '__add__',
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.add_rounded,
                                                      size: 14,
                                                      color:
                                                          AppColors.accentBlue,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Add Category',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors
                                                            .accentBlue,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            onChanged: (v) async {
                                              if (v == '__add__') {
                                                final newCat =
                                                    await _showAddCategoryDialog(
                                                      ctx,
                                                    );
                                                if (newCat != null &&
                                                    newCat.isNotEmpty) {
                                                  if (!_userCategories.contains(
                                                    newCat,
                                                  )) {
                                                    await LocalDbService.saveCategory(
                                                      newCat,
                                                    );
                                                    ConnectivityService.instance
                                                        .syncNow();
                                                    setState(
                                                      () => _userCategories.add(
                                                        newCat,
                                                      ),
                                                    );
                                                  }
                                                  setLocal(
                                                    () => category = newCat,
                                                  );
                                                }
                                              } else if (v != null)
                                                setLocal(() => category = v);
                                            },
                                            decoration: _dlgInputDecor(
                                              'Category',
                                            ),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            dropdownColor: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _dlgLabel('DEALER / SUPPLIER'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: dealerCtrl,
                                  focusNode: dealerFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => priceFocus.requestFocus(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                  decoration: _dlgInputDecor(
                                    'e.g. Metro Wholesale',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _dlgLabel('PURCHASE DATE'),
                                const SizedBox(height: 6),
                                _dlgDateField(
                                  ctx: ctx,
                                  value: purchaseDate,
                                  focusNode: dateFocus,
                                  onChanged: (d) =>
                                      setLocal(() => purchaseDate = d),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel(
                                            'SELLING PRICE ($_currencySymbol)',
                                          ),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: priceCtrl,
                                            focusNode: priceFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                stockFocus.requestFocus(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            validator: (v) =>
                                                v != null &&
                                                    v.isNotEmpty &&
                                                    double.tryParse(v) != null
                                                ? null
                                                : 'Required',
                                            onChanged: (_) => setLocal(() {}),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0.00'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('STOCK QTY'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: stockCtrl,
                                            focusNode: stockFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                buyingFocus.requestFocus(),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            validator: (v) =>
                                                v != null && v.isNotEmpty
                                                ? null
                                                : 'Required',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel(
                                            'BUYING PRICE ($_currencySymbol)',
                                          ),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: buyingPriceCtrl,
                                            focusNode: buyingFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                taxFocus.requestFocus(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0.00'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('TAX (%)'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: taxPercentCtrl,
                                            focusNode: taxFocus,
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => saveEdit(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            onChanged: (_) => setLocal(() {}),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            // Empty = fall back to the store-wide rate
                                            decoration: _dlgInputDecor(
                                              '$_taxRateDisplay (default)',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                _finalPriceCard(
                                  priceCtrl.text,
                                  taxPercentCtrl.text,
                                ),
                                const SizedBox(height: 18),
                                _dlgLabel('TAGS'),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ...List.generate(tags.length, (i) {
                                        const tagColors = [
                                          Color(0xFF6366F1),
                                          Color(0xFF10B981),
                                          Color(0xFFF59E0B),
                                          Color(0xFFEF4444),
                                          Color(0xFF3B82F6),
                                          Color(0xFFEC4899),
                                          Color(0xFF8B5CF6),
                                          Color(0xFF14B8A6),
                                          Color(0xFFF97316),
                                        ];
                                        final c =
                                            tagColors[i % tagColors.length];
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: c.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                tags[i],
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: c,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              GestureDetector(
                                                onTap: () => setLocal(
                                                  () => tags.removeAt(i),
                                                ),
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 13,
                                                  color: c,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                      if (isAddingTag)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceVariant,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: SizedBox(
                                            width: 160,
                                            child: TextField(
                                              controller: tagInputCtrl,
                                              focusNode: tagFocusNode,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: AppColors.textDark,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Type tag…',
                                                hintStyle: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: AppColors.textMuted,
                                                ),
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onSubmitted: (v) {
                                                final t = v.trim();
                                                if (t.isNotEmpty &&
                                                    !tags.contains(t))
                                                  tags.add(t);
                                                tagInputCtrl.clear();
                                                setLocal(
                                                  () => isAddingTag = false,
                                                );
                                              },
                                            ),
                                          ),
                                        )
                                      else
                                        GestureDetector(
                                          onTap: () {
                                            setLocal(() => isAddingTag = true);
                                            Future.delayed(
                                              const Duration(milliseconds: 50),
                                              () => tagFocusNode.requestFocus(),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: AppColors.border,
                                                style: BorderStyle.solid,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.add_rounded,
                                                  size: 13,
                                                  color: AppColors.textMuted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Add tag',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: AppColors.textMuted,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: saveEdit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Save Changes',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Add Product Dialog ────────────────────────────────────────────────────────

  String _generateUniqueSku(String name, {String? excludeId}) {
    final words = name.trim().split(RegExp(r'\s+'));
    String prefix = '';
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      if (clean.isNotEmpty) {
        prefix += clean.length > 2 ? clean.substring(0, 2) : clean;
      }
      if (prefix.length >= 4) break;
    }
    if (prefix.isEmpty) prefix = 'ITEM';
    // Guarantee at least 2 chars before clamping the substring's end index,
    // e.g. a 1-letter name like "I" would otherwise ask for substring(0, 2)
    // on a 1-char string and throw a RangeError.
    if (prefix.length < 2) prefix = prefix.padRight(2, 'X');
    prefix = prefix.substring(0, prefix.length.clamp(2, 6));
    final existing = _products
        .where((p) => excludeId == null || p.id != excludeId)
        .map((p) => p.sku)
        .toSet();
    int num = 1;
    while (existing.contains('$prefix${num.toString().padLeft(2, '0')}')) {
      num++;
    }
    return '$prefix${num.toString().padLeft(2, '0')}';
  }

  void _showAddProductDialog() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final buyingPriceCtrl = TextEditingController();
    // New products inherit the store-wide tax rate from Settings by default.
    final taxPercentCtrl = TextEditingController(
      text: (double.tryParse(_taxRateDisplay) ?? 0) > 0 ? _taxRateDisplay : '',
    );
    final stockCtrl = TextEditingController();
    final dealerCtrl = TextEditingController();
    DateTime? purchaseDate = DateTime.now();
    // Enter advances through the fields top-to-bottom, last one saves.
    final nameFocus = FocusNode();
    final skuFocus = FocusNode();
    final priceFocus = FocusNode();
    final stockFocus = FocusNode();
    final buyingFocus = FocusNode();
    final taxFocus = FocusNode();
    final dealerFocus = FocusNode();
    final dateFocus = FocusNode();
    // Arrow keys move between fields (Up/Down always; Left/Right at caret edges).
    _wireArrowNav([
      (nameFocus, nameCtrl),
      (skuFocus, skuCtrl),
      (dealerFocus, dealerCtrl),
      (dateFocus, null),
      (priceFocus, priceCtrl),
      (stockFocus, stockCtrl),
      (buyingFocus, buyingPriceCtrl),
      (taxFocus, taxPercentCtrl),
    ]);
    List<String> tags = [];
    final tagInputCtrl = TextEditingController();
    final tagFocusNode = FocusNode();
    bool isAddingTag = false;
    String emoji = '';
    String category = _userCategories.isNotEmpty ? _userCategories.first : '';
    bool skuAutoMode = true;
    final pendingProductId = const Uuid().v4();
    List<ProductVariant> variants = [];

    // Which variant the price/stock fields currently edit (null = base product).
    String? selectedVariantId;
    // Inline naming state: 'new' while adding, or the id being renamed.
    String? variantNameMode;
    final variantNameCtrl = TextEditingController();
    String basePriceText = '';
    String baseBuyingText = '';
    String baseStockText = '';

    void commitFields() {
      if (selectedVariantId == null) {
        basePriceText = priceCtrl.text;
        baseBuyingText = buyingPriceCtrl.text;
        baseStockText = stockCtrl.text;
      } else {
        final idx = variants.indexWhere((v) => v.id == selectedVariantId);
        if (idx != -1) {
          variants[idx] = variants[idx].copyWith(
            price: double.tryParse(priceCtrl.text) ?? variants[idx].price,
            buyingPrice: double.tryParse(buyingPriceCtrl.text) ?? 0.0,
            stock: int.tryParse(stockCtrl.text) ?? variants[idx].stock,
          );
        }
      }
    }

    void loadFields() {
      if (selectedVariantId == null) {
        priceCtrl.text = basePriceText;
        buyingPriceCtrl.text = baseBuyingText;
        stockCtrl.text = baseStockText;
      } else {
        final v = variants.firstWhere((x) => x.id == selectedVariantId);
        priceCtrl.text = v.price > 0 ? v.price.toStringAsFixed(2) : '';
        buyingPriceCtrl.text = v.buyingPrice > 0
            ? v.buyingPrice.toStringAsFixed(2)
            : '';
        stockCtrl.text = '${v.stock}';
      }
    }

    nameCtrl.addListener(() {
      if (skuAutoMode && nameCtrl.text.isNotEmpty) {
        skuCtrl.text = _generateUniqueSku(nameCtrl.text);
      }
    });
    skuCtrl.addListener(() {
      // If user manually edits SKU, stop auto-generating
      final expected = nameCtrl.text.isNotEmpty
          ? _generateUniqueSku(nameCtrl.text)
          : '';
      if (skuCtrl.text != expected) skuAutoMode = false;
    });

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> saveNew() async {
            if (!formKey.currentState!.validate()) return;
            final sku = skuCtrl.text.trim().isEmpty
                ? _generateUniqueSku(nameCtrl.text.trim())
                : skuCtrl.text.trim().toUpperCase();
            if (_products.any((p) => p.sku == sku)) {
              _showToast('SKU "$sku" already exists', isError: true);
              return;
            }
            commitFields();
            final basePrice = double.tryParse(basePriceText);
            final baseStock = int.tryParse(baseStockText);
            if (basePrice == null || baseStock == null) {
              _showToast(
                'Enter a price and stock for the base product',
                isError: true,
              );
              setLocal(() {
                selectedVariantId = null;
                loadFields();
              });
              return;
            }
            final pendingTag = tagInputCtrl.text.trim();
            if (pendingTag.isNotEmpty && !tags.contains(pendingTag)) {
              tags.add(pendingTag);
            }
            final newProduct = Product(
              id: pendingProductId,
              name: nameCtrl.text.trim(),
              price: basePrice,
              buyingPrice: double.tryParse(baseBuyingText) ?? 0.0,
              taxPercent: double.tryParse(taxPercentCtrl.text) ?? 0.0,
              category: category,
              emoji: emoji,
              sku: sku,
              stock: baseStock,
              description: tags.join(', '),
              dealerName: dealerCtrl.text.trim(),
              purchaseDate: purchaseDate != null ? _isoDate(purchaseDate!) : '',
            );
            await LocalDbService.insertProduct(newProduct);
            for (final v in variants) {
              await LocalDbService.insertVariant(v);
            }
            ConnectivityService.instance.syncNow();
            if (!ctx.mounted) return;
            setState(() {
              _products.add(newProduct);
              if (variants.isNotEmpty) {
                _variantsByProduct[pendingProductId] = variants;
              }
            });
            Navigator.pop(ctx);
            _showToast('${newProduct.name} added to inventory');
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        border: Border(
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_box_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Add New Product',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Form
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Emoji + Name row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image picker
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _dlgLabel('IMAGE'),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () async {
                                            final r = await FilePicker.platform
                                                .pickFiles(
                                                  type: FileType.image,
                                                );
                                            if (r?.files.single.path != null) {
                                              final copied =
                                                  await LocalDbService.copyImageToAppDir(
                                                    r!.files.single.path!,
                                                  );
                                              setLocal(() => emoji = copied);
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: AppColors.surfaceVariant,
                                                border: Border.all(
                                                  color: AppColors.border,
                                                ),
                                              ),
                                              child: emoji.startsWith('/')
                                                  ? Image.file(
                                                      File(emoji),
                                                      fit: BoxFit.cover,
                                                      width: 64,
                                                      height: 64,
                                                      errorBuilder:
                                                          (
                                                            _,
                                                            __,
                                                            ___,
                                                          ) => const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                              color: AppColors
                                                                  .textMuted,
                                                            ),
                                                          ),
                                                    )
                                                  : Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .add_photo_alternate_outlined,
                                                          color: AppColors
                                                              .textMuted,
                                                          size: 22,
                                                        ),
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Text(
                                                          'Photo',
                                                          style:
                                                              GoogleFonts.inter(
                                                                fontSize: 9,
                                                                color: AppColors
                                                                    .textMuted,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    // Name
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _dlgLabel(
                                                  'PRODUCT NAME',
                                                ),
                                              ),
                                              SizedBox(
                                                width: 158,
                                                child: _dlgLabel('VARIANT'),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: nameCtrl,
                                                  focusNode: nameFocus,
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  onFieldSubmitted: (_) =>
                                                      skuFocus.requestFocus(),
                                                  validator: (v) =>
                                                      v != null &&
                                                          v.trim().isNotEmpty
                                                      ? null
                                                      : 'Required',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: AppColors.textDark,
                                                  ),
                                                  decoration: _dlgInputDecor(
                                                    'e.g. Wireless Keyboard',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              SizedBox(
                                                width: 148,
                                                child: variantNameMode != null
                                                    ? _inlineVariantField(
                                                        ctrl: variantNameCtrl,
                                                        hint:
                                                            'e.g. 128GB / Blue',
                                                        onCancel: () =>
                                                            setLocal(() {
                                                              variantNameMode =
                                                                  null;
                                                              variantNameCtrl
                                                                  .clear();
                                                            }),
                                                        onSubmit: (name) => setLocal(() {
                                                          if (variantNameMode ==
                                                              'new') {
                                                            commitFields();
                                                            final v = ProductVariant(
                                                              id: const Uuid()
                                                                  .v4(),
                                                              productId:
                                                                  pendingProductId,
                                                              label: name,
                                                              price:
                                                                  double.tryParse(
                                                                    priceCtrl
                                                                        .text,
                                                                  ) ??
                                                                  0.0,
                                                              stock: 0,
                                                            );
                                                            variants.add(v);
                                                            selectedVariantId =
                                                                v.id;
                                                            loadFields();
                                                          } else {
                                                            final idx = variants
                                                                .indexWhere(
                                                                  (x) =>
                                                                      x.id ==
                                                                      variantNameMode,
                                                                );
                                                            if (idx != -1) {
                                                              variants[idx] =
                                                                  variants[idx]
                                                                      .copyWith(
                                                                        label:
                                                                            name,
                                                                      );
                                                            }
                                                          }
                                                          variantNameMode =
                                                              null;
                                                          variantNameCtrl
                                                              .clear();
                                                        }),
                                                      )
                                                    : _variantDropdown(
                                                        variants: variants,
                                                        selectedId:
                                                            selectedVariantId,
                                                        onSelect: (id) =>
                                                            setLocal(() {
                                                              commitFields();
                                                              selectedVariantId =
                                                                  id;
                                                              loadFields();
                                                            }),
                                                        onAdd: () =>
                                                            setLocal(() {
                                                              variantNameCtrl
                                                                  .clear();
                                                              variantNameMode =
                                                                  'new';
                                                            }),
                                                      ),
                                              ),
                                            ],
                                          ),
                                          if (selectedVariantId != null) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Price & stock below apply to this variant',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () => setLocal(() {
                                                    final v = variants
                                                        .firstWhere(
                                                          (x) =>
                                                              x.id ==
                                                              selectedVariantId,
                                                        );
                                                    variantNameCtrl.text =
                                                        v.label;
                                                    variantNameMode = v.id;
                                                  }),
                                                  child: Text(
                                                    'Rename',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                  onTap: () => setLocal(() {
                                                    variants.removeWhere(
                                                      (x) =>
                                                          x.id ==
                                                          selectedVariantId,
                                                    );
                                                    selectedVariantId = null;
                                                    loadFields();
                                                  }),
                                                  child: Text(
                                                    'Remove',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // SKU + Category row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('SKU'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: skuCtrl,
                                            focusNode: skuFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                dealerFocus.requestFocus(),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor(
                                              'e.g. WK-00123',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('CATEGORY'),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<String>(
                                            value: category.isEmpty
                                                ? null
                                                : category,
                                            items: [
                                              ..._userCategories.map(
                                                (c) => DropdownMenuItem(
                                                  value: c,
                                                  child: Text(
                                                    c,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      color: AppColors.textDark,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: '__add__',
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.add_rounded,
                                                      size: 14,
                                                      color:
                                                          AppColors.accentBlue,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Add Category',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors
                                                            .accentBlue,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            onChanged: (v) async {
                                              if (v == '__add__') {
                                                final newCat =
                                                    await _showAddCategoryDialog(
                                                      ctx,
                                                    );
                                                if (newCat != null &&
                                                    newCat.isNotEmpty) {
                                                  if (!_userCategories.contains(
                                                    newCat,
                                                  )) {
                                                    await LocalDbService.saveCategory(
                                                      newCat,
                                                    );
                                                    ConnectivityService.instance
                                                        .syncNow();
                                                    setState(
                                                      () => _userCategories.add(
                                                        newCat,
                                                      ),
                                                    );
                                                  }
                                                  setLocal(
                                                    () => category = newCat,
                                                  );
                                                }
                                              } else if (v != null) {
                                                setLocal(() => category = v);
                                              }
                                            },
                                            decoration: _dlgInputDecor(
                                              'Category',
                                            ),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            dropdownColor: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _dlgLabel('DEALER / SUPPLIER'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: dealerCtrl,
                                  focusNode: dealerFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => priceFocus.requestFocus(),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                  decoration: _dlgInputDecor(
                                    'e.g. Metro Wholesale',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _dlgLabel('PURCHASE DATE'),
                                const SizedBox(height: 6),
                                _dlgDateField(
                                  ctx: ctx,
                                  value: purchaseDate,
                                  focusNode: dateFocus,
                                  onChanged: (d) =>
                                      setLocal(() => purchaseDate = d),
                                ),
                                const SizedBox(height: 16),
                                // Price + Stock row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel(
                                            'SELLING PRICE ($_currencySymbol)',
                                          ),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: priceCtrl,
                                            focusNode: priceFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                stockFocus.requestFocus(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            validator: (v) {
                                              if (v == null || v.isEmpty) {
                                                return 'Required';
                                              }
                                              if (double.tryParse(v) == null) {
                                                return 'Invalid number';
                                              }
                                              return null;
                                            },
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0.00'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('STOCK QTY'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: stockCtrl,
                                            focusNode: stockFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                buyingFocus.requestFocus(),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            validator: (v) =>
                                                v != null && v.isNotEmpty
                                                ? null
                                                : 'Required',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Buying Price + Tax row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel(
                                            'BUYING PRICE ($_currencySymbol)',
                                          ),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: buyingPriceCtrl,
                                            focusNode: buyingFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onFieldSubmitted: (_) =>
                                                taxFocus.requestFocus(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            decoration: _dlgInputDecor('0.00'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dlgLabel('TAX (%)'),
                                          const SizedBox(height: 6),
                                          TextFormField(
                                            controller: taxPercentCtrl,
                                            focusNode: taxFocus,
                                            textInputAction:
                                                TextInputAction.done,
                                            onFieldSubmitted: (_) => saveNew(),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d{0,2}'),
                                              ),
                                            ],
                                            onChanged: (_) => setLocal(() {}),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppColors.textDark,
                                            ),
                                            // Empty = fall back to the store-wide rate
                                            decoration: _dlgInputDecor(
                                              '$_taxRateDisplay (default)',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                _finalPriceCard(
                                  priceCtrl.text,
                                  taxPercentCtrl.text,
                                ),
                                const SizedBox(height: 18),
                                _dlgLabel('TAGS'),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ...List.generate(tags.length, (i) {
                                        const tagColors = [
                                          Color(0xFF6366F1),
                                          Color(0xFF10B981),
                                          Color(0xFFF59E0B),
                                          Color(0xFFEF4444),
                                          Color(0xFF3B82F6),
                                          Color(0xFFEC4899),
                                          Color(0xFF8B5CF6),
                                          Color(0xFF14B8A6),
                                          Color(0xFFF97316),
                                        ];
                                        final c =
                                            tagColors[i % tagColors.length];
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: c.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                tags[i],
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: c,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              GestureDetector(
                                                onTap: () => setLocal(
                                                  () => tags.removeAt(i),
                                                ),
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 13,
                                                  color: c,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                      if (isAddingTag)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceVariant,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          child: SizedBox(
                                            width: 160,
                                            child: TextField(
                                              controller: tagInputCtrl,
                                              focusNode: tagFocusNode,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: AppColors.textDark,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Type tag…',
                                                hintStyle: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: AppColors.textMuted,
                                                ),
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onSubmitted: (v) {
                                                final t = v.trim();
                                                if (t.isNotEmpty &&
                                                    !tags.contains(t))
                                                  tags.add(t);
                                                tagInputCtrl.clear();
                                                setLocal(
                                                  () => isAddingTag = false,
                                                );
                                              },
                                            ),
                                          ),
                                        )
                                      else
                                        GestureDetector(
                                          onTap: () {
                                            setLocal(() => isAddingTag = true);
                                            Future.delayed(
                                              const Duration(milliseconds: 50),
                                              () => tagFocusNode.requestFocus(),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: AppColors.border,
                                                style: BorderStyle.solid,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.add_rounded,
                                                  size: 13,
                                                  color: AppColors.textMuted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Add tag',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: AppColors.textMuted,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Actions
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: saveNew,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Add Product',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickEmoji(BuildContext ctx, String current) async {
    const emojis = [
      '📦',
      '💻',
      '🖥️',
      '🖱️',
      '⌨️',
      '🎧',
      '🎮',
      '📷',
      '💾',
      '🧠',
      '🔌',
      '�—�️',
      '⚡',
      '📱',
      '🖨️',
      '📡',
      '🔋',
      '💿',
      '📺',
      '🎙️',
      '�•�️',
      '🔦',
      '🖊️',
      '📋',
      '�—�️',
      '🧲',
      '🔧',
      '🔩',
      '⚙️',
      '🛒',
    ];
    return showDialog<String>(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Pick an Emoji',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: emojis.map((e) {
                    final selected = e == current;
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, e),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(color: AppColors.primary, width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showAddCategoryDialog(BuildContext ctx) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'New Category',
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: 'e.g. Electronics',
            hintStyle: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dlgLabel(String text) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 1,
    ),
  );

  InputDecoration _dlgInputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
    filled: true,
    fillColor: AppColors.surfaceVariant,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.error),
    ),
  );

  /// Parses an ISO `yyyy-MM-dd` purchase-date string; null when empty/invalid.
  static DateTime? _parseDate(String iso) =>
      iso.trim().isEmpty ? null : DateTime.tryParse(iso.trim());

  /// ISO `yyyy-MM-dd` for a [DateTime] (the on-disk purchase-date format).
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Human date, e.g. `21 Jul 2026`.
  static String _fmtDMY(DateTime d) =>
      '${d.day} ${_monthName(d.month)} ${d.year}';

  /// Formats a stored ISO purchase-date string for display; '' when unset.
  static String _fmtPurchaseDate(String iso) {
    final d = _parseDate(iso);
    return d == null ? '' : _fmtDMY(d);
  }

  static bool _caretAtStart(TextEditingController? c) {
    if (c == null) return true; // non-text field (date picker): free to jump
    final s = c.selection;
    if (!s.isValid || s.baseOffset < 0) return true;
    return s.isCollapsed && s.baseOffset <= 0;
  }

  static bool _caretAtEnd(TextEditingController? c) {
    if (c == null) return true;
    final s = c.selection;
    if (!s.isValid || s.baseOffset < 0) return true;
    return s.isCollapsed && s.baseOffset >= c.text.length;
  }

  /// Lets the user move between the given form fields with the arrow keys.
  /// Up/Down always jump to the previous/next field; Left/Right move the text
  /// caret as usual and only jump once the caret reaches the field's start/end,
  /// so in-field editing still works. Pass null for the controller of a
  /// non-text field (e.g. the date picker) so Left/Right jump freely there.
  void _wireArrowNav(List<(FocusNode, TextEditingController?)> fields) {
    for (var i = 0; i < fields.length; i++) {
      final node = fields[i].$1;
      final ctrl = fields[i].$2;
      final prev = i > 0 ? fields[i - 1].$1 : null;
      final next = i < fields.length - 1 ? fields[i + 1].$1 : null;
      node.onKeyEvent = (n, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown && next != null) {
          next.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && prev != null) {
          prev.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight &&
            next != null &&
            _caretAtEnd(ctrl)) {
          next.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft &&
            prev != null &&
            _caretAtStart(ctrl)) {
          prev.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
  }

  /// A tappable field that opens a date picker, used for purchase dates in the
  /// add / edit / restock product dialogs. [onChanged] fires with the picked
  /// date, or null when the user clears it.
  Widget _dlgDateField({
    required BuildContext ctx,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    FocusNode? focusNode,
  }) {
    return InkWell(
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final firstDate = DateTime(2015);
        final lastDate = DateTime(now.year + 1, 12, 31);
        // Clamp into range: a stored date outside [firstDate, lastDate] (e.g.
        // from a previously wrong system clock) would otherwise trip
        // showDatePicker's assertion / open a broken, unselectable picker.
        var initial = value ?? now;
        if (initial.isBefore(firstDate)) initial = firstDate;
        if (initial.isAfter(lastDate)) initial = lastDate;
        final picked = await showDatePicker(
          context: ctx,
          initialDate: initial,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: _dlgInputDecor(''),
        child: Row(
          children: [
            const Icon(
              Icons.event_outlined,
              size: 16,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? _fmtDMY(value) : 'Select purchase date',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: value != null
                      ? AppColors.textDark
                      : AppColors.textMuted,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _monthName(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];

  String _fmtShort(double v) {
    if (v >= 1000000)
      return '$_currencySymbol${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '$_currencySymbol${(v / 1000).toStringAsFixed(1)}K';
    return '$_currencySymbol${v.toStringAsFixed(0)}';
  }

  Widget _buildBarChart(List<(String, double)> bars) =>
      _PremiumBarChart(bars: bars, currencySymbol: _currencySymbol);

  // ── Dashboard View ───────────────────────────────────────────────────────────

  Widget _buildDashboardView() {
    // Active period data
    final pSales = switch (_dashPeriod) {
      'This Week' => _dashWeekSales,
      'This Month' => _dashMonthSales,
      'This Year' => _dashYearSales,
      _ => _dashSales,
    };
    final pTx = switch (_dashPeriod) {
      'This Week' => _dashWeekTxCount,
      'This Month' => _dashMonthTxCount,
      'This Year' => _dashYearTxCount,
      _ => _dashTxCount,
    };
    final pItems = switch (_dashPeriod) {
      'This Week' => _dashWeekItems,
      'This Month' => _dashMonthItems,
      'This Year' => _dashYearItems,
      _ => _dashItemsSold,
    };
    final pAvg = switch (_dashPeriod) {
      'This Week' => _dashWeekAvg,
      'This Month' => _dashMonthAvg,
      'This Year' => _dashYearAvg,
      _ => _dashAvgOrder,
    };
    final pBars = switch (_dashPeriod) {
      'This Week' => _chartBarsWeek,
      'This Month' => _chartBarsMonth,
      'This Year' => _chartBarsYear,
      _ => _chartBarsToday,
    };
    final _dow = [
      '',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][DateTime.now().weekday];
    String _pctVs(double current, double prev, String label) {
      if (prev == 0) return 'No data last $label';
      final pct = ((current - prev) / prev * 100).round();
      return '${pct >= 0 ? '+' : ''}$pct% vs last $label';
    }

    final pVsLabel = switch (_dashPeriod) {
      'This Week' => 'Mon – today',
      'This Month' =>
        '1–${DateTime.now().day} ${_monthName(DateTime.now().month)}',
      'This Year' =>
        'Jan–${_monthName(DateTime.now().month)} ${DateTime.now().year}',
      _ =>
        _dashYestSales > 0
            ? '${_dashSales >= _dashYestSales ? '+' : ''}${((_dashSales - _dashYestSales) / _dashYestSales * 100).round()}% vs yesterday'
            : _pctVs(_dashSales, _dashLastWeekSameDaySales, _dow),
    };
    final pTopProducts = switch (_dashPeriod) {
      'This Week' => _topProductsWeek,
      'This Month' => _topProductsMonth,
      'This Year' => _topProductsYear,
      _ => _topProductsToday,
    };

    final maxCat = _dashCategories.isEmpty
        ? 1.0
        : _dashCategories.map((e) => e.$2).reduce((a, b) => a > b ? a : b);

    const periods = ['Today', 'This Week', 'This Month', 'This Year'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    _fmtDate(DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Period dropdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _dashPeriod,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
                    isDense: true,
                    onChanged: (v) {
                      if (v != null) setState(() => _dashPeriod = v);
                    },
                    items: periods
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Metric cards ──
          Row(
            children: [
              _metricCard(
                'Total Sales',
                '$_currencySymbol${pSales.toStringAsFixed(2)}',
                Icons.attach_money_rounded,
                AppColors.accent,
                pVsLabel,
                currencyIcon: _currencySymbol,
              ),
              const SizedBox(width: 16),
              _metricCard(
                'Transactions',
                '$pTx',
                Icons.receipt_long_rounded,
                AppColors.accentBlue,
                '$_dashPeriod',
              ),
              const SizedBox(width: 16),
              _metricCard(
                'Items Sold',
                '$pItems',
                Icons.shopping_bag_outlined,
                const Color(0xFF10B981),
                '$_dashPeriod',
              ),
              const SizedBox(width: 16),
              _metricCard(
                'Avg Order',
                '$_currencySymbol${pAvg.toStringAsFixed(2)}',
                Icons.trending_up_rounded,
                const Color(0xFF8B5CF6),
                '$_dashPeriod',
                currencyIcon: _currencySymbol,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Sales Chart ──
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Sales Overview',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _dashPeriod,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$_currencySymbol${pSales.toStringAsFixed(2)} total  •  $pTx transactions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                _buildBarChart(pBars),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Sold Products ──
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Top Products',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _dashPeriod,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Best sellers by qty',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (pTopProducts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No sales $_dashPeriod',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        ...pTopProducts.asMap().entries.map((e) {
                          final rank = e.key + 1;
                          final p = e.value;
                          final medalColor = rank == 1
                              ? const Color(0xFFFFB800)
                              : rank == 2
                              ? const Color(0xFF9E9E9E)
                              : rank == 3
                              ? const Color(0xFFCD7F32)
                              : AppColors.textMuted;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: medalColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$rank',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: medalColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.$1,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textDark,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${p.$2} units sold',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$_currencySymbol${_fmtShort(p.$3).replaceAll(_currencySymbol, '')}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales by Category',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        'Revenue breakdown today',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_dashCategories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No sales today yet',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._dashCategories.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.$1,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$_currencySymbol${c.$2.toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: c.$2 / maxCat,
                                    minHeight: 6,
                                    backgroundColor: AppColors.surfaceVariant,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      c.$3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Recent Transactions',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() {
                              _selectedTab = 3;
                              _reportView = 'Sales';
                            }),
                            child: Text(
                              'View all →',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.accentBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Last ${_dashRecentTx.length} bills closed today',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_dashRecentTx.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No transactions today yet',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _dashColHeader('CUSTOMER'),
                              ),
                              Expanded(
                                flex: 2,
                                child: _dashColHeader('METHOD'),
                              ),
                              Expanded(flex: 2, child: _dashColHeader('TIME')),
                              Expanded(flex: 1, child: _dashColHeader('ITEMS')),
                              Expanded(
                                flex: 2,
                                child: _dashColHeader('AMOUNT', right: true),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: AppColors.border),
                        ..._dashRecentTx.map((tx) {
                          final name = (tx.customerName?.isNotEmpty == true)
                              ? tx.customerName!
                              : 'Walk-in';
                          final timeStr =
                              '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';
                          final method = switch (tx.paymentMethod
                              .toLowerCase()) {
                            'cash' => 'Cash',
                            'card' => 'Card',
                            'upi' => 'UPI/QR',
                            _ => tx.paymentMethod,
                          };
                          final itemCount = tx.items.fold(
                            0,
                            (s, i) => s + i.quantity,
                          );
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: const BoxDecoration(
                                              color: AppColors.surfaceVariant,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                name[0].toUpperCase(),
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              name,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: _paymentBadge(method),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        timeStr,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        '$itemCount',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '$_currencySymbol${tx.total.toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: AppColors.border),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    String sub, {
    String? currencyIcon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: currencyIcon != null
                      ? Center(
                          child: Text(
                            currencyIcon,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        )
                      : Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: sub.startsWith('+')
                        ? AppColors.accent.withValues(alpha: 0.08)
                        : sub.startsWith('-')
                        ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    sub,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: sub.startsWith('+')
                          ? AppColors.accent
                          : sub.startsWith('-')
                          ? const Color(0xFFEF4444)
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _printIconBtn(VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.print_rounded, color: Colors.white, size: 16),
    ),
  );

  Future<void> _printSalesTable(
    List<TransactionRecord> txList,
    String periodLabel,
  ) async {
    if (txList.isEmpty) return;
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final q = _salesSearchQuery.toLowerCase();
    final rows = txList.where((t) {
      if (q.isEmpty) return true;
      return (t.customerName ?? '').toLowerCase().contains(q) ||
          (t.invoiceNumber?.toLowerCase().contains(q) ?? false) ||
          t.items.any((i) => i.productName.toLowerCase().contains(q));
    }).toList();

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(
            'Transaction History – $periodLabel',
            style: pw.TextStyle(font: bold, fontSize: 16),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['DATE', 'INVOICE', 'CUSTOMER', 'PAYMENT', 'TOTAL']
                    .map(
                      (h) => pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(font: bold, fontSize: 8),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ...rows.map(
                (t) => pw.TableRow(
                  children: [
                    _pdfCell(t.createdAt.toString().substring(0, 16), regular),
                    _pdfCell(
                      '#${t.invoiceNumber ?? t.id.substring(0, 6).toUpperCase()}',
                      regular,
                    ),
                    _pdfCell(t.customerName ?? '—', regular),
                    _pdfCell(t.paymentMethod, regular),
                    _pdfCell(
                      '$_currencySymbol${t.total.toStringAsFixed(2)}',
                      bold,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'Sales-$periodLabel',
    );
  }

  Future<void> _printCustomersTable(List<Customer> customers) async {
    if (customers.isEmpty) return;
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final q = _customerSearchQuery.toLowerCase();
    final rows = customers
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              (c.phone ?? '').contains(q),
        )
        .toList();

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(
            'Customer List',
            style: pw.TextStyle(font: bold, fontSize: 16),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: ['#', 'NAME', 'PHONE', 'ADDED ON']
                    .map(
                      (h) => pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(font: bold, fontSize: 8),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ...rows.asMap().entries.map(
                (e) => pw.TableRow(
                  children: [
                    _pdfCell('${e.key + 1}', regular),
                    _pdfCell(e.value.name, regular),
                    _pdfCell(e.value.phone ?? '—', regular),
                    _pdfCell(
                      e.value.createdAt.toString().substring(0, 10),
                      regular,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) => bytes, name: 'Customers');
  }

  Future<void> _printInventoryTable(List<Product> products) async {
    if (products.isEmpty) return;
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(
            'Product Inventory',
            style: pw.TextStyle(font: bold, fontSize: 16),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children:
                    [
                          '#',
                          'PRODUCT',
                          'CATEGORY',
                          'SKU',
                          'PRICE',
                          'STOCK',
                          'VALUE',
                        ]
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(font: bold, fontSize: 8),
                            ),
                          ),
                        )
                        .toList(),
              ),
              ...products.asMap().entries.map((e) {
                final p = e.value;
                return pw.TableRow(
                  children: [
                    _pdfCell('${e.key + 1}', regular),
                    _pdfCell(p.name, regular),
                    _pdfCell(p.category, regular),
                    _pdfCell(p.sku, regular),
                    _pdfCell(
                      '$_currencySymbol${p.price.toStringAsFixed(2)}',
                      regular,
                    ),
                    _pdfCell('${p.stock}', regular),
                    _pdfCell(
                      '$_currencySymbol${(p.price * p.stock).toStringAsFixed(2)}',
                      bold,
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) => bytes, name: 'Inventory');
  }

  pw.Widget _pdfCell(String text, pw.Font font) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 9)),
  );

  Widget _dashColHeader(String text, {bool right = false}) => Text(
    text,
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 0.8,
    ),
  );

  Widget _paymentBadge(String method) {
    final (color, bg) = switch (method) {
      'Cash' => (AppColors.accent, AppColors.accent.withValues(alpha: 0.1)),
      'Card' => (
        AppColors.accentBlue,
        AppColors.accentBlue.withValues(alpha: 0.1),
      ),
      'UPI/QR' => (
        const Color(0xFF8B5CF6),
        const Color(0xFF8B5CF6).withValues(alpha: 0.1),
      ),
      _ => (AppColors.textMuted, AppColors.surfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        method,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ── Utilities View ────────────────────────────────────────────────────────────

  Widget _buildUtilitiesView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _utilitiesView,
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'May ${DateTime.now().day}, ${DateTime.now().year}',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          if (_utilitiesView == 'Delivery') _buildDeliveryView(),
        ],
      ),
    );
  }

  Widget _buildDeliveryView() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                size: 36,
                color: AppColors.accentBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Delivery',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Delivery management coming soon.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reports View ─────────────────────────────────────────────────────────────

  Future<void> _loadReportCustomers() async {
    final customers = await LocalDbService.getCustomers();
    if (mounted) setState(() => _reportCustomers = customers);
  }

  Widget _buildReportsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _reportView,
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    _fmtDate(DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_reportView == 'Sales') ...[
                _reportPeriodBtn('Today'),
                const SizedBox(width: 6),
                _reportPeriodBtn('This Week'),
                const SizedBox(width: 6),
                _reportPeriodBtn('This Month'),
              ],
            ],
          ),
          const SizedBox(height: 24),
          if (_reportView == 'Sales')
            _buildSalesReport()
          else if (_reportView == 'Customers')
            _buildCustomersReport()
          else if (_reportView == 'Dealers')
            _buildDealersReport()
          else
            _buildInventoryReport(),
        ],
      ),
    );
  }

  // ── Sales sub-view ─────────────────────────────────────────────────────────

  Widget _buildSalesReport() {
    final isToday = _reportSalesPeriod == 'Today';
    final isWeek = _reportSalesPeriod == 'This Week';

    final revenue = isToday
        ? _dashSales
        : isWeek
        ? _dashWeekSales
        : _dashMonthSales;
    final txCount = isToday
        ? _dashTxCount
        : isWeek
        ? _dashWeekTxCount
        : _dashMonthTxCount;
    final items = isToday
        ? _dashItemsSold
        : isWeek
        ? _dashWeekItems
        : _dashMonthItems;
    final profit = isToday
        ? _dashProfitToday
        : isWeek
        ? _dashProfitWeek
        : _dashProfitMonth;
    final txList = isToday
        ? _txListToday
        : isWeek
        ? _txListWeek
        : _txListMonth;
    final periodLabel = isToday
        ? 'today'
        : isWeek
        ? 'this week'
        : 'this month';

    String fmtAmt(double v) {
      final parts = v.toStringAsFixed(2).split('.');
      final intPart = parts[0];
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
        buf.write(intPart[i]);
      }
      return '$_currencySymbol$buf.${parts[1]}';
    }

    String fmtDate(DateTime dt) {
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        final m = dt.minute.toString().padLeft(2, '0');
        final ampm = dt.hour < 12 ? 'AM' : 'PM';
        return '$h:$m $ampm';
      }
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${(dt.hour % 12 == 0 ? 12 : dt.hour % 12)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
    }

    return Column(
      children: [
        Row(
          children: [
            _reportSummaryCard(
              'Total Sales',
              fmtAmt(revenue),
              Icons.attach_money_rounded,
              AppColors.accent,
              currencyIcon: _currencySymbol,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Transactions',
              '$txCount',
              Icons.receipt_long_rounded,
              AppColors.accentBlue,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Items Sold',
              '$items',
              Icons.shopping_bag_outlined,
              const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Profit',
              fmtAmt(profit),
              Icons.trending_up_rounded,
              const Color(0xFF8B5CF6),
              currencyIcon: _currencySymbol,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transaction History',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          'All transactions $periodLabel',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 240,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.search_rounded,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: TextField(
                              onChanged: (v) =>
                                  setState(() => _salesSearchQuery = v),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search invoice, customer, items...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_salesSearchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _salesSearchQuery = ''),
                              child: const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _printIconBtn(() => _printSalesTable(txList, periodLabel)),
                ],
              ),
              const SizedBox(height: 16),
              if (txList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No transactions $periodLabel',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _dashColHeader('DATE / TIME')),
                      Expanded(flex: 3, child: _dashColHeader('INVOICE')),
                      Expanded(flex: 4, child: _dashColHeader('CUSTOMER')),
                      Expanded(flex: 2, child: _dashColHeader('ITEMS')),
                      Expanded(flex: 2, child: _dashColHeader('PAYMENT')),
                      Expanded(
                        flex: 2,
                        child: _dashColHeader('TOTAL', right: true),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                ...(() {
                  final filtered = txList.where((t) {
                    if (_salesSearchQuery.isEmpty) return true;
                    final q = _salesSearchQuery.toLowerCase();
                    final inv = t.id.substring(0, 6).toUpperCase();
                    return (t.customerName?.toLowerCase().contains(q) ??
                            false) ||
                        (t.invoiceNumber?.toLowerCase().contains(q) ??
                            false) ||
                        t.items.any(
                          (i) => i.productName.toLowerCase().contains(q),
                        ) ||
                        t.paymentMethod.toLowerCase().contains(q) ||
                        inv.toLowerCase().contains(q) ||
                        '#$inv'.toLowerCase().contains(q);
                  }).toList();
                  return filtered.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final t = entry.value;
                    // Show the real invoice number (as printed on receipts);
                    // fall back to the short id for older sales without one.
                    final invoiceNo = t.invoiceNumber?.isNotEmpty == true
                        ? t.invoiceNumber!
                        : '#${t.id.substring(0, 6).toUpperCase()}';
                    // Returns carry negative quantities so they net off in
                    // totals; the count itself reads as a plain number.
                    final itemCount = t.items
                        .fold(0, (s, i) => s + i.quantity)
                        .abs();
                    final reversal = t.reversalLabel;
                    final customer = (t.customerName?.isNotEmpty == true)
                        ? t.customerName!
                        : '—';
                    final payLabel =
                        {
                          'cash': 'Cash',
                          'card': 'Card',
                          'upi': 'UPI/QR',
                          'hybrid': 'Hybrid',
                        }[t.paymentMethod] ??
                        t.paymentMethod;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => _showTransactionDetail(t),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    fmtDate(t.createdAt),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          invoiceNo,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: reversal != null
                                                ? AppColors.error
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      if (reversal != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(
                                              alpha: 0.09,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            reversal,
                                            style: GoogleFonts.inter(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.error,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    customer,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    payLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    reversal != null
                                        ? '-$_currencySymbol${t.total.abs().toStringAsFixed(2)}'
                                        : '$_currencySymbol${t.total.toStringAsFixed(2)}',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: reversal != null
                                          ? AppColors.error
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                      ],
                    );
                  });
                })(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showTransactionDetail(TransactionRecord t) {
    final payLabel =
        {
          'cash': 'Cash',
          'card': 'Card',
          'upi': 'UPI/QR',
          'hybrid': 'Hybrid',
        }[t.paymentMethod] ??
        t.paymentMethod;
    final dt = t.createdAt;
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dt.month - 1]} ${dt.year}';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final timeStr =
        '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
    final invoiceNo = t.invoiceNumber?.isNotEmpty == true
        ? t.invoiceNumber!
        : '#${t.id.substring(0, 6).toUpperCase()}';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invoiceNo,
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$dateStr · $timeStr',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        payLabel,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Customer row ─────────────────────────────────────────────
              if (t.customerName?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t.customerName!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (t.customerPhone?.isNotEmpty == true) ...[
                        const SizedBox(width: 8),
                        Text(
                          t.customerPhone!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: AppColors.border),
              // ── Items ────────────────────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Column headers
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                'Item',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                'Qty',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Price',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Amount',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                      ...t.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  item.displayName,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '�—${item.quantity}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '$_currencySymbol${item.price.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '$_currencySymbol${item.total.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Totals ───────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  children: [
                    _txDetailRow(
                      'Subtotal',
                      '$_currencySymbol${t.subtotal.toStringAsFixed(2)}',
                    ),
                    if (t.discountAmount > 0)
                      _txDetailRow(
                        'Discount',
                        '-$_currencySymbol${t.discountAmount.toStringAsFixed(2)}',
                        valueColor: Colors.green,
                      ),
                    if (t.taxAmount > 0)
                      _txDetailRow(
                        'Tax ($_taxLabel)',
                        '$_currencySymbol${t.taxAmount.toStringAsFixed(2)}',
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        Text(
                          '$_currencySymbol${t.total.toStringAsFixed(2)}',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Actions ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (c2) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: Text(
                              'Delete Transaction?',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            content: Text(
                              'This will permanently remove this transaction.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c2, false),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c2, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && ctx.mounted) {
                          Navigator.pop(ctx);
                          await _deleteTransaction(t.id);
                        }
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 22,
                      ),
                      tooltip: 'Delete',
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _printRecord(t);
                        },
                        icon: const Icon(Icons.print_outlined, size: 15),
                        label: Text(
                          'Print',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(String id) async {
    // Soft-delete locally (hidden immediately, tombstone marks it for cloud
    // removal). Refresh the UI right away so the row disappears instantly.
    await LocalDbService.deleteTransaction(id);
    _loadDashboardData();
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // .select() returns the rows actually deleted. If the cloud delete
        // removes nothing (e.g. no DELETE policy), the list is empty and we
        // must KEEP the tombstone — otherwise the row is re-pulled and the
        // deletion "comes back". syncNow retries the delete each cycle.
        final removed = await Supabase.instance.client
            .from('transactions')
            .delete()
            .eq('id', id)
            .eq('user_id', userId)
            .select('id');
        debugPrint('CLOUD DELETE: id=$id removed=${removed.length} rows');
        if (removed.isNotEmpty) {
          // Confirmed gone from the cloud — safe to drop the local tombstone.
          await LocalDbService.purgeDeletedTransaction(id);
        }
      }
    } catch (e) {
      // Offline / failed: the tombstone stays and syncNow retries the delete.
      debugPrint('CLOUD DELETE ERROR: $e');
    }
    ConnectivityService.instance.syncNow();
  }

  // ── Customer detail popup ─────────────────────────────────────────────────

  void _showCustomerDetail(Customer c) async {
    final txs = await LocalDbService.getTransactionsByCustomer(c.name, c.phone);
    if (!mounted) return;
    final totalSpent = txs.fold<double>(0, (s, t) => s + t.total);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.phone?.isNotEmpty == true ? c.phone! : 'No phone',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_currencySymbol${totalSpent.toStringAsFixed(2)}',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'lifetime spent',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Row(
                  children: [
                    _custStatChip(
                      Icons.receipt_long_outlined,
                      '${txs.length} orders',
                    ),
                    const SizedBox(width: 8),
                    _custStatChip(
                      Icons.calendar_today_outlined,
                      'Since ${_fmtDate(c.createdAt)}',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              // ── Transaction list ──────────────────────────────────────────
              if (txs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No transactions found',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: SingleChildScrollView(
                    child: Column(
                      children: txs.map((t) {
                        final dt = t.createdAt;
                        const months = [
                          'Jan',
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul',
                          'Aug',
                          'Sep',
                          'Oct',
                          'Nov',
                          'Dec',
                        ];
                        final dateStr =
                            '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
                        final timeStr =
                            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        final payLabel = t.paymentMethod == 'cash'
                            ? 'Cash'
                            : t.paymentMethod == 'card'
                            ? 'Card'
                            : t.paymentMethod == 'upi'
                            ? 'UPI'
                            : t.paymentMethod.toUpperCase();
                        return Column(
                          children: [
                            InkWell(
                              onTap: () => _showTransactionDetail(t),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$dateStr · $timeStr',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            t.items
                                                .map((i) => i.displayName)
                                                .join(', '),
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textDark,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$_currencySymbol${t.total.toStringAsFixed(2)}',
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEEF2FF),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            payLabel,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: AppColors.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.border),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              // ── Actions ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (c2) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: Text(
                              'Delete Customer?',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            content: Text(
                              'This will permanently remove ${c.name} and all their data.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c2, false),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c2, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && ctx.mounted) {
                          Navigator.pop(ctx);
                          await _deleteCustomer(c);
                        }
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 22,
                      ),
                      tooltip: 'Delete customer',
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 13,
                        ),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _custStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer(Customer c) async {
    // Soft-delete locally (hidden immediately, tombstone marks it for cloud
    // removal), same pattern as transactions.
    await LocalDbService.deleteCustomer(c.id);
    _loadReportCustomers();
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // Purge the tombstone only when the cloud confirms the row is gone;
        // otherwise it stays hidden and syncNow retries the delete.
        final removed = await Supabase.instance.client
            .from('customers')
            .delete()
            .eq('id', c.id)
            .eq('user_id', userId)
            .select('id');
        if (removed.isNotEmpty) {
          await LocalDbService.purgeDeletedCustomer(c.id);
        }
      }
    } catch (_) {
      // Offline / failed: the tombstone stays and syncNow retries the delete.
    }
    ConnectivityService.instance.syncNow();
  }

  // ── Owner / Staff access ──────────────────────────────────────────────────

  void _lockOwnerMode() {
    setState(() {
      _isOwnerMode = false;
      if (_selectedTab == 0 || _selectedTab == 3 || _selectedTab == 4)
        _selectedTab = 1;
    });
  }

  void _showOwnerPasscodeDialog() {
    if (_ownerPasscode.isEmpty) {
      _showSetPasscodeDialog(isFirstTime: true);
      return;
    }
    final enteredDigits = ValueNotifier<String>('');
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ValueListenableBuilder<String>(
        valueListenable: enteredDigits,
        builder: (ctx, entered, _) {
          if (entered.length == 4) {
            Future.microtask(() {
              if (entered == _ownerPasscode) {
                Navigator.pop(ctx);
                setState(() => _isOwnerMode = true);
              } else {
                enteredDigits.value = '';
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect passcode'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            });
          }
          return _buildPasscodeDialog(
            'Owner Access',
            'Enter 4-digit passcode',
            enteredDigits,
            ctx,
          );
        },
      ),
    );
  }

  void _showSetPasscodeDialog({bool isFirstTime = false, VoidCallback? onSet}) {
    final firstDigits = ValueNotifier<String>('');
    final secondDigits = ValueNotifier<String>('');
    bool confirming = false;
    showDialog(
      context: context,
      barrierDismissible: !isFirstTime,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final current = confirming ? secondDigits : firstDigits;
          return ValueListenableBuilder<String>(
            valueListenable: current,
            builder: (ctx, entered, _) {
              if (entered.length == 4 && !confirming) {
                Future.microtask(() => setDialogState(() => confirming = true));
              }
              if (entered.length == 4 && confirming) {
                Future.microtask(() {
                  if (firstDigits.value == secondDigits.value) {
                    _saveNewPasscode(firstDigits.value);
                    Navigator.pop(ctx);
                    if (onSet != null) {
                      onSet();
                    } else if (isFirstTime) {
                      setState(() => _isOwnerMode = true);
                    }
                  } else {
                    secondDigits.value = '';
                    firstDigits.value = '';
                    setDialogState(() => confirming = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Passcodes did not match, try again'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                });
              }
              return _buildPasscodeDialog(
                confirming ? 'Confirm Passcode' : 'Set Owner Passcode',
                confirming
                    ? 'Re-enter the same 4 digits'
                    : 'Choose a 4-digit owner passcode',
                current,
                ctx,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _saveNewPasscode(String code) async {
    setState(() => _ownerPasscode = code);
    await LocalDbService.saveSettings({'owner_passcode': code});
    ConnectivityService.instance.syncNow();
  }

  Widget _buildPasscodeDialog(
    String title,
    String subtitle,
    ValueNotifier<String> digits,
    BuildContext ctx,
  ) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      // Type the passcode instead of tapping it: the number pad stays for
      // touch tills, but a keyboard is faster on a counter PC. Safe to grab
      // the keys — the global scan handler stands down while a dialog is up.
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _passcodeKey(event, digits),
        child: SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // 4 dot indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < digits.value.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.primary : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? AppColors.primary
                            : const Color(0xFFCCCCCC),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              // Number pad
              ...[
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', '⌫'],
              ].map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map((key) {
                      if (key.isEmpty) return const SizedBox(width: 72);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: GestureDetector(
                          onTap: () {
                            if (key == '⌫') {
                              if (digits.value.isNotEmpty) {
                                digits.value = digits.value.substring(
                                  0,
                                  digits.value.length - 1,
                                );
                              }
                            } else if (digits.value.length < 4) {
                              digits.value = digits.value + key;
                            }
                          },
                          child: Container(
                            width: 64,
                            height: 56,
                            decoration: BoxDecoration(
                              color: key == '⌫'
                                  ? Colors.transparent
                                  : const Color(0xFFF5F5F7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: key == '⌫'
                                ? const Icon(
                                    Icons.backspace_outlined,
                                    size: 20,
                                    color: Color(0xFF6E6E73),
                                  )
                                : Text(
                                    key,
                                    style: GoogleFonts.manrope(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keyboard entry for the passcode dialogs: digits fill the dots, backspace
  /// clears the last one. The four-digit check runs off [digits] itself, so
  /// typing the last digit submits exactly like tapping it does.
  KeyEventResult _passcodeKey(KeyEvent event, ValueNotifier<String> digits) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (digits.value.isNotEmpty) {
        digits.value = digits.value.substring(0, digits.value.length - 1);
      }
      return KeyEventResult.handled;
    }
    // character covers the number row; the numpad reports its own keys and
    // can arrive with a null character depending on the layout.
    var typed = event.character;
    if (typed == null || typed.isEmpty) {
      final numpad = <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.numpad0: '0',
        LogicalKeyboardKey.numpad1: '1',
        LogicalKeyboardKey.numpad2: '2',
        LogicalKeyboardKey.numpad3: '3',
        LogicalKeyboardKey.numpad4: '4',
        LogicalKeyboardKey.numpad5: '5',
        LogicalKeyboardKey.numpad6: '6',
        LogicalKeyboardKey.numpad7: '7',
        LogicalKeyboardKey.numpad8: '8',
        LogicalKeyboardKey.numpad9: '9',
      };
      typed = numpad[event.logicalKey];
    }
    if (typed == null ||
        typed.length != 1 ||
        typed.codeUnitAt(0) < 0x30 ||
        typed.codeUnitAt(0) > 0x39) {
      return KeyEventResult.ignored;
    }
    if (digits.value.length < 4) digits.value = digits.value + typed;
    return KeyEventResult.handled;
  }

  Widget _txDetailRow(String label, String value, {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textDark,
              ),
            ),
          ],
        ),
      );

  // ── Customers sub-view ─────────────────────────────────────────────────────

  Widget _buildCustomersReport() {
    final total = _reportCustomers.length;
    final withPhone = _reportCustomers
        .where((c) => c.phone != null && c.phone!.isNotEmpty)
        .length;
    final now = DateTime.now();
    final newThisMonth = _reportCustomers
        .where(
          (c) => c.createdAt.year == now.year && c.createdAt.month == now.month,
        )
        .length;

    return Column(
      children: [
        Row(
          children: [
            _reportSummaryCard(
              'Total Customers',
              '$total',
              Icons.people_alt_outlined,
              AppColors.accentBlue,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'With Phone',
              '$withPhone',
              Icons.phone_outlined,
              AppColors.accent,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'New This Month',
              '$newThisMonth',
              Icons.person_add_alt_1_outlined,
              const Color(0xFF8B5CF6),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'All Customers',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          '${_reportCustomers.length} records',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 240,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.search_rounded,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: TextField(
                              onChanged: (v) =>
                                  setState(() => _customerSearchQuery = v),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search name or phone...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_customerSearchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _customerSearchQuery = ''),
                              child: const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _printIconBtn(() => _printCustomersTable(_reportCustomers)),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: _dashColHeader('#')),
                    Expanded(flex: 4, child: _dashColHeader('NAME')),
                    Expanded(flex: 3, child: _dashColHeader('PHONE')),
                    Expanded(
                      flex: 3,
                      child: _dashColHeader('ADDED ON', right: true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (_reportCustomers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No customers yet',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ...(() {
                  final filtered = _customerSearchQuery.isEmpty
                      ? _reportCustomers
                      : _reportCustomers.where((c) {
                          final q = _customerSearchQuery.toLowerCase();
                          return c.name.toLowerCase().contains(q) ||
                              (c.phone?.toLowerCase().contains(q) ?? false);
                        }).toList();
                  if (filtered.isEmpty)
                    return [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No results for "$_customerSearchQuery"',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ];
                  return filtered.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => _showCustomerDetail(c),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    '${i + 1}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    c.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    c.phone?.isNotEmpty == true
                                        ? c.phone!
                                        : '—',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        _fmtDate(c.createdAt),
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: AppColors.textMuted,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                      ],
                    );
                  }).toList();
                })(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dealers sub-view ───────────────────────────────────────────────────────

  Widget _buildDealersReport() {
    // Group products by the dealer/supplier recorded on each product.
    final byDealer = <String, List<Product>>{};
    for (final p in _products) {
      final name = p.dealerName.trim().isEmpty
          ? 'Unassigned'
          : p.dealerName.trim();
      (byDealer[name] ??= []).add(p);
    }
    final dealers = byDealer.entries.toList()
      ..sort((a, b) {
        // Keep "Unassigned" last, otherwise sort by sourced value desc.
        if (a.key == 'Unassigned') return 1;
        if (b.key == 'Unassigned') return -1;
        double val(List<Product> ps) =>
            ps.fold(0.0, (s, p) => s + p.price * p.stock);
        return val(b.value).compareTo(val(a.value));
      });

    final realDealerCount = byDealer.keys
        .where((k) => k != 'Unassigned')
        .length;
    final totalSourcedValue = _products.fold<double>(
      0,
      (s, p) => s + p.price * p.stock,
    );
    final unassigned = byDealer['Unassigned']?.length ?? 0;

    return Column(
      children: [
        Row(
          children: [
            _reportSummaryCard(
              'Dealers',
              '$realDealerCount',
              Icons.local_shipping_outlined,
              AppColors.accentBlue,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Products Sourced',
              '${_products.length - unassigned}',
              Icons.inventory_2_outlined,
              AppColors.accent,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Stock Value',
              '$_currencySymbol${totalSourcedValue.toStringAsFixed(2)}',
              Icons.attach_money_rounded,
              const Color(0xFF059669),
              currencyIcon: _currencySymbol,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Unassigned',
              '$unassigned',
              Icons.help_outline_rounded,
              const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dealers / Suppliers',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '${byDealer.length} groups',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: _dashColHeader('#')),
                    Expanded(flex: 5, child: _dashColHeader('DEALER')),
                    Expanded(flex: 2, child: _dashColHeader('PRODUCTS')),
                    Expanded(flex: 2, child: _dashColHeader('STOCK')),
                    Expanded(
                      flex: 3,
                      child: _dashColHeader('STOCK VALUE', right: true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (dealers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No products yet',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ...dealers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final name = entry.value.key;
                  final ps = entry.value.value;
                  final stock = ps.fold<int>(0, (s, p) => s + p.stock);
                  final value = ps.fold<double>(
                    0,
                    (s, p) => s + p.price * p.stock,
                  );
                  final isUnassigned = name == 'Unassigned';
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => _showDealerDetailDialog(name, ps),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '${i + 1}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color:
                                            (isUnassigned
                                                    ? AppColors.textMuted
                                                    : AppColors.accentBlue)
                                                .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        Icons.local_shipping_outlined,
                                        size: 13,
                                        color: isUnassigned
                                            ? AppColors.textMuted
                                            : AppColors.accentBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isUnassigned
                                              ? AppColors.textMuted
                                              : AppColors.textDark,
                                          fontStyle: isUnassigned
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${ps.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '$stock',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '$_currencySymbol${value.toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: AppColors.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < dealers.length - 1)
                        const Divider(height: 1, color: AppColors.border),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  // Full purchase breakdown for one dealer/supplier. Reads live from
  // [_products] each time it's built, so it reflects the latest product edits.
  void _showDealerDetailDialog(String dealerName, List<Product> _) {
    final isUnassigned = dealerName == 'Unassigned';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, _) {
          // Re-derive from live product state on every build.
          final items =
              _products.where((p) {
                final d = p.dealerName.trim();
                return isUnassigned ? d.isEmpty : d == dealerName;
              }).toList()..sort(
                (a, b) => (b.price * b.stock).compareTo(a.price * a.stock),
              );
          final totalStock = items.fold<int>(0, (s, p) => s + p.stock);
          final stockValue = items.fold<double>(
            0,
            (s, p) => s + p.price * p.stock,
          );
          final purchaseCost = items.fold<double>(
            0,
            (s, p) => s + p.buyingPrice * p.stock,
          );

          Widget stat(String label, String value) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          );

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isUnassigned ? 'Unassigned' : dealerName,
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                '${items.length} product${items.length == 1 ? '' : 's'} sourced',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w300,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 20, 18, 8),
                    child: Row(
                      children: [
                        stat('TOTAL STOCK', '$totalStock units'),
                        stat(
                          'STOCK VALUE',
                          '$_currencySymbol${stockValue.toStringAsFixed(2)}',
                        ),
                        stat(
                          'PURCHASE COST',
                          '$_currencySymbol${purchaseCost.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ),
                  // Table header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 6),
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: _dashColHeader('PRODUCT')),
                        Expanded(flex: 2, child: _dashColHeader('STOCK')),
                        Expanded(flex: 3, child: _dashColHeader('BUY')),
                        Expanded(flex: 3, child: _dashColHeader('SELL')),
                        Expanded(
                          flex: 3,
                          child: _dashColHeader('VALUE', right: true),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Flexible(
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'No products from this dealer',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: AppColors.border,
                            ),
                            itemBuilder: (_, idx) {
                              final p = items[idx];
                              final pd = _fmtPurchaseDate(p.purchaseDate);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          Text(
                                            p.sku,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                          if (pd.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.event_outlined,
                                                    size: 11,
                                                    color: AppColors.textMuted,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    'Purchased $pd',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      color:
                                                          AppColors.textMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${p.stock}',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        p.buyingPrice > 0
                                            ? '$_currencySymbol${p.buyingPrice.toStringAsFixed(2)}'
                                            : '—',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        '$_currencySymbol${p.price.toStringAsFixed(2)}',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        '$_currencySymbol${(p.price * p.stock).toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Inventory sub-view ─────────────────────────────────────────────────────

  Widget _buildInventoryReport() {
    final totalProducts = _products.length;
    final totalStock = _products.fold<int>(0, (sum, p) => sum + p.stock);
    final totalValue = _products.fold<double>(
      0,
      (sum, p) => sum + p.price * p.stock,
    );
    final lowStock = _products.where((p) => p.stock > 0 && p.stock <= 5).length;
    final outOfStock = _products.where((p) => p.stock == 0).length;

    return Column(
      children: [
        Row(
          children: [
            _reportSummaryCard(
              'Total Products',
              '$totalProducts',
              Icons.inventory_2_outlined,
              AppColors.accentBlue,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Total Stock',
              '$totalStock units',
              Icons.layers_outlined,
              AppColors.accent,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Stock Value',
              '$_currencySymbol${totalValue.toStringAsFixed(2)}',
              Icons.attach_money_rounded,
              const Color(0xFF059669),
              currencyIcon: _currencySymbol,
            ),
            const SizedBox(width: 16),
            _reportSummaryCard(
              'Low / Out',
              '$lowStock / $outOfStock',
              Icons.warning_amber_rounded,
              const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Inventory',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          '${_products.length} items',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w300,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _printIconBtn(() => _printInventoryTable(_products)),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: _dashColHeader('#')),
                    Expanded(flex: 4, child: _dashColHeader('PRODUCT')),
                    Expanded(flex: 2, child: _dashColHeader('CATEGORY')),
                    Expanded(flex: 2, child: _dashColHeader('SKU')),
                    Expanded(flex: 2, child: _dashColHeader('PRICE')),
                    Expanded(flex: 1, child: _dashColHeader('STOCK')),
                    Expanded(
                      flex: 2,
                      child: _dashColHeader('VALUE', right: true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (_products.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No products yet',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ..._products.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  final stockColor = p.stock == 0
                      ? AppColors.error
                      : p.stock <= 5
                      ? const Color(0xFFF59E0B)
                      : AppColors.accent;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${i + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: p.emoji.startsWith('/')
                                          ? Image.file(
                                              File(p.emoji),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _SmallInitialsBox(
                                                    name: p.name,
                                                  ),
                                            )
                                          : _SmallInitialsBox(name: p.name),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textDark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  p.category,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                p.sku,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$_currencySymbol${p.price.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: stockColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${p.stock}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: stockColor,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$_currencySymbol${(p.price * p.stock).toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.border),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  // ── Account sub-view ───────────────────────────────────────────────────────

  Widget _reportPeriodBtn(String label) {
    final active = _reportSalesPeriod == label;
    return GestureDetector(
      onTap: () => setState(() => _reportSalesPeriod = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _reportSummaryCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? currencyIcon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: currencyIcon != null
                  ? Center(
                      child: Text(
                        currencyIcon,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    )
                  : Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product Card ─────────────────────────────────────────────────────────────

String _productInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.isEmpty) return '?';
  if (words.length == 1)
    return words[0].substring(0, words[0].length.clamp(1, 2)).toUpperCase();
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

Color _initialsColor(String name) => const Color(0xFFF1F5F9);

Color _initialsFgColor(Color bg) => const Color(0xFF1E293B);

// Hover shadow wrapper for search bar
class _HoverShadowBox extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  const _HoverShadowBox({required this.child, this.borderRadius = 14});
  @override
  State<_HoverShadowBox> createState() => _HoverShadowBoxState();
}

class _HoverShadowBoxState extends State<_HoverShadowBox> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: widget.child,
      ),
    );
  }
}

// Hover-aware nav tab
class _NavHoverTab extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  final String label;
  const _NavHoverTab({
    required this.selected,
    required this.onTap,
    required this.label,
  });
  @override
  State<_NavHoverTab> createState() => _NavHoverTabState();
}

class _NavHoverTabState extends State<_NavHoverTab> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accentBlue.withValues(alpha: 0.1)
                : _hovered
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected
                  ? AppColors.accentBlue
                  : _hovered
                  ? AppColors.textDark
                  : AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

// Hover-aware category chip
class _CategoryChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.primary
                : _hovered
                ? const Color(0xFFEEF2FF)
                : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: widget.selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.8,
              color: widget.selected
                  ? Colors.white
                  : _hovered
                  ? AppColors.textDark
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// Hover-aware dropdown nav tab (Reports / Utilities)
class _DropdownNavHover extends StatefulWidget {
  final bool selected;
  final String label;
  const _DropdownNavHover({required this.selected, required this.label});
  @override
  State<_DropdownNavHover> createState() => _DropdownNavHoverState();
}

class _DropdownNavHoverState extends State<_DropdownNavHover> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: widget.selected
              ? AppColors.accentBlue.withValues(alpha: 0.1)
              : _hovered
              ? Colors.black.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                color: widget.selected
                    ? AppColors.accentBlue
                    : _hovered
                    ? AppColors.textDark
                    : AppColors.textMuted.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: widget.selected
                  ? AppColors.accentBlue
                  : _hovered
                  ? AppColors.textDark
                  : AppColors.textMuted.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductInitialsBox extends StatelessWidget {
  final String name;
  final double radius;
  const _ProductInitialsBox({required this.name, this.radius = 15});

  @override
  Widget build(BuildContext context) {
    final bg = _initialsColor(name);
    final fg = _initialsFgColor(bg);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Center(
        child: Text(
          name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 52,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B).withValues(alpha: 0.12),
            height: 1,
          ),
        ),
      ),
    );
  }
}

// Small (22�—22) initials used in inventory list rows.
class _SmallInitialsBox extends StatelessWidget {
  final String name;
  const _SmallInitialsBox({required this.name});

  @override
  Widget build(BuildContext context) {
    final bg = _initialsColor(name);
    final fg = _initialsFgColor(bg);
    return Container(
      color: bg,
      child: Center(
        child: Text(
          _productInitials(name),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// Medium (44�—44) initials used in the product management grid.
class _MediumInitialsBox extends StatelessWidget {
  final String name;
  final double radius;
  const _MediumInitialsBox({required this.name, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final bg = _initialsColor(name);
    final fg = _initialsFgColor(bg);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          _productInitials(name),
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final String currencySymbol;
  final List<ProductVariant> variants;
  final bool variantsExpanded;
  final VoidCallback? onVariantArrowTap;

  /// Rate actually charged for this product — its own, or the store default.
  final double effectiveTaxRate;
  final String taxLabel;
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.currencySymbol,
    this.variants = const [],
    this.variantsExpanded = false,
    this.onVariantArrowTap,
    this.effectiveTaxRate = 0,
    this.taxLabel = 'GST',
  });
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final inCart = cart.quantityInCart(widget.product.id);
    final outOfStock = (widget.product.stock - inCart) <= 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? AppColors.accentBlue : AppColors.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji / image area
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: widget.product.emoji.startsWith('/')
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                              child: Image.file(
                                File(widget.product.emoji),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _ProductInitialsBox(
                                      name: widget.product.name,
                                      radius: 15,
                                    ),
                              ),
                            )
                          : _ProductInitialsBox(
                              name: widget.product.name,
                              radius: 15,
                            ),
                    ),
                    Consumer<CartProvider>(
                      builder: (_, cart, __) {
                        final hasVariants = widget.variants.isNotEmpty;
                        final totalStock = hasVariants
                            ? widget.variants.fold<int>(
                                0,
                                (s, v) => s + v.stock,
                              )
                            : widget.product.stock;
                        final inCart = hasVariants
                            ? cart.totalQuantityInCartForProduct(
                                widget.product.id,
                              )
                            : cart.quantityInCart(widget.product.id);
                        // Plain subtraction, not clamp: clamp throws when the
                        // stored stock is negative, which would fail the whole
                        // tile's build and leave it dead to taps.
                        final left = totalStock - inCart;
                        final remaining = left < 0 ? 0 : left;
                        final outOfStock = remaining == 0;
                        return Stack(
                          children: [
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: outOfStock
                                      ? AppColors.error
                                      : AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  outOfStock
                                      ? 'OUT OF STOCK'
                                      : 'STOCK: ${remaining.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            // Add button on hover
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _hovered ? 1.0 : 0.0,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: outOfStock
                                        ? AppColors.textMuted
                                        : AppColors.accentBlue,
                                    shape: BoxShape.circle,
                                    boxShadow: outOfStock
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: AppColors.accentBlue
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            if (widget.variants.isNotEmpty)
                              Positioned(
                                left: 8,
                                bottom: 8,
                                right: 52,
                                child: Wrap(
                                  spacing: 3,
                                  runSpacing: 3,
                                  children: [
                                    ...widget.variants.take(3).map((v) {
                                      final vInCart = cart
                                          .quantityInCartForVariant(
                                            widget.product.id,
                                            v.id,
                                          );
                                      final vOut = (v.stock - vInCart) <= 0;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: vOut
                                              ? AppColors.error
                                              : AppColors.success,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          v.label,
                                          style: GoogleFonts.inter(
                                            fontSize: 8,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      );
                                    }),
                                    if (widget.variants.length > 3)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.textMuted,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '+${widget.variants.length - 3}',
                                          style: GoogleFonts.inter(
                                            fontSize: 8,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (widget.variants.isNotEmpty)
                              Positioned(
                                right: 6,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: GestureDetector(
                                    onTap: widget.onVariantArrowTap,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: widget.variantsExpanded
                                            ? AppColors.primary
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.12,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: AnimatedRotation(
                                        turns: widget.variantsExpanded
                                            ? 0.5
                                            : 0,
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 18,
                                          color: widget.variantsExpanded
                                              ? Colors.white
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Info area
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (_) {
                        final tags = widget.product.description.isNotEmpty
                            ? widget.product.description
                                  .split(RegExp(r'[,\n]'))
                                  .map((t) => t.trim())
                                  .where((t) => t.isNotEmpty)
                                  .toList()
                            : <String>[];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF6366F1,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  tags.first,
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${widget.product.sku}'.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w300,
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Price shown is the actual base price, before tax.
                    Text(
                      () {
                        if (widget.variants.isEmpty) {
                          return '${widget.currencySymbol}${widget.product.price.toStringAsFixed(2)}';
                        }
                        final prices =
                            widget.variants.map((v) => v.price).toList()
                              ..sort();
                        return prices.first == prices.last
                            ? '${widget.currencySymbol}${prices.first.toStringAsFixed(2)}'
                            : '${widget.currencySymbol}${prices.first.toStringAsFixed(0)}–${prices.last.toStringAsFixed(0)}';
                      }(),
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (widget.effectiveTaxRate > 0)
                      Text(
                        '+ ${widget.taxLabel} '
                        '${widget.effectiveTaxRate == widget.effectiveTaxRate.truncateToDouble() ? widget.effectiveTaxRate.toStringAsFixed(0) : widget.effectiveTaxRate}%',
                        style: GoogleFonts.inter(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Variant Card (slides out beside its product in the grid) ────────────────

class _VariantCard extends StatefulWidget {
  final Product product;
  final ProductVariant variant;
  final String currencySymbol;
  final VoidCallback? onCollapse;
  final double effectiveTaxRate;
  final String taxLabel;
  const _VariantCard({
    required this.product,
    required this.variant,
    required this.currencySymbol,
    this.onCollapse,
    this.effectiveTaxRate = 0,
    this.taxLabel = 'GST',
  });
  @override
  State<_VariantCard> createState() => _VariantCardState();
}

class _VariantCardState extends State<_VariantCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final inCart = cart.quantityInCartForVariant(
      widget.product.id,
      widget.variant.id,
    );
    // See _ProductCard: clamp would throw on a negative stored stock and take
    // the whole card's build down with it.
    final left = widget.variant.stock - inCart;
    final remaining = left < 0 ? 0 : left;
    final outOfStock = remaining == 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(28 * (1 - t), 0),
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: outOfStock
              ? null
              : () => context.read<CartProvider>().addVariant(
                  widget.product,
                  widget.variant,
                ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered ? AppColors.accentBlue : AppColors.border,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: widget.product.emoji.startsWith('/')
                            ? ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(15),
                                ),
                                child: Image.file(
                                  File(widget.product.emoji),
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _ProductInitialsBox(
                                        name: widget.variant.label,
                                        radius: 15,
                                      ),
                                ),
                              )
                            : _ProductInitialsBox(
                                name: widget.variant.label,
                                radius: 15,
                              ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: outOfStock
                                ? AppColors.error
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            outOfStock
                                ? 'OUT OF STOCK'
                                : 'STOCK: ${remaining.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'VARIANT',
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _hovered ? 1.0 : 0.0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: outOfStock
                                  ? AppColors.textMuted
                                  : AppColors.accentBlue,
                              shape: BoxShape.circle,
                              boxShadow: outOfStock
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: AppColors.accentBlue.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      if (widget.onCollapse != null)
                        Positioned(
                          left: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: widget.onCollapse,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.chevron_left_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.variant.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.product.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.currencySymbol}${widget.variant.price.toStringAsFixed(2)}',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (widget.effectiveTaxRate > 0)
                        Text(
                          '+ ${widget.taxLabel} '
                          '${widget.effectiveTaxRate == widget.effectiveTaxRate.truncateToDouble() ? widget.effectiveTaxRate.toStringAsFixed(0) : widget.effectiveTaxRate}%',
                          style: GoogleFonts.inter(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w300,
                            color: AppColors.textMuted.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cart Row ─────────────────────────────────────────────────────────────────

class _CartRow extends StatefulWidget {
  final CartItem item;
  final CartProvider cart;
  final String currencySymbol;
  final String taxLabel;
  const _CartRow({
    required this.item,
    required this.cart,
    required this.currencySymbol,
    this.taxLabel = 'GST',
  });
  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  bool _editing = false;
  late TextEditingController _qtyCtrl;
  final _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity}');
    _qtyFocus.addListener(() {
      if (!_qtyFocus.hasFocus && _editing) _commitEdit();
    });
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _commitEdit() {
    final v = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (v > 0) {
      widget.cart.setQuantity(widget.item.lineKey, v, stock: widget.item.stock);
    } else {
      widget.cart.removeItem(widget.item.lineKey);
    }
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) _qtyCtrl.text = '${widget.item.quantity}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SKU: ${widget.item.product.sku}'.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w300,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Qty controls
          Container(
            width: 90,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _editing ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _qtyBtn(
                  Icons.remove,
                  () => widget.cart.decrement(widget.item.lineKey),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() => _editing = true);
                    _qtyCtrl.text = '${widget.item.quantity}';
                    _qtyCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _qtyCtrl.text.length,
                    );
                    Future.microtask(() => _qtyFocus.requestFocus());
                  },
                  child: SizedBox(
                    width: 32,
                    child: _editing
                        ? TextField(
                            controller: _qtyCtrl,
                            focusNode: _qtyFocus,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _commitEdit(),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        : Text(
                            '${widget.item.quantity}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                  ),
                ),
                _qtyBtn(
                  Icons.add,
                  () => widget.cart.increment(
                    widget.item.lineKey,
                    stock: widget.item.stock,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Line total (pre-tax); tax is shown once in the summary below.
                Text(
                  '${widget.currencySymbol}${widget.item.total.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${widget.currencySymbol}${widget.item.unitPrice.toStringAsFixed(2)}/unit',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: GestureDetector(
                onTap: () => widget.cart.removeItem(widget.item.lineKey),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppColors.primary),
      ),
    );
  }
}

// ── Discount Toggle ──────────────────────────────────────────────────────────

// Settings row input. Uses a real controller (not `initialValue`) so the caret
// isn't stuck at offset 0 — with right-aligned text that made typing insert
// before the existing value instead of replacing it. Focusing selects all.
class _SettingsInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscureText;
  final String hintText;
  const _SettingsInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hintText,
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
  });
  @override
  State<_SettingsInput> createState() => _SettingsInputState();
}

class _SettingsInputState extends State<_SettingsInput> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus && _ctrl.text.isNotEmpty) {
        _ctrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _ctrl.text.length,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant _SettingsInput old) {
    super.didUpdateWidget(old);
    // Adopt external changes only while the user isn't typing in this field.
    if (widget.value != old.value &&
        !_focus.hasFocus &&
        widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      obscureText: widget.obscureText,
      style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF1D1D1F)),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: widget.hintText,
        hintStyle: GoogleFonts.inter(
          fontSize: 13.5,
          color: const Color(0xFFC7C7CC),
        ),
        isDense: true,
        contentPadding: widget.maxLines > 1
            ? const EdgeInsets.symmetric(vertical: 4)
            : EdgeInsets.zero,
      ),
      textAlign: TextAlign.right,
    );
  }
}

// Tax row in the cart summary. Renders exactly like the other summary rows;
// tapping it reveals a small field to change the rate for this bill onwards.
class _TaxSummaryRow extends StatefulWidget {
  final String label;
  final double amount;
  final String currencySymbol;
  final String rate;
  final ValueChanged<String> onRateChanged;
  const _TaxSummaryRow({
    required this.label,
    required this.amount,
    required this.currencySymbol,
    required this.rate,
    required this.onRateChanged,
  });
  @override
  State<_TaxSummaryRow> createState() => _TaxSummaryRowState();
}

class _TaxSummaryRowState extends State<_TaxSummaryRow> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.rate,
  );
  bool _editing = false;

  @override
  void didUpdateWidget(_TaxSummaryRow old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.rate != old.rate) _ctrl.text = widget.rate;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    widget.onRateChanged(_ctrl.text.trim().isEmpty ? '0' : _ctrl.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _editing
                ? null
                : () {
                    _ctrl.text = widget.rate;
                    setState(() => _editing = true);
                  },
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                if (_editing) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    height: 26,
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      style: GoogleFonts.inter(fontSize: 12),
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _apply(),
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: AppColors.accentBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _apply,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          'APPLY',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Text(
          '${widget.currencySymbol}${widget.amount.toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _DiscountToggle extends StatefulWidget {
  final CartProvider cart;
  final String currencySymbol;
  const _DiscountToggle({required this.cart, required this.currencySymbol});
  @override
  State<_DiscountToggle> createState() => _DiscountToggleState();
}

class _DiscountToggleState extends State<_DiscountToggle> {
  final _ctrl = TextEditingController();
  DiscountType _type = DiscountType.percent;
  bool _showInput = false;

  void _onTypeBtn(DiscountType type) {
    setState(() {
      if (_type == type && _showInput) {
        // tapping active type again collapses
        _showInput = false;
      } else {
        _type = type;
        _showInput = true;
      }
    });
  }

  void _apply() {
    final v = double.tryParse(_ctrl.text) ?? 0;
    widget.cart.applyDiscount(v, _type);
    setState(() => _showInput = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // %/₹ toggle
        Container(
          height: 28,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _typeBtn('%', DiscountType.percent),
              _typeBtn(widget.currencySymbol, DiscountType.fixed),
            ],
          ),
        ),
        // Animated input + apply button
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _showInput
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 52,
                      height: 28,
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        style: GoogleFonts.inter(fontSize: 12),
                        textAlign: TextAlign.center,
                        onSubmitted: (_) => _apply(),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: AppColors.accentBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _apply,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            'APPLY',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _typeBtn(String label, DiscountType type) {
    final selected = _type == type;
    return GestureDetector(
      onTap: () => _onTypeBtn(type),
      child: Container(
        width: 26,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 2,
                  ),
                ]
              : null,
          border: selected
              ? Border.all(color: AppColors.border.withValues(alpha: 0.5))
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppColors.primary
                  : AppColors.textMuted.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Premium Bar Chart ─────────────────────────────────────────────────────────

class _PremiumBarChart extends StatefulWidget {
  final List<(String, double)> bars;
  final String currencySymbol;
  const _PremiumBarChart({required this.bars, required this.currencySymbol});
  @override
  State<_PremiumBarChart> createState() => _PremiumBarChartState();
}

class _PremiumBarChartState extends State<_PremiumBarChart> {
  int? _hovered;
  static const _barH = 120.0;
  static const _tipH = 28.0;
  static const _lblH = 20.0;
  static const _yW = 44.0;

  String _fmt(double v) {
    final s = widget.currencySymbol;
    if (v >= 10000000) return '$s${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '$s${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '$s${(v / 1000).toStringAsFixed(1)}K';
    return '$s${v.toStringAsFixed(0)}';
  }

  String _fmtFull(double v) {
    final s = widget.currencySymbol;
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '$s$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    if (bars.isEmpty) {
      return SizedBox(
        height: _tipH + _barH + _lblH,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_rounded, size: 36, color: AppColors.border),
              const SizedBox(height: 8),
              Text(
                'No data for this period',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxVal = bars.fold(0.0, (m, b) => b.$2 > m ? b.$2 : m);
    final yTicks = List.generate(5, (i) => maxVal * (4 - i) / 4);

    return SizedBox(
      height: _tipH + _barH + _lblH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Y-axis labels
          SizedBox(
            width: _yW,
            child: Stack(
              children: yTicks.asMap().entries.map((e) {
                return Positioned(
                  top: _tipH + (e.key / 4) * _barH - 8,
                  right: 6,
                  child: Text(
                    e.key == 4 ? '0' : _fmt(e.value),
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              }).toList(),
            ),
          ),
          // Chart area
          Expanded(
            child: Stack(
              children: [
                // Horizontal grid lines
                ...yTicks.asMap().entries.map(
                  (e) => Positioned(
                    top: _tipH + (e.key / 4) * _barH,
                    left: 0,
                    right: 0,
                    height: e.key == 4 ? 1.5 : 1,
                    child: Container(
                      color: e.key == 4
                          ? const Color(0xFFDDDDDD)
                          : const Color(0xFFF2F2F2),
                    ),
                  ),
                ),
                // Bars + labels
                Positioned.fill(
                  child: Row(
                    children: bars.asMap().entries.map((e) {
                      final idx = e.key;
                      final label = e.value.$1;
                      final val = e.value.$2;
                      final pct = maxVal > 0 ? val / maxVal : 0.0;
                      final isHov = _hovered == idx;
                      final anyH = _hovered != null;

                      return Expanded(
                        child: MouseRegion(
                          cursor: val > 0
                              ? SystemMouseCursors.click
                              : MouseCursor.defer,
                          onEnter: (_) => setState(() => _hovered = idx),
                          onExit: (_) => setState(() => _hovered = null),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Tooltip (fixed height slot, fades in/out)
                              SizedBox(
                                height: _tipH,
                                child: AnimatedOpacity(
                                  opacity: isHov && val > 0 ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 140),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _fmtFull(val),
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Bar body
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: AnimatedContainer(
                                  duration: Duration(
                                    milliseconds: 300 + idx * 35,
                                  ),
                                  curve: Curves.easeOut,
                                  height: val > 0
                                      ? (_barH * pct).clamp(3.0, _barH)
                                      : 1.5,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: val > 0
                                          ? [
                                              isHov
                                                  ? const Color(0xFF1E3A8A)
                                                  : AppColors.primary
                                                        .withValues(
                                                          alpha: anyH
                                                              ? 0.28
                                                              : 1.0,
                                                        ),
                                              isHov
                                                  ? const Color(0xFF60A5FA)
                                                  : AppColors.primary
                                                        .withValues(
                                                          alpha: anyH
                                                              ? 0.10
                                                              : 0.42,
                                                        ),
                                            ]
                                          : [
                                              const Color(0xFFEEEEEE),
                                              const Color(0xFFEEEEEE),
                                            ],
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              // X label
                              SizedBox(
                                height: _lblH,
                                child: Center(
                                  child: Text(
                                    label,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: isHov
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isHov
                                          ? AppColors.primary
                                          : AppColors.textMuted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryCatChip extends StatefulWidget {
  final String label;
  final bool selected;
  final bool editable;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  const _InventoryCatChip({
    required this.label,
    required this.selected,
    required this.editable,
    required this.onTap,
    required this.onEdit,
  });

  @override
  State<_InventoryCatChip> createState() => _InventoryCatChipState();
}

class _InventoryCatChipState extends State<_InventoryCatChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.textDark : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: widget.selected ? AppColors.textDark : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.selected ? Colors.white : AppColors.textDark,
                  letterSpacing: 0.3,
                ),
              ),
              if (widget.editable && _hovered) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: widget.onEdit,
                  child: Icon(
                    Icons.edit_rounded,
                    size: 11,
                    color: widget.selected
                        ? Colors.white60
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  final String data;
  _BarcodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final barcode = bc.Barcode.code128();
    final elements = barcode.make(
      data,
      width: size.width,
      height: size.height,
      drawText: false,
    );
    final paint = Paint()..color = Colors.black;
    for (final el in elements) {
      if (el is bc.BarcodeBar && el.black) {
        canvas.drawRect(
          Rect.fromLTWH(el.left, el.top, el.width, el.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.data != data;
}

/// A product being handed out in an exchange, before it becomes a sale line.
/// Mutable quantity so the dialog's steppers can adjust it in place.
class _ExchangeAdd {
  _ExchangeAdd({required this.product, this.variant, this.qty = 1});

  final Product product;
  final ProductVariant? variant;
  int qty;

  String get key =>
      variant == null ? product.id : '${product.id}::${variant!.id}';

  String get name =>
      variant == null ? product.name : '${product.name} (${variant!.label})';

  double get price => variant?.price ?? product.price;

  int get stock => variant?.stock ?? product.stock;
}
