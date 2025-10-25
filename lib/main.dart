// lib/main.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:medi_care/services/med_reminder_scheduler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/missed_dose_service.dart';
import 'services/refill_service.dart';

// Screens
import 'features/authentication/screens/signup/signup.dart';
import 'features/authentication/screens/welcome/welcome.dart';
import 'features/authentication/screens/signin/signin.dart';
import 'features/Calendar/calendar.dart';
import 'features/role_based_account_selection/profiles/profile_selection.dart';
import 'features/Home/home_screen.dart';

Future<void> checkPermissions() async {
  final notif = await Permission.notification.status;
  final exact = await Permission.scheduleExactAlarm.status;
  print("🔔 Notification permission: $notif");
  print("⏰ Exact alarm permission: $exact");
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    try {
      // ✅ Always initialize core deps in background isolate before any work
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await NotificationService.init();
      await Hive.initFlutter();
      await Hive.openBox('scheduled_reminders');

      if (taskName == 'resyncReminders') {
        final uid = (inputData?['uid'] as String?) ?? '';
        final box = Hive.box('scheduled_reminders');
        for (final entry in box.toMap().entries) {
          final medId = entry.key;
          final data = Map<String, dynamic>.from(entry.value);
          await MedReminderScheduler.scheduleForMed(uid: uid, medId: medId, medData: data);
        }
        print("🔁 Background resync of reminders completed");
        return true;
      }

      if (taskName == 'midnight_missed_refill_check') {
        final uid = (inputData?['uid'] as String?)?.trim();
        if (uid != null && uid.isNotEmpty) {
          await MissedDoseService.checkMissedDosesFor(uid);
          await RefillService.checkAll(uid);
        }
        return true;
      }
    } catch (e, st) {
      debugPrint('WorkManager error: $e\n$st');
    }
    return true;
  });
}

Future<void> _registerBackgroundFor(String uid) async {
  // Cancel old workers first to avoid duplicates
  await Workmanager().cancelAll();

  // 🔹 Daily reminder resync (every morning)
  await Workmanager().registerPeriodicTask(
    'medicare_reminder_resync',
    'resyncReminders',
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(minutes: 10),
    inputData: {'uid': uid},
  );

  // 🔹 Daily missed dose/refill check
  await Workmanager().registerPeriodicTask(
    'medicare_midnight_check',
    'midnight_missed_refill_check',
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(minutes: 5),
    inputData: {'uid': uid},
  );

  // 🔹 Frequent refill checks (optional extra)
  await Workmanager().registerPeriodicTask(
    'medicare_refill_check',
    'checkRefill',
    frequency: const Duration(hours: 6),
    inputData: {'uid': uid},
  );
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  try {
    // 1) Core SDKs
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await NotificationService.init();

    // 2) Local stores (before any Hive.box)
    await Hive.initFlutter();
    await Hive.openBox('meds');
    await Hive.openBox('scheduled_reminders');

    // 3) Permissions & background
    await checkPermissions();
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

    // 4) Firestore cache
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // 5) Restore scheduled reminders from local Hive backup
    final reminderBox = Hive.box('scheduled_reminders');
    for (final entry in reminderBox.toMap().entries) {
      final medId = entry.key;
      final data = Map<String, dynamic>.from(entry.value);
      await MedReminderScheduler.scheduleForMed(
        uid: (data['uid'] ?? FirebaseAuth.instance.currentUser?.uid ?? '') as String,
        medId: medId,
        medData: data,
      );
    }
    if (kDebugMode) {
      print("🔁 Restored ${reminderBox.length} medication reminders on startup");
      await NotificationService.dumpPending();
      // Optional debug sanity check (uncomment if needed)
      // await NotificationService.sanityPing(title: '🔔 Reminder test', body: 'Arrives in ~60s.');
    }

    // 6) Auth-driven background tasks (single listener)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await NotificationService.purgeAndReseed(user.uid);
        await NotificationService.cleanUserPending(user.uid);
        await NotificationService.dumpPending();
        await _registerBackgroundFor(user.uid);
      } else {
        await Workmanager().cancelAll();
        await NotificationService.cancelAll();
      }
    });
  } catch (e, st) {
    debugPrint("Initialization failed: $e\n$st");
  } finally {
    FlutterNativeSplash.remove();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Medi_Care",
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WelcomeScreen(),
      routes: {
        "/welcome": (context) => const WelcomeScreen(),
        "/signup": (context) => const SignUpScreen(),
        "/signin": (context) => const SignInScreen(),
        "/profileSelect": (context) => const ProfileSelectionScreen(),
        "/HomeScreen": (context) => const HomeScreen(),
        "/schedule": (context) => const SchedulePage(),
      },
    );
  }
}
