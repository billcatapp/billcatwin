import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
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

void main() {
  // runZonedGuarded ensures ensureInitialized and runApp share the same zone,
  // and catches background Supabase auth errors thrown when offline.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
      if (data.event == AuthChangeEvent.signedIn && user != null) {
        await LocalDbService.initForUser(user.id);
        await LocalDbService.clearAll();
        await ConnectivityService.instance.pullFromCloud();

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
