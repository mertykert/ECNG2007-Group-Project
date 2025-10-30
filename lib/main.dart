// lib/main.dart
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/notification_service.dart';
import 'firebase_options.dart';
import 'services/missed_dose_service.dart';
import 'services/refill_service.dart';
import 'services/med_reminder_scheduler.dart';

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
  if (kDebugMode) {
    print("🔔 Notification permission: $notif");
    print("⏰ Exact alarm permission: $exact");
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      await Hive.initFlutter();
      await Hive.openBox('scheduled_reminders');

      await NotificationService.init();

      switch (taskName) {
        case 'resyncReminders': {
          final uid = (inputData?['uid'] as String?) ?? '';
          if (uid.isNotEmpty) {
            await NotificationService.resetFromFirestore(uid);
          }
          if (kDebugMode) print("🔁 Background resync of reminders completed");
          return true;
        }
        case 'midnight_missed_refill_check': {
          final uid = (inputData?['uid'] as String?)?.trim();
          if (uid != null && uid.isNotEmpty) {
            await MissedDoseService.checkMissedDosesFor(uid);
            await RefillService.checkAll(uid);
          }
          return true;
        }
        case 'checkRefill': { // FIX: missing handler
          final uid = (inputData?['uid'] as String?)?.trim();
          if (uid != null && uid.isNotEmpty) {
            await RefillService.checkAll(uid);
          }
          return true;
        }
        default:
          return true;
      }
    } catch (e, st) {
      debugPrint('WorkManager error: $e\n$st');
      return true; // prevent task reschedule loops
    }
  });
}

Future<void> _registerBackgroundFor(String uid) async {
  await Workmanager().cancelAll(); // avoid dup tasks

  await Workmanager().registerPeriodicTask(
    'medicare_reminder_resync', // unique ID
    'resyncReminders',          // taskName in dispatcher
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(minutes: 10),
    inputData: {'uid': uid},
  );

  await Workmanager().registerPeriodicTask(
    'medicare_midnight_check',
    'midnight_missed_refill_check',
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(minutes: 5),
    inputData: {'uid': uid},
  );

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

    // 2) Firestore offline-first
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Warm cache (non-blocking)
    unawaited(FirebaseFirestore.instance
        .collection('ping')
        .limit(1)
        .get(const GetOptions(source: Source.cache)));

    // 3) Local stores
    await Hive.initFlutter();
    await Hive.openBox('meds');
    await Hive.openBox('scheduled_reminders');

    // 4) Notifications + permissions + background
    await NotificationService.init();
    await checkPermissions();
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

    // 5) Restore scheduled reminders from local backup (guard uid)
    final reminderBox = Hive.box('scheduled_reminders');
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isNotEmpty) {
      for (final entry in reminderBox.toMap().entries) {
        final medId = entry.key as String;
        final data = Map<String, dynamic>.from(entry.value);
        // Only restore reminders that belong to this uid (safety)
        final ownerUid = (data['uid'] as String?) ?? currentUid;
        if (ownerUid == currentUid) {
          await MedReminderScheduler.scheduleForMed(
            uid: ownerUid,
            medId: medId,
            medData: data,
          );
        }
      }
      if (kDebugMode) {
        print("🔁 Restored ${reminderBox.length} medication reminders on startup for $currentUid");
        await NotificationService.dumpPending();
      }
    }

    // 6) Auth-driven background tasks
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await NotificationService.resetFromFirestore(user.uid);
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
    // WHY: ReceiverScope exposes active receiver globally (read by Home/Calendar)
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
