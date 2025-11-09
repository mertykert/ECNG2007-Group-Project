// lib/main.dart
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:medi_care/services/offline_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'analytics/analytics_bootstrap.dart';
import 'features/authentication/auth_gate.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';
import 'services/missed_dose_service.dart';
import 'services/refill_service.dart';
import 'services/med_reminder_scheduler.dart';

// Screens
import 'features/authentication/screens/onboarding_screen.dart';
import 'features/authentication/screens/signup/signup.dart';
import 'features/authentication/screens/welcome/welcome.dart';
import 'features/authentication/screens/signin/signin.dart';
import 'features/Calendar/calendar.dart';
import 'features/role_based_account_selection/profiles/profile_selection.dart';
import 'features/Home/home_screen.dart';

late final FirebaseAnalytics analytics;

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
            await RefillService.checkAll(uid);
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

    analytics = FirebaseAnalytics.instance;

    // (Optional) Disable collection until user consents:
     await analytics.setAnalyticsCollectionEnabled(true);
    await AnalyticsBootstrap.init();

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

    // Restore scheduled reminders from local backup (guard uid)
    Future<void> _restoreScheduledRemindersForCurrentUser() async {
      final box = Hive.box('scheduled_reminders');
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (currentUid.isEmpty) return;

      int scanned = 0, restored = 0, skipped = 0;

      Future<bool> _tryRestoreOne(Map<dynamic, dynamic> raw, {required String fallbackMedId}) async {
        final data = Map<String, dynamic>.from(raw); // ensure String keys
        final ownerUid = (data['uid'] as String?) ?? currentUid;
        if (ownerUid != currentUid) return false;

        final medId = (data['medId'] as String?) ?? fallbackMedId;
        try {
          await MedReminderScheduler.scheduleForMed(
            uid: ownerUid,
            medId: medId,
            medData: data,
          );
          return true;
        } catch (e, st) {
          if (kDebugMode) debugPrint("⚠️ Restore failed for medId=$medId: $e\n$st");
          return false;
        }
      }

      final map = box.toMap();
      for (final entry in map.entries) {
        scanned++;
        final keyStr = entry.key.toString();
        final v = entry.value;

        if (v is Map) {
          final ok = await _tryRestoreOne(v, fallbackMedId: keyStr);
          if (ok) restored++; else skipped++;
        } else if (v is List) {
          for (final item in v) {
            if (item is Map) {
              final ok = await _tryRestoreOne(item, fallbackMedId: (item['medId']?.toString() ?? keyStr));
              if (ok) restored++; else skipped++;
            } else {
              skipped++;
            }
          }
        } else {
          skipped++;
        }
      }

      if (kDebugMode) {
        debugPrint("🔁 Restored $restored / scanned $scanned reminders (skipped $skipped) for $currentUid");
        await NotificationService.dumpPending();
      }
    }

    final reminderBox = Hive.box('scheduled_reminders');
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isNotEmpty) {
      await _restoreScheduledRemindersForCurrentUser(); // ← use helper (do NOT keep old loop)
    }

    await OfflineService.init();

    // 6) Auth-driven background tasks
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        await MissedDoseService.checkMissedDosesFor(user.uid);
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
        home: const EntryGate(),
        navigatorObservers: [
          FirebaseAnalyticsObserver(analytics: analytics),
        ],
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

class EntryGate extends StatelessWidget {
  const EntryGate({super.key});

  Future<bool> _seenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_done') == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _seenOnboarding(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final seen = snap.data == true;
        // First app open -> onboarding; otherwise -> your normal auth/home gate
        return seen ? const AuthGate() : const OnBoardingScreen();
      },
    );
  }
}

