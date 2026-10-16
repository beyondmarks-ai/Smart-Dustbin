import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aws_waste_repository.dart';
import 'app_flow.dart';
import 'home_dashboard.dart';
import 'app_preferences.dart';

final _defaultRepository = AwsWasteRepository();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appPreferences.load();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFF7F5EE),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const SmartDustbinApp());
}

class SmartDustbinApp extends StatelessWidget {
  const SmartDustbinApp({super.key, this.repository});

  final WasteRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appPreferences,
      builder: (context, _) {
        AppColors.dark =
            appPreferences.themeMode == ThemeMode.dark ||
            (appPreferences.themeMode == ThemeMode.system &&
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                    Brightness.dark);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'EcoSort AI',
          themeMode: appPreferences.themeMode,
          darkTheme: ecoTheme(Brightness.dark),
          theme: ecoTheme(Brightness.light),
          home: repository == null
              ? EcoSortFlow(repository: _defaultRepository)
              : HomeDashboard(repository: repository),
        );
      },
    );
  }
}

ThemeData ecoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF101C16) : const Color(0xFFF7F5EE);
  final surface = dark ? const Color(0xFF1A2921) : const Color(0xFFFFFEF9);
  final border = dark ? const Color(0xFF3C5042) : const Color(0xFFE3E3DA);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    brightness: brightness,
    surface: surface,
    primary: dark ? const Color(0xFF78D69A) : AppColors.green,
  );
  return ThemeData(
    brightness: brightness,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.primaryContainer.withValues(alpha: .35),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: DividerThemeData(color: border),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
