import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'i18n.dart';
import 'screens_auth.dart';
import 'screens_home.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final docs = await getApplicationDocumentsDirectory();
  imagesDir = p.join(docs.path, 'images');
  Directory(imagesDir).createSync(recursive: true);
  final st = AppState();
  await st.init();
  bumpAfter = bump;
  try {
    await Notif.init();
  } catch (_) {}
  runApp(ChangeNotifierProvider.value(value: st, child: const ReineApp()));
}

class ReineApp extends StatefulWidget {
  const ReineApp({super.key});
  @override
  State<ReineApp> createState() => _ReineAppState();
}

class _ReineAppState extends State<ReineApp> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Verrouillage automatique : après un délai en arrière-plan, l'écran de déverrouillage s'affiche.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final st = context.read<AppState>();
    if (s == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (s == AppLifecycleState.resumed && _pausedAt != null) {
      if (DateTime.now().difference(_pausedAt!).inSeconds >= AppState.lockDelay) st.lock();
      _pausedAt = null;
    }
  }

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: kViolet, secondary: kGold, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF3A0F1E) : kViolet,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: kGold, foregroundColor: Colors.black),
      // Cartes légèrement transparentes : le logo en fond reste visible.
      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: dark ? const Color(0xE62A1F24) : const Color(0xE6FFFFFF),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    Widget home;
    if (st.userId == null) {
      home = const LoginScreen();
    } else if (st.locked) {
      home = const LockScreen();
    } else {
      home = const HomeShell();
    }
    return MaterialApp(
      title: kAtelierName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: st.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );
  }
}
