import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'azure_waste_repository.dart';
import 'home_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(SmartDustbinApp(repository: AzureWasteRepository()));
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.green,
          surface: AppColors.card,
        ),
        fontFamily: 'Roboto',
        splashFactory: InkSparkle.splashFactory,
      ),
      home: HomeDashboard(repository: repository ?? AzureWasteRepository()),
    );
  }
}
