import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:medi_care/features/Calendar/calendar.dart';
import 'package:medi_care/features/Medication/add_medication.dart';
import 'package:medi_care/features/Medication/edit_medication.dart';
import 'package:medi_care/widgets/link_partner_dialog.dart';
import 'package:medi_care/widgets/app_snackbars.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/med_reminder_scheduler.dart';
import '../../services/refill_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/missed_counts_chips.dart';
import 'package:medi_care/services/offline_service.dart';
import '../../widgets/fancy_drawer.dart';

// small enum for the popup menu (must be top-level)
enum _MedAction { edit, delete }



// ---------------------------------------------------------------------------
// Shell: uses the fancy drawer and hosts your unchanged screen logic/content.
// ---------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  static final GlobalKey<FancyDrawerScaffoldState> _drawerKey =
    GlobalKey<FancyDrawerScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return FancyDrawerScaffold(
      key: _drawerKey,
      drawer: const _AppDrawer(), // left menu content (converted from your Drawer)
      body: const _HomeContent(), // your original screen (moved below)
       drawerWidthFraction: 0.82,
      backgroundColor: const Color(0xFF2d59f0),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drawer content (same items & actions you had, just living inside FancyDrawer)
// ---------------------------------------------------------------------------
class _AppDrawer extends StatefulWidget {
  const _AppDrawer();

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

String? linkedPartnerId;
String? linkedPartnerName;

class _AppDrawerState extends State<_AppDrawer> {
  String caregiverName = "Loading...";

  @override
  void initState() {
    super.initState();
    _loadCaregiverName();
    _refreshLinkInfo();
  }

  Future<void> _loadCaregiverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    if (doc.exists) {
      setState(() => caregiverName = (doc.data()?['name'] as String?) ?? 'Caregiver');
    }
  }



  Future<void> _refreshLinkInfo() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final meDoc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
    final partnerId = (meDoc.data()?['linkedPartner'] as String?)?.trim();
    if (partnerId == null || partnerId.isEmpty) {
      if (!mounted) return;
      setState(() {
        linkedPartnerId = null;
        linkedPartnerName = null;
      });
      return;
    }
    final pDoc = await FirebaseFirestore.instance.collection('users').doc(partnerId).get();
    if (!mounted) return;
    setState(() {
      linkedPartnerId = partnerId;
      linkedPartnerName = pDoc.data()?['name'] as String? ?? 'Partner';
    });
  }

  Future<void> _unlinkPartner() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    // Nothing to unlink
    if (linkedPartnerId == null || linkedPartnerId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're not linked to a partner.")),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Unlink Partner", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          "Stop sharing schedules and progress with ${linkedPartnerName ?? 'your partner'}?",
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Unlink"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final users = FirebaseFirestore.instance.collection('users');
    final meRef = users.doc(me.uid);
    final partnerRef = users.doc(linkedPartnerId);

    // Ensure we only unlink if the partner still points back to me (mutual link)
    final meSnap = await meRef.get();
    final pSnap  = await partnerRef.get();
    final mePointsTo = (meSnap.data()?['linkedPartner'] as String?)?.trim();
    final pPointsTo  = (pSnap.data()?['linkedPartner'] as String?)?.trim();

    final batch = FirebaseFirestore.instance.batch();
    if (mePointsTo == linkedPartnerId) {
      batch.update(meRef, {'linkedPartner': FieldValue.delete()});
    }
    if (pSnap.exists && pPointsTo == me.uid) {
      batch.update(partnerRef, {'linkedPartner': FieldValue.delete()});
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Partner unlinked.")),
    );

    setState(() {
      linkedPartnerId = null;
      linkedPartnerName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2d59f0);

    Widget sidebarItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color color = blue,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.12),
        highlightColor: Colors.white.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white24,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.person, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    caregiverName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: Colors.white.withOpacity(0.2), thickness: 1),

            // Scrollable menu list
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  sidebarItem(
                    icon: Icons.qr_code_2_rounded,
                    label: "View Partner Code",
                    onTap: () async {
                      FancyDrawerScaffold.of(context)?.toggle();

                      final current = FirebaseAuth.instance.currentUser;
                      if (current == null) return;

                      final doc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(current.uid)
                          .get();
                      final code = (doc.data()?['partnerCode'] ?? 'N/A').toString();

                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: const Text(
                            "Your Partner Code",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          content: SelectableText(
                            code,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: blue,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Partner code copied")),
                                );
                              },
                              child: const Text("Copy", style: TextStyle(color: blue)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close", style: TextStyle(color: blue)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  sidebarItem(
                    icon: Icons.person_add_alt_1_rounded,
                    label: "Link Partner",
                    onTap: () {
                      FancyDrawerScaffold.of(context)?.toggle();
                      showDialog(context: context, builder: (_) => const LinkPartnerDialog());
                    },
                  ),
                  sidebarItem(
                    icon: Icons.link_off_rounded,
                    label: "Unlink Partner",
                    onTap: () async {
                      FancyDrawerScaffold.of(context)?.toggle();
                      _unlinkPartner();
                    },
                  ),
                  Divider(color: Colors.white.withOpacity(0.12), thickness: 1),
                  const SizedBox(height: 8),
                  sidebarItem(
                    icon: Icons.switch_account_rounded,
                    label: "Switch Account",
                    onTap: () async {
                      FancyDrawerScaffold.of(context)?.toggle();
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, "/signin");
                      }
                    },
                  ),
                  sidebarItem(
                    icon: Icons.logout_rounded,
                    label: "Log Out",
                    onTap: () async {
                      FancyDrawerScaffold.of(context)?.toggle();
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, "/welcome");
                      }
                    },
                  ),
                ],
              ),
            ),

            // Footer (non-scrolling)
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.center,
              child: Text(
                "MediCare v1.0",
                style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Your original Home screen logic/content (unchanged except: no drawer,
// and the menu button toggles the FancyDrawer).
// ---------------------------------------------------------------------------
class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  String caregiverName = "Loading...";
  final ValueNotifier<List<double>> weeklyProgressNotifier = ValueNotifier(List.filled(7, 0.0));
  final ValueNotifier<double> _todayProgressNotifier = ValueNotifier(0.0);
  StreamSubscription? _medListener;
  Timer? _updateThrottle;

  @override
  void initState() {
    super.initState();
    weeklyProgressNotifier.value = List.filled(7, 0.0);
    _todayProgressNotifier.value = 0.0;
    _loadCaregiverName();
    _setupMedicationsListener();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _loadWeeklyProgress(user.uid);
      _loadTodayProgress(user.uid);
      _adjustDailyRemainingPills(user.uid);
    }
  }

  @override
  void dispose() {
    _medListener?.cancel();
    weeklyProgressNotifier.dispose();
    _todayProgressNotifier.dispose();
    super.dispose();
  }

  Future<String> _getTargetUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return (doc.data()?['linkedPartner'] as String?)?.trim().isNotEmpty == true
        ? doc['linkedPartner']
        : user.uid;
  }

  Future<void> _loadCaregiverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    if (doc.exists) {
      setState(() => caregiverName = (doc.data()?['name'] as String?) ?? 'Caregiver');
    }
  }

  Future<bool> _confirmDelete(String medName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Confirm Deletion", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$medName"?',
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
            label: const Text("Delete"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _setupMedicationsListener() async {
    final targetUserId = await _getTargetUserId();
    if (targetUserId.isEmpty) return;

    _medListener = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUserId)
        .collection('medications')
        .snapshots()
        .listen((_) {
      _updateThrottle?.cancel();
      _updateThrottle = Timer(const Duration(milliseconds: 800), () {
        _loadWeeklyProgress(targetUserId);
        _loadTodayProgress(targetUserId);
      });
    });

    _loadWeeklyProgress(targetUserId);
    _loadTodayProgress(targetUserId);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getTodayMedicationsStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['linkedPartner'];
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medications')
        .where('date', isEqualTo: today)
        .snapshots()
        .map((snap) => snap.docs);

    if (partnerId == null || partnerId.toString().isEmpty) {
      yield* userStream;
      return;
    }

    final partnerStream = FirebaseFirestore.instance
        .collection('users')
        .doc(partnerId)
        .collection('medications')
        .where('date', isEqualTo: today)
        .snapshots()
        .map((snap) => snap.docs);

    yield* Rx.combineLatest2(userStream, partnerStream, (a, b) {
      final combined = [...a, ...b];
      final unique = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final doc in combined) {
        final data = doc.data();
        final key = "${data['name'] ?? ''}_${data['time'] ?? ''}_${data['date'] ?? ''}";
        unique[key] = doc;
      }
      return unique.values.toList();
    });
  }

  Future<void> _markAsTaken(String ownerId, String id, bool currentStatus) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medSnap = await userRef.collection('medications').doc(id).get();
    if (!medSnap.exists) return;

    final medData = medSnap.data()!;
    final newStatus = !currentStatus;

    await medSnap.reference.update({'taken': newStatus});

    if (newStatus) {
      final perDose = (medData['perDose'] ?? 1) as int;
      final remaining = ((medData['remainingPills'] ?? medData['totalPills'] ?? 0) as int) - perDose;
      await medSnap.reference.update({'remainingPills': remaining.clamp(0, 100000)});
      await RefillService.checkOne(ownerId, id);
    }

    final ownerDoc = await FirebaseFirestore.instance.collection('users').doc(ownerId).get();
    final partnerId = ownerDoc.data()?['linkedPartner'];
    if (partnerId == null || partnerId.toString().isEmpty) {
      _loadTodayProgress(ownerId);
      if (mounted) setState(() {});
      return;
    }

    if (partnerId != null && partnerId.toString().isNotEmpty) {
      final partnerRef = FirebaseFirestore.instance.collection('users').doc(partnerId).collection('medications');
      final match = await partnerRef
          .where('name', isEqualTo: medData['name'])
          .where('time', isEqualTo: medData['time'])
          .where('date', isEqualTo: medData['date'])
          .get();
      for (var doc in match.docs) {
        await doc.reference.update({'taken': newStatus});
      }
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await OfflineService.upsertTodayMed(ownerId, today, {
      'id': id,
      'owner': ownerId,
      'name': medData['name'],
      'time': medData['time'],
      'date': medData['date'],
      'taken': newStatus,
      'remainingPills': (medData['remainingPills'] ?? medData['totalPills']),
      'expiryDate': medData['expiryDate'],
    });

    _loadTodayProgress(ownerId);
    if (mounted) setState(() {});
  }

  Future<void> _adjustDailyRemainingPills(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = 'lastAdjusted_$uid';
      final lastAdjusted = prefs.getString(todayKey);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (lastAdjusted == today) return; // already adjusted today

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userDoc = await userRef.get();
      final partnerId = (userDoc.data()?['linkedPartner'] as String?)?.trim();

      // collect all meds for user + partner
      final owners = [uid, if (partnerId != null && partnerId.isNotEmpty) partnerId];
      for (final owner in owners) {
        final ref = FirebaseFirestore.instance.collection('users').doc(owner);
        final meds = await ref
            .collection('medications')
            .where('date', isEqualTo: today)
            .get();

        final missedMeds = <Map<String, dynamic>>[];

        for (final doc in meds.docs) {
          final data = doc.data();
          final taken = data['taken'] == true;
          final alreadyAdjusted = data['adjustedFor'] == today;

          if (taken && !alreadyAdjusted) {
            // only decrease once per day
            final perDose = (data['perDose'] ?? 1) as int;
            final remaining =
                ((data['remainingPills'] ?? data['totalPills'] ?? 0) as int) - perDose;

            await doc.reference.update({
              'remainingPills': remaining.clamp(0, 100000),
              'adjustedFor': today,
            });

            await RefillService.checkOne(owner, doc.id);
          } else if (!taken) {
            missedMeds.add({
              'name': data['name'],
              'time': data['time'],
            });
          }
        }

        // Save missed meds summary for this owner
        if (missedMeds.isNotEmpty) {
          await ref.collection('missed').doc(today).set({'meds': missedMeds});
        }
      }

      await prefs.setString(todayKey, today);
      debugPrint("✅ Adjusted remaining pills & marked missed meds for $today");
    } catch (e) {
      debugPrint("⚠️ adjustDailyRemainingPills failed: $e");
    }
  }

  Future<void> debugListPendingNotifications() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final pending = await plugin.pendingNotificationRequests();
    debugPrint("📋 Pending count: ${pending.length}");
    for (final p in pending) {
      debugPrint("➡️ ${p.id} :: ${p.title} :: ${p.body}");
    }
  }

  // Cancel local notifications for a med (handles int | num from Firestore)
  Future<void> _cancelMedNotifications(Map<String, dynamic> medData) async {
    try {
      final ids = (medData['notificationIds'] as Map?)?.cast<String, dynamic>();
      if (ids == null) return;
      final reminder = ids['reminder'];
      final expiry   = ids['expiry'];
      if (reminder is int) await NotificationService.cancel(reminder);
      if (expiry is int)   await NotificationService.cancel(expiry);
    } catch (_) {}
  }

  Future<bool> _deleteMedication(String ownerId, String id) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medSnap = await userRef.collection('medications').doc(id).get();
    if (!medSnap.exists) return false;

    final data = medSnap.data()!;
    final name = (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : 'Medication';

    // central + legacy cancel
    await MedReminderScheduler.cancelForMed(ownerId, id);
    await _cancelMedNotifications(data);

    await medSnap.reference.delete();

    // partner mirror + offline cleanup (same as before) ...
    final ownerDoc = await userRef.get();
    final partnerId = ownerDoc.data()?['linkedPartner']?.toString();
    if (partnerId != null && partnerId.isNotEmpty) {
      final partnerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .collection('medications');

      final partnerDocById = await partnerRef.doc(id).get();
      if (partnerDocById.exists) {
        await partnerDocById.reference.delete();
      } else {
        final match = await partnerRef
            .where('name', isEqualTo: data['name'])
            .where('time', isEqualTo: data['time'])
            .where('date', isEqualTo: data['date'])
            .get();
        for (final doc in match.docs) {
          await doc.reference.delete();
        }
      }
    }

    final todayDel = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await OfflineService.deleteTodayMedById(ownerId, todayDel, id);

    if (mounted) {
      showMedicationDeletedSuccess(context, name: name);
      setState(() {});
    }
    return true;
  }

  Future<void> _loadTodayProgress(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final partnerId = userDoc.data()?['linkedPartner'];
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      List<QuerySnapshot> results = [];

      results.add(await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medications')
          .where('date', isEqualTo: today)
          .get());

      if (partnerId != null && partnerId.toString().isNotEmpty) {
        results.add(await FirebaseFirestore.instance
            .collection('users')
            .doc(partnerId)
            .collection('medications')
            .where('date', isEqualTo: today)
            .get());
      }

      final allDocs = results.expand((r) => r.docs).toList();
      if (allDocs.isEmpty) {
        _todayProgressNotifier.value = 0.0;
        await OfflineService.saveTodayProgress(uid, today, 0.0);
      } else {
        final total = allDocs.length;
        final taken = allDocs.where((d) => d['taken'] == true).length;
        final ratio = total == 0 ? 0.0 : taken / total;
        _todayProgressNotifier.value = ratio;
        await OfflineService.saveTodayProgress(uid, today, ratio);

        final mapped = allDocs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'id': d.id,
            'owner': d.reference.parent.parent!.id,
            'name': data['name'],
            'time': data['time'],
            'date': data['date'],
            'taken': data['taken'],
            'remainingPills': data['remainingPills'],
            'expiryDate': data['expiryDate'],
          };
        }).toList();

        await OfflineService.saveTodayMeds(uid, today, mapped);
      }
    } catch (e) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cached = OfflineService.loadTodayProgress(uid, today);
      if (cached != null) {
        _todayProgressNotifier.value = cached;
        debugPrint("⚠️ Using cached today progress due to: $e");
      }
    }
  }

  Future<void> _loadWeeklyProgress(String uid) async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!mounted) return;

      final partnerId = userDoc.data()?['linkedPartner'];
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      List<double> progress = [];

      for (int i = 0; i < 7; i++) {
        final dateStr = DateFormat('yyyy-MM-dd').format(startOfWeek.add(Duration(days: i)));
        List<QuerySnapshot> results = [];
        if (!mounted) return;

        results.add(await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medications')
            .where('date', isEqualTo: dateStr)
            .get());

        if (partnerId != null && partnerId.toString().isNotEmpty) {
          results.add(await FirebaseFirestore.instance
              .collection('users')
              .doc(partnerId)
              .collection('medications')
              .where('date', isEqualTo: dateStr)
              .get());
        }

        if (!mounted) return;

        final allDocs = results.expand((r) => r.docs).toList();
        if (allDocs.isEmpty) {
          progress.add(0.0);
        } else {
          final total = allDocs.length;
          final taken = allDocs.where((d) => d['taken'] == true).length;
          progress.add(taken / total);
        }
      }

      if (mounted) {
        weeklyProgressNotifier.value = progress;
        final weekStartIso = DateFormat('yyyy-MM-dd').format(startOfWeek);
        await OfflineService.saveWeekProgress(uid, weekStartIso, progress);
      }
    } catch (e) {
      // Today fallback
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cached = OfflineService.loadTodayProgress(uid, today);
      if (cached != null) _todayProgressNotifier.value = cached;

      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final weekKey = DateFormat('yyyy-MM-dd').format(startOfWeek);
      final cachedWeek = OfflineService.loadWeekProgress(uid, weekKey);
      if (cachedWeek != null && mounted) weeklyProgressNotifier.value = cachedWeek;

      debugPrint("Offline fallback used: $e");
    }
  }


  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final IconData greetingIcon =
    hour < 12 ? Icons.wb_sunny_rounded : (hour < 18 ? Icons.wb_cloudy_rounded : Icons.nightlight_round);

    return Scaffold(
      backgroundColor: Colors.white,

      // ⬇️ SliverAppBar inside NestedScrollView so the header can scroll away
      body: SafeArea(
        top: false, // SliverAppBar handles its own padding
        child: NestedScrollView(
          headerSliverBuilder: (context, innerScrolled) => [
            SliverAppBar(
              pinned: false,            // don't stick at top
              floating: true,           // appear when you scroll up a bit
              snap: true,               // snap open nicely
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.white,
              toolbarHeight: 64,

              leading: IconButton(
                icon: const Icon(Icons.menu_rounded, color: Color(0xFF2d59f0), size: 28),
                onPressed: () => HomeScreen._drawerKey.currentState?.toggle(),
              ),

              titleSpacing: 0,
              title: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 220,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "Good ${hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"}",
                        style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caregiverName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d59f0).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(greetingIcon, color: const Color(0xFF2d59f0), size: 22),
                  ),
                ),
              ],
            ),
          ],

          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                const MissedCountsChips(),
                ValueListenableBuilder<List<double>>(
                  valueListenable: weeklyProgressNotifier,
                  builder: (context, weeklyProgress, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 5),
                        const Text("Weekly Progress", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        _buildProgressGraph(),
                        const SizedBox(height: 25),
                        _buildTodayTakenMeter(),
                        const SizedBox(height: 25),
                        Row(
                          children: [
                            Expanded(
                              child: _modernButton("Add Medication", Icons.add_circle_outline, onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMedicationScreen()));
                              }),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _modernButton("View Schedule", Icons.calendar_today_outlined, onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulePage()));
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),
                        const Text("Today's Medications", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 15),
                        StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                          stream: _getTodayMedicationsStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final meds = snapshot.data!;
                            if (meds.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text("No medications added yet.",
                                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                                ),
                              );
                            }
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.76,
                              ),
                              itemCount: meds.length,
                              itemBuilder: (context, index) {
                                final data = meds[index].data();
                                return _modernMedicationCard({
                                  'id': meds[index].id,
                                  'owner': meds[index].reference.parent.parent!.id,
                                  'name': data['name'] ?? 'Unknown',
                                  'time': data['time'] ?? 'Unknown',
                                  'taken': data['taken'] ?? false,
                                  'remainingPills': data['remainingPills'],
                                  'expiryDate': data['expiryDate'],
                                });
                              },
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  // ==== your helpers & widgets (unchanged) ================================

  Widget _buildProgressGraph() { /* … exactly as you posted … */
    return ValueListenableBuilder<List<double>>(
      valueListenable: weeklyProgressNotifier,
      builder: (context, weeklyProgress, _) {
        return Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  // IMPORTANT: return one item per touched spot (all null) to avoid the crash
                  getTooltipItems: (touchedSpots) =>
                      List.generate(touchedSpots.length, (_) => null),
                ),
                getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
                    .map(
                      (_) => TouchedSpotIndicatorData(
                    FlLine(color: Colors.transparent, strokeWidth: 0),
                    const FlDotData(show: false),
                  ),
                )
                    .toList(),
              ),
              minX: 0, maxX: 6, minY: 0, maxY: 1,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 28, interval: 1,
                    getTitlesWidget: (x, _) {
                      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                      final i = x.toInt();
                      if (i < 0 || i > 6) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          days[i],
                          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: const Color(0xFF2d59f0),
                  barWidth: 4,
                  spots: List.generate(
                    7,
                        (i) => FlSpot(i.toDouble(), (i < weeklyProgress.length ? weeklyProgress[i] : 0.0)),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [const Color(0xFF2d59f0).withOpacity(0.25), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodayTakenMeter() { /* … exactly as you posted … */
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2d59f0),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _todayProgressNotifier,
        builder: (context, todayProgress, _) {
          final v = todayProgress.clamp(0.0, 1.0);
          final percentage = (v * 100).toStringAsFixed(0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "Pills Taken (Today)",
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    "$percentage%",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: v,
                  color: Colors.white,
                  backgroundColor: Colors.white30,
                  minHeight: 10,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modernButton(String label, IconData icon, {required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 15)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2d59f0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
    );
  }

  Widget _dotIcon({required IconData icon, required Color fg, required Color bg}) {
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 15, color: fg),
    );
  }

  int? _daysLeft(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    try {
      return DateTime.parse(iso).difference(DateTime.now()).inDays;
    } catch (_) {
      return null;
    }
  }

  Widget _modernMedicationCard(Map<String, dynamic> med) {
    final bool isTaken = med['taken'] ?? false;
    final String name = med['name'] ?? 'Unknown';
    final String time = med['time'] ?? 'Unknown';
    final String id = med['id'];
    final String owner = med['owner'];

    final int? remainingPills = (med['remainingPills'] is int) ? med['remainingPills'] as int : null;
    final String? expiryDate = (med['expiryDate'] is String && (med['expiryDate'] as String).trim().isNotEmpty)
        ? med['expiryDate'] as String
        : null;

    final int? expiryDays = _daysLeft(expiryDate);
    final bool needsRefill = (remainingPills ?? 9999) <= 5;
    final bool expiringSoon = expiryDays != null && expiryDays >= 0 && expiryDays <= 30;

    const blue = Color(0xFF2d59f0);

    Future<void> onMenuAction(_MedAction a) async {
      switch (a) {
        case _MedAction.edit:
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditMedicationScreen(ownerId: owner, medId: id)),
          );
          if (mounted) setState(() {});
          break;
        case _MedAction.delete:
          final ok = await _confirmDelete(name);
          if (ok) await _deleteMedication(owner, id);
          break;
      }
    }

    Widget moreMenu() {
      return PopupMenuButton<_MedAction>(
        tooltip: 'More',
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.grey),
        color: Colors.white,
        elevation: 6,
        offset: const Offset(0, 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        constraints: const BoxConstraints(minWidth: 88, maxWidth: 96),
        itemBuilder: (context) => <PopupMenuEntry<_MedAction>>[
          PopupMenuItem<_MedAction>(
            value: _MedAction.edit,
            height: 42,
            child: Center(
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: blue.withOpacity(0.10), shape: BoxShape.circle),
                child: const Icon(Icons.edit_rounded, size: 18, color: blue),
              ),
            ),
          ),
          PopupMenuItem<_MedAction>(
            value: _MedAction.delete,
            height: 42,
            child: Center(
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.10), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              ),
            ),
          ),
        ],
        onSelected: onMenuAction,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: (isTaken ? Colors.green : blue).withOpacity(0.12),
                child: Icon(Icons.medical_services_rounded,
                    color: isTaken ? Colors.green : blue, size: 22),
              ),
              moreMenu(),
            ],
          ),
          const SizedBox(height: 10),

          // take the vertical room ABOVE the button
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                if (needsRefill || expiringSoon) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (needsRefill)
                        _dotIcon(
                          icon: Icons.local_pharmacy_outlined,
                          fg: const Color(0xFFE53935),
                          bg: const Color(0x1AE53935),
                        ),
                      if (expiringSoon)
                        _dotIcon(
                          icon: Icons.hourglass_bottom_rounded,
                          fg: const Color(0xFFF39C12),
                          bg: const Color(0x1AF39C12),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // bottom button
          Align(
            alignment: Alignment.center,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.selectionClick();
                _markAsTaken(owner, id, isTaken);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isTaken ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isTaken ? 'Taken' : 'Pending',
                  style: TextStyle(
                    color: isTaken ? Colors.green.shade700 : Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
