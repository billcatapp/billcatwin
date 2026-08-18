import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/cart_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/billing/billing_screen.dart';
import 'services/connectivity_service.dart';
import 'services/local_db_service.dart';

const _supabaseUrl = 'https://xawpxbhglzhaibmcpwho.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhhd3B4YmhnbHpoYWlibWNwd2hvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMTA4MTMsImV4cCI6MjA5MjY4NjgxM30.rin8K6vTWF_L-gCJKw1dyf0Vm2RoDvxcMSKSnClWy9E';

final _navigatorKey = GlobalKey<NavigatorState>();

/// Windows single-instance guard. Two BillCat processes sharing one SQLite
/// file is the classic cause of "database is locked" failures when closing a
/// bill (a leftover instance after an update, or the app opened twice).
/// Returns false when another instance already runs — after bringing that
/// instance's window to the front. The mutex handle is deliberately never
/// closed; Windows releases it when the process exits.
bool _acquireSingleInstanceLock() {
  if (!Platform.isWindows) return true;
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final createMutex = kernel32
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)
      >('CreateMutexW');
  final getLastError = kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  final name = 'BillCat_SingleInstance_Mutex'.toNativeUtf16();
  createMutex(nullptr, 0, name);
  final alreadyRunning = getLastError() == 183; // ERROR_ALREADY_EXISTS
  calloc.free(name);
  if (!alreadyRunning) return true;

  // Focus the running instance so the double-click still "opens" BillCat.
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindow = user32
      .lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)
      >('FindWindowW');
  final showWindow = user32
      .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
        'ShowWindow',
      );
  final setForegroundWindow = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetForegroundWindow',
      );
  final title = 'BillCat'.toNativeUtf16();
  final hwnd = findWindow(nullptr, title);
  calloc.free(title);
  if (hwnd != 0) {
    showWindow(hwnd, 9); // SW_RESTORE
    setForegroundWindow(hwnd);
  }
  return false;
}

void main() {
  // runZonedGuarded ensures ensureInitialized and runApp share the same zone,
  // and catches background Supabase auth errors thrown when offline.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // A second instance would share the SQLite file with the first and turn
    // every bill save into a "database is locked" coin flip. Hand over to
    // the running instance instead.
    if (!_acquireSingleInstanceLock()) {
      exit(0);
    }

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await LocalDbService.initForUser(currentUser.id);
    }
    await ConnectivityService.instance.init();
    if (currentUser != null) {
      // Pull cloud data, then push anything still unsynced locally so the
      // two sides re-converge even if a previous push was lost cloud-side.
      ConnectivityService.instance
          .pullFromCloud()
          .then((_) => ConnectivityService.instance.syncNow());
    }
    runApp(const BillCatApp());
  }, (error, _) {
    // Supabase fires AuthRetryableFetchException in background when offline;
    // catching here prevents it from killing the Windows process.
  });
}

class BillCatApp extends StatefulWidget {
  const BillCatApp({super.key});

  @override
  State<BillCatApp> createState() => _BillCatAppState();
}

class _BillCatAppState extends State<BillCatApp> {
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _handleIncomingLinks();
  }

  void _handleIncomingLinks() {
    _appLinks.uriLinkStream.listen((uri) {
      if (uri.fragment.contains('type=recovery') ||
          uri.queryParameters['type'] == 'recovery') {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (route) => false,
        );
      }
    });

    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      if (data.event == AuthChangeEvent.signedOut) {
        // Drop the previous user's live sync channel.
        await ConnectivityService.instance.onUserChanged();
        return;
      }
      if (data.event == AuthChangeEvent.signedIn && user != null) {
        // NOTE: no clearAll here — the DB file is per-user, and wiping it
        // would destroy offline sales and delete-tombstones that were never
        // pushed. Pull merges/reconciles instead, then push sends pending
        // work up.
        await LocalDbService.initForUser(user.id);
        await ConnectivityService.instance.pullFromCloud();
        await ConnectivityService.instance.syncNow();
        // Open the live sync channel for this user.
        await ConnectivityService.instance.onUserChanged();

        final provider = user.appMetadata['provider'] as String?;
        if (provider == 'google') {
          _navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const BillingScreen()),
            (route) => false,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: MaterialApp(
        title: 'BillCat',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1A3A5F),
          useMaterial3: true,
        ),
        // Lay the app out on a fixed-width design canvas (macOS reference
        // window: 1512 logical px) and scale to the actual window, so the
        // layout density matches across OS display scale factors.
        builder: (context, child) {
          const designWidth = 1512.0;
          final mq = MediaQuery.of(context);
          if (child == null ||
              mq.size.width <= 0 ||
              mq.size.width >= designWidth) {
            return child ?? const SizedBox.shrink();
          }
          final scale = mq.size.width / designWidth;
          final designHeight = mq.size.height / scale;
          return MediaQuery(
            data: mq.copyWith(size: Size(designWidth, designHeight)),
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: designWidth,
                height: designHeight,
                child: child,
              ),
            ),
          );
        },
        home: Supabase.instance.client.auth.currentUser != null
            ? const BillingScreen()
            : const LoginScreen(),
      ),
    );
  }
}
