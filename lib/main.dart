import 'package:flutter/material.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'models/edit_state.dart';
import 'models/app_settings.dart';
import 'services/prefs_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/update_service.dart';
import 'services/ads_service.dart';
import 'widgets/update_dialog.dart';
import 'widgets/model_download_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  // Uncaught async errors are logged instead of closing the app.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    return true;
  };
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final prefsService = PrefsService();
  final appSettings = AppSettings(prefsService);
  await appSettings.load();
  final onboardingDone = await prefsService.isOnboardingDone();

  runApp(BgRemoverApp(
    appSettings: appSettings,
    startAtOnboarding: !onboardingDone,
  ));
}

class BgRemoverApp extends StatelessWidget {
  final AppSettings appSettings;
  final bool startAtOnboarding;

  const BgRemoverApp({
    super.key,
    required this.appSettings,
    required this.startAtOnboarding,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appSettings),
        ChangeNotifierProvider(create: (_) => EditState()),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'BG Remover',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            supportedLocales: const [Locale('en')],
            builder: (context, child) =>
                ModelDownloadOverlay(child: child ?? const SizedBox.shrink()),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              colorSchemeSeed: Colors.deepPurple,
              appBarTheme: const AppBarTheme(centerTitle: true),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.deepPurple,
              appBarTheme: const AppBarTheme(centerTitle: true),
              brightness: Brightness.dark,
              useMaterial3: true,
            ),
            home: _AppStartupGate(
              child: startAtOnboarding
                  ? const OnboardingScreen()
                  : const HomeScreen(),
            ),
          );
        },
      ),
    );
  }
}

/// Wraps the first screen and, right after the first frame, checks the
/// remote update_config.json — showing a forced (blocking) or optional
/// update dialog on top if needed. A failed/offline check is silently
/// ignored so it never prevents the app from being used.
class _AppStartupGate extends StatefulWidget {
  final Widget child;
  const _AppStartupGate({required this.child});

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    AdsService.instance.init();
  }

  Future<void> _checkForUpdate() async {
    final result = await UpdateService().check();
    if (result == null || !mounted) return;
    await showUpdateDialogIfNeeded(context, result);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
