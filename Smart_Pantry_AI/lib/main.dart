import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
import 'screens.dart';
import 'storage_service.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  NotificationService.onWeeklyReminderOpened = () async {
    await appNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const WeeklyPantryCheckScreen(),
      ),
    );
    await NotificationService.onWeeklyReminderClosed?.call();
  };
  await NotificationService.initialize();
  final existingProducts = await StorageService.loadProducts();
  await NotificationService.syncProducts(existingProducts);
  final cameras = await availableCameras();
  runApp(PantryPulseApp(cameras: cameras, useFirebaseAuth: true));
  if (NotificationService.openedFromWeeklyReminder) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.onWeeklyReminderOpened?.call();
    });
  }
}

class PantryPulseApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final bool useFirebaseAuth;

  const PantryPulseApp({
    super.key,
    required this.cameras,
    this.useFirebaseAuth = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Pantry Pulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        scaffoldBackgroundColor: const Color(0xFFF5F8F3),
        useMaterial3: true,
      ),
      home: useFirebaseAuth
          ? AuthGate(cameras: cameras)
          : PantryPulseHomePage(cameras: cameras),
    );
  }
}

