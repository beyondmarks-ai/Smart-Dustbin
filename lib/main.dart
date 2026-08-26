import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aws_waste_repository.dart';
import 'home_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(SmartDustbinApp(repository: AwsWasteRepository()));
}

class SmartDustbinApp extends StatelessWidget {
  const SmartDustbinApp({super.key, this.repository});

  final WasteRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Dustbin',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.green,
          surface: AppColors.card,
          onSurface: AppColors.textPrimary,
          onPrimary: Colors.white,
        ),
        fontFamily: 'Roboto',
        splashFactory: InkSparkle.splashFactory,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textPrimary),
          bodySmall: TextStyle(color: AppColors.muted),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: HomeDashboard(repository: repository ?? AwsWasteRepository()),
    );
  }
}
