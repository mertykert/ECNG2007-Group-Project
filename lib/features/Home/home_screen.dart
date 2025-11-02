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
import '../../analytics/analytics_service.dart';
import '../../services/med_reminder_scheduler.dart';
import '../../services/refill_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/missed_counts_chips.dart';
import 'package:medi_care/services/offline_service.dart';
import '../../widgets/fancy_drawer.dart';
import 'package:medi_care/services/partner_service.dart' as partner_service;

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
List<String> _linkedReceivers = const [];
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meSub;

class _AppDrawerState extends State<_AppDrawer> {
  String caregiverName = "Loading...";
  String _userRole = ''; // caregiver|receiver

  @override
  void initState() {
    super.initState();
    _loadCaregiverName();
    _refreshLinkInfo();
    _loadLinkedReceiversList();

    //  Live listener keeps drawer in sync automatically
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      _meSub = FirebaseFirestore.instance
          .collection('users')
          .doc(me.uid)
          .snapshots()
          .listen((snap) {
        final d = snap.data() ?? {};
        final partnerId = (d['linkedPartner'] as String?)?.trim();
        final role = (d['role'] as String?)?.toLowerCase() ?? '';
        final list = (d['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];

        if (!mounted) return;
        setState(() {
          _userRole = role;
          linkedPartnerId = partnerId;
          // keep name if we have it; resolve async if changed
          _linkedReceivers = list;
        });

        // Resolve partner name lazily if needed
        if (partnerId != null && partnerId.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(partnerId)
              .get(const GetOptions(source: Source.serverAndCache)).then((p) {
            if (!mounted) return;
            final pd = p.data() ?? {};
            setState(() {
              linkedPartnerName = (pd['profile']?['name'] as String?) ??
                  (pd['name'] as String?) ??
                  (pd['email'] as String?);
            });
          });
        } else {
          if (!mounted) return;
          setState(() => linkedPartnerName = null);
        }
      });
    }
  }

  @override
  void dispose() {
    _meSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCaregiverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        caregiverName = (data['name'] as String?) ?? 'Caregiver';
        _userRole = (data['role'] as String?)?.toLowerCase() ?? '';
      });
    }
  }

  Future<void> _loadLinkedReceiversList() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .get(const GetOptions(source: Source.serverAndCache));

    final data = doc.data() ?? {};
    final role = (data['role'] as String?)?.toLowerCase() ?? '';

    // Caregivers keep the list; receivers typically don't.
    if (role == 'caregiver') {
      final list = (data['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _linkedReceivers = list;
      });
    } else {
      // Receiver: ensure local list is empty to avoid stale UI
      if (!mounted) return;
      setState(() {
        _linkedReceivers = const <String>[];
      });
    }
  }

  Future<void> _refreshLinkInfo() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    try {
      final meDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(me.uid)
          .get(const GetOptions(source: Source.serverAndCache));

      final data = meDoc.data() ?? {};
      final partnerId = (data['linkedPartner'] as String?)?.trim();
      String? partnerName;

      if (partnerId != null && partnerId.isNotEmpty) {
        final pDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(partnerId)
            .get(const GetOptions(source: Source.serverAndCache));
        final pd = pDoc.data() ?? {};
        partnerName = (pd['profile']?['name'] as String?) ??
            (pd['name'] as String?) ??
            (pd['email'] as String?);
      }

      if (!mounted) return;
      setState(() {
        linkedPartnerId = partnerId;
        linkedPartnerName = partnerName;
        _userRole = (data['role'] as String?)?.toLowerCase() ?? '';
      });
    } catch (_) {
      // keep current state on transient failures
    }
  }

  Future<void> _unlinkPartner() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    // Confirm UI
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

    try {
      final db = FirebaseFirestore.instance;
      final meRef = db.collection('users').doc(me.uid);

      // 🔹 Always fetch fresh from server; don't trust local state.
      final meSnap = await meRef.get(const GetOptions(source: Source.server));
      final meData = meSnap.data() ?? {};
      final myRole = (meData['role'] as String?)?.toLowerCase() ?? '';
      String? partnerId = (meData['linkedPartner'] as String?)?.trim();

      // 🔹 Receiver fallback: if linkedPartner missing, try reverse-lookup caregiver
      if ((partnerId == null || partnerId.isEmpty) && myRole == 'receiver') {
        final q = await db
            .collection('users')
            .where('linkedReceivers', arrayContains: me.uid)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (q.docs.isNotEmpty) {
          partnerId = q.docs.first.id;
        }
      }

      // Still nothing? Then we are not linked.
      if (partnerId == null || partnerId.isEmpty) {
        if (!mounted) return;
        await _showToast(title: 'You are not linked to a partner.');
        return;
      }

      final partnerRef = db.collection('users').doc(partnerId);
      final pSnap = await partnerRef.get(const GetOptions(source: Source.server));
      final pData = pSnap.data() ?? {};
      final partnerPointsToMe = (pData['linkedPartner'] as String?)?.trim() == me.uid;

      // 🔹 Unlink both sides and maintain caregiver list
      final batch = db.batch();

      // Clear my active link if present
      if ((meData['linkedPartner'] as String?)?.trim() == partnerId) {
        batch.update(meRef, {'linkedPartner': FieldValue.delete()});
      }

      // Clear their active link if it points back to me
      if (pSnap.exists && partnerPointsToMe) {
        batch.update(partnerRef, {'linkedPartner': FieldValue.delete()});
      }

      // Maintain caregiver's linkedReceivers[] on unlink
      if (myRole == 'caregiver') {
        batch.update(meRef, {'linkedReceivers': FieldValue.arrayRemove([partnerId])});
      } else if (myRole == 'receiver') {
        batch.update(partnerRef, {'linkedReceivers': FieldValue.arrayRemove([me.uid])});
      }

      await batch.commit();

      if (!mounted) return;

      // Refresh local UI state and list so the drawer/sheet updates immediately
      setState(() {
        linkedPartnerId = null;
        linkedPartnerName = null;
      });
      await _refreshLinkInfo();      // reloads names/ids
      await _loadLinkedReceiversList(); // repopulates caregiver list
      final removedUid = linkedPartnerId;            // cache current active partner id
      await partner_service.unlinkActivePartner();   // still returns void
      if (removedUid != null && removedUid!.isNotEmpty) {
        await AppAnalytics.logPartnerUnlinked(partnerUid: removedUid!);
      }
      await _showToast(title: 'Partner unlinked', success: true);
    } catch (e) {
      if (!mounted) return;
      await _showToast(
        title: 'Unlink failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    }
  }


  Future<void> switchActiveReceiver(String receiverUid) async {
    await partner_service.switchActiveReceiver(receiverUid);
  }

  Future<void> _showSwitchReceiverSheet() async {
    const blue = Color(0xFF2d59f0);
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

// Force a fresh doc read (server pref) to avoid stale cache when sheet opens
    final meDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .get(const GetOptions(source: Source.serverAndCache));

    final data = meDoc.data() ?? {};
    final receivers = (data['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];
    if (receivers.isEmpty) {
      await _showInfoDialog('No Care Receivers', 'Link a partner first to switch.');
      return;
    }

    final initial = (data['linkedPartner'] as String?)?.trim() ?? receivers.first;

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        String sel = initial; // local state for the sheet
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.switch_account_rounded, color: blue, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Switch Care Receiver',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  for (final id in receivers)
                    RadioListTile<String>(
                      value: id,
                      groupValue: sel,
                      activeColor: blue,
                      selected: id == sel,
                      selectedTileColor: blue.withOpacity(0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      onChanged: (v) => setLocal(() => sel = v ?? sel), // <-- local setState
                      title: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(id)
                            .get(const GetOptions(source: Source.serverAndCache)),
                        builder: (c, s) {
                          final d = (s.data?.data() as Map<String, dynamic>?) ?? {};
                          final name  = (d['profile']?['name'] as String?) ??
                              (d['name'] as String?) ??
                              (d['email'] as String?) ?? id;
                          final email = (d['email'] as String?) ?? '';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
                              ),
                              if (email.isNotEmpty)
                                Text(email,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                            ],
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Switch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          await partner_service.switchActiveReceiver(sel);
                          await _refreshLinkInfo();
                          if (!mounted) return;
                          await partner_service.switchActiveReceiver(sel);
                          await AppAnalytics.logReceiverSwitched(receiverUid: sel);
                          Navigator.pop(ctx);
                          await _showInfoDialog('Done', 'Active care receiver switched.');
                        } catch (e) {
                          if (!mounted) return;
                          await _showInfoDialog('Error', e.toString().replaceFirst('Exception: ', ''));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _startLinkFlow() async {
    // Close the drawer first (FancyDrawer or Scaffold — keep what you use)
    FancyDrawerScaffold.of(context)?.toggle();
    // Scaffold.of(context).closeDrawer(); // if you use Scaffold's drawer

    // Wait for the closing animation to finish to avoid disposed-context crashes
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    // IMPORTANT: expect a String (the code) or null on Cancel
    final String? code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,           // present above the whole app
      builder: (_) => const LinkPartnerDialog(),  // DO NOT pass onSubmit
    );

    // Cancel pressed
    if (code == null || code.trim().isEmpty) return;

    // Link pressed: call service with the code
    try {
      await partner_service.linkReceiverByCode(code.trim());
      await _refreshLinkInfo();    // your existing refresh method
      if (!mounted) return;
      final receiverUid = await partner_service.linkReceiverByCode(code);
      await AppAnalytics.logPartnerLinked(receiverUid: receiverUid);
      await _showToast(title: 'Linked successfully');
      await _refreshLinkInfo();
      await _loadLinkedReceiversList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showInfoDialog(String title, String message) async {
    const blue = Color(0xFF2d59f0);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.info_rounded, color: blue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: blue)),
          ),
        ],
      ),
    );
  }

  Future<void> _showToast({
    required String title,
    String? message,
    bool success = true,
  }) async {
    const blue = Color(0xFF2d59f0);
    final bg = success ? blue : Colors.redAccent;
    final fg = Colors.white;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 2,
          backgroundColor: bg,
          margin: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: .2,
                        )),
                    if (message != null && message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(message, style: const TextStyle(color: Colors.black87)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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
                    onTap: () async {
                      await _startLinkFlow();
                    },
                  ),
                  if (_userRole == 'caregiver')
                    sidebarItem(
                      icon: Icons.switch_account_rounded,
                      label: "Switch Care Receiver",
                      onTap: () async {
                        FancyDrawerScaffold.of(context)?.toggle();
                        await _showSwitchReceiverSheet(); // defined below
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
    unawaited(() async {
      final targetUid = await _getTargetUserId();
      if (!mounted || targetUid.isEmpty) return;
      _loadWeeklyProgress(targetUid);
      _loadTodayProgress(targetUid);
      _adjustDailyRemainingPills(targetUid);
    }());
  }

  @override
  void dispose() {
    _medListener?.cancel();
    weeklyProgressNotifier.dispose();
    _todayProgressNotifier.dispose();
    super.dispose();
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

  void _setupMedicationsListener() {
    _medListener?.cancel();
    _medListener = _targetUidStream().listen((targetUserId) {
      // cancel any previous meds sub
      _updateThrottle?.cancel();

      // re-subscribe to that user's medications
      FirebaseFirestore.instance
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

      // also do an immediate load for the new target
      _loadWeeklyProgress(targetUserId);
      _loadTodayProgress(targetUserId);
    });
  }


  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getTodayMedicationsStream() async* {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      yield const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final users = FirebaseFirestore.instance.collection('users');

    // React to active partner changes automatically
    yield* users.doc(me.uid).snapshots().switchMap((meSnap) {
      final data = meSnap.data() ?? {};
      final partnerId = (data['linkedPartner'] as String?)?.trim();
      final targetUid = (partnerId != null && partnerId.isNotEmpty) ? partnerId : me.uid;

      final medsQuery = users
          .doc(targetUid)
          .collection('medications')
          .where('date', isEqualTo: today);

      return medsQuery.snapshots().map((snap) => snap.docs);
    });
  }


  Future<void> _markAsTaken(String ownerId, String id, bool currentStatus) async {
    final medRef = FirebaseFirestore.instance
        .collection('users').doc(ownerId)
        .collection('medications').doc(id);

    final medSnap = await medRef.get();
    if (!medSnap.exists) return;
    final medData = medSnap.data()!;

    final String todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final bool   newStatus = !currentStatus;

// 1) Write scalar + per-day flag for TODAY
    await medRef.update({
      'taken': newStatus,
      'takenByDate.$todayIso': newStatus,
    });

// 2) Symmetric stock math for TODAY
    final bool isToday = true; // we’re toggling from “Today’s Meds” section
    if (isToday) {
      final int perDose   = (medData['perDose'] ?? 1) as int;
      final int total     = (medData['totalPills'] ?? 0) as int;
      final int remaining = (medData['remainingPills'] ?? total) as int;

      final int delta        = newStatus ? -perDose : perDose;  // taken→subtract, undo→add back
      final int newRemaining = (remaining + delta).clamp(0, 100000);

      await medRef.update({'remainingPills': newRemaining});

      await medRef.set(
        RefillService.computeRefillPatch({
          'totalPills': total,
          'remainingPills': newRemaining,
          'refillThreshold': medData['refillThreshold'],
        }),
        SetOptions(merge: true),
      );

      // If you write to offline cache here, make sure to use newRemaining
      final today = todayIso;
      await OfflineService.upsertTodayMed(ownerId, today, {
        'id': id,
        'owner': ownerId,
        'name': medData['name'],
        'time': medData['time'],
        'date': medData['date'],
        'taken': newStatus,
        'remainingPills': newRemaining, // <-- critical: use updated value
        'expiryDate': medData['expiryDate'],
      });
    }

    // analytics
    await AppAnalytics.logMedicationTaken(ownerUid: ownerId, medId: id, taken: newStatus);

    await RefillService.checkOne(ownerId, id);

    _loadTodayProgress(ownerId);
    if (mounted) setState(() {});
  }

  Future<void> _adjustDailyRemainingPills(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = 'lastAdjusted_$uid';
      final lastAdjusted = prefs.getString(todayKey);
      final today = DateUtils.dateOnly(DateTime.now());
      final todayIso = DateFormat('yyyy-MM-dd').format(today);
      if (lastAdjusted == todayIso) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      // ⚠️ Do NOT filter by date==today; this misses "Daily" meds.
      final medsSnap = await userRef.collection('medications')
      // .limit(500) // optional safety if dataset is large
          .get(const GetOptions(source: Source.serverAndCache));

      final missedMeds = <Map<String, dynamic>>[];

      for (final doc in medsSnap.docs) {
        final data = doc.data();
        final med = {'id': doc.id, ...data};

        // Only adjust those DUE today (Daily or Once today / Weekly today)
        if (!_isScheduledForDay(med, today)) continue;

        final taken = data['taken'] == true;
        final alreadyAdjusted = (data['adjustedFor'] as String?) == todayIso;

        if (taken && !alreadyAdjusted) {
          final perDose   = (data['perDose'] ?? 1) as int;
          final total     = (data['totalPills'] ?? 0) as int;
          final remaining = (data['remainingPills'] ?? total) as int;

          final newRemaining = (remaining - perDose).clamp(0, 100000);

          // 🔁 recompute refill fields right away (clears sticky badge)
          final refillPatch = RefillService.computeRefillPatch({
            'totalPills': total,
            'remainingPills': newRemaining,
            'refillThreshold': data['refillThreshold'],
          });

          await doc.reference.set({
            'remainingPills': newRemaining,
            'adjustedFor': todayIso,
            ...refillPatch,
          }, SetOptions(merge: true));

          // Keep background predictions/notifications consistent
          await RefillService.checkOne(uid, doc.id);
        } else if (!taken) {
          missedMeds.add({'name': data['name'], 'time': data['time']});
        }
      }

      if (missedMeds.isNotEmpty) {
        await userRef.collection('missed').doc(todayIso).set({'meds': missedMeds});
      }

      await prefs.setString(todayKey, todayIso);
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

  Future<void> _showToast({
    required String title,
    String? message,
    bool success = true,
  }) async {
    const blue = Color(0xFF2d59f0);
    final bg = success ? blue : Colors.redAccent;
    final fg = Colors.white;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 2,
          backgroundColor: bg,
          margin: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: .2,
                        )),
                    if (message != null && message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(message, style: const TextStyle(color: Colors.black87)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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

    // 2) Local cache delete (safe even if offline cache missing)
    final todayDel = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      await OfflineService.deleteTodayMedById(ownerId, todayDel, id);
    } catch (_) {
      // ignore cache errors; remote succeeded
    }

    await _showToast(title: 'Medication deleted');

    if (mounted) {
      setState(() {});
      showMedicationDeletedSuccess(context, name: name);
    }
    return true;
  }

  // ================== DROP-IN HELPERS (put in the same State as your loaders) ==================

  bool _wasTakenOn(Map<String, dynamic> m, DateTime day) {
    final key = DateUtils.dateOnly(day).toIso8601String().substring(0, 10);

    // 1) Preferred: takenByDate: { 'yyyy-MM-dd': true/false }
    final Map<String, dynamic>? byDate = (m['takenByDate'] as Map?)?.cast<String, dynamic>();
    if (byDate != null) {
      final v = byDate[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
    }

    // 2) Or: takenDates: ['yyyy-MM-dd', ...]
    final List<dynamic>? dates = m['takenDates'] as List<dynamic>?;
    if (dates != null && dates.any((e) => (e as String?) == key)) {
      return true;
    }

    // 3) Or: lastTakenDate: 'yyyy-MM-dd'
    final String? last = (m['lastTakenDate'] as String?);
    if (last != null && last == key) return true;

    // 4) Legacy fallback: a plain 'taken' bool only counts if the med instance is for that date
    // (handles ONCE meds or models where 'date' marks the instance day)
    final bool taken = (m['taken'] as bool?) ?? false;
    final String? instanceDate = m['date'] as String?;
    if (taken && instanceDate == key) return true;

    return false;
  }

// You already have _isScheduledForDay(m, day). Keep using it.

// ================== REPLACE your TWO LOADERS with these versions ==================

  Future<void> _loadTodayProgress(String targetUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('medications')
          .get();

      final today = DateTime.now();
      final todayIso = DateFormat('yyyy-MM-dd').format(today);

      final todays = snap.docs
          .map((d) => {'id': d.id, ...Map<String, dynamic>.from(d.data())})
          .where((m) => _isScheduledForDay(m, today))
          .toList();

      if (todays.isEmpty) {
        _todayProgressNotifier.value = 0.0;
        await OfflineService.saveTodayProgress(targetUid, todayIso, 0.0);
        await OfflineService.saveTodayMeds(targetUid, todayIso, const []);
        return;
      }

      final total = todays.length;
      final taken = todays.where((m) => _wasTakenOn(m, today)).length;
      final ratio = total == 0 ? 0.0 : taken / total;

      _todayProgressNotifier.value = ratio;
      await OfflineService.saveTodayProgress(targetUid, todayIso, ratio);
      await OfflineService.saveTodayMeds(targetUid, todayIso, todays);

    } catch (_) {
      final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cached = OfflineService.loadTodayProgress(targetUid, todayIso);
      if (cached != null) _todayProgressNotifier.value = cached;
    }
  }

  Future<void> _loadWeeklyProgress(String targetUid) async {
    if (!mounted) return;
    try {
      final all = await FirebaseFirestore.instance
          .collection('users').doc(targetUid)
          .collection('medications')
          .get();

      final meds = all.docs.map((d) => {'id': d.id, ...Map<String, dynamic>.from(d.data())}).toList();

      final now = DateTime.now();
      final start = now.subtract(Duration(days: now.weekday - 1)); // Monday
      final progress = <double>[];

      for (int i = 0; i < 7; i++) {
        final day = DateTime(start.year, start.month, start.day + i);
        final todays = meds.where((m) => _isScheduledForDay(m, day)).toList();
        if (todays.isEmpty) {
          progress.add(0.0);
        } else {
          final total = todays.length;
          final taken = todays.where((m) => _wasTakenOn(m, day)).length;
          progress.add(taken / total);
        }
      }

      if (!mounted) return;
      weeklyProgressNotifier.value = progress;

      final weekStartIso = DateFormat('yyyy-MM-dd').format(start);
      await OfflineService.saveWeekProgress(targetUid, weekStartIso, progress);
    } catch (_) {
      final now = DateTime.now();
      final start = now.subtract(Duration(days: now.weekday - 1));
      final weekKey = DateFormat('yyyy-MM-dd').format(start);
      final cached = OfflineService.loadWeekProgress(targetUid, weekKey);
      if (cached != null && mounted) weeklyProgressNotifier.value = cached;
    }
  }


  Future<void> _showInfoDialog(String title, String message) async {
    const blue = Color(0xFF2d59f0);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.info_rounded, color: blue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: blue)),
          ),
        ],
      ),
    );
  }

  // Role-aware target uid resolution.
// Caregiver => active receiver (linkedPartner) if set; else self.
// Receiver  => always self (never write/read under caregiver!).
  Stream<String> _targetUidStream() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const Stream.empty();
    final users = FirebaseFirestore.instance.collection('users');

    return users.doc(me.uid).snapshots().map((meSnap) {
      final d = meSnap.data() ?? {};
      final role = (d['role'] as String?)?.toLowerCase() ?? '';

      if (role == 'caregiver') {
        final partner = (d['linkedPartner'] as String?)?.trim() ?? '';
        if (partner.isNotEmpty) return partner;
        final list = (d['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];
        if (list.isNotEmpty) return list.first;
        return me.uid; // fallback
      }

      // receiver or unknown role -> self
      return me.uid;
    });
  }

  Future<String> _getTargetUserId() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return '';
    final userRef = FirebaseFirestore.instance.collection('users').doc(me.uid);
    final snap = await userRef.get(const GetOptions(source: Source.serverAndCache));
    final d = snap.data() ?? {};
    final role = (d['role'] as String?)?.toLowerCase() ?? '';

    if (role == 'caregiver') {
      final partner = (d['linkedPartner'] as String?)?.trim() ?? '';
      if (partner.isNotEmpty) return partner;
      final list = (d['linkedReceivers'] as List?)?.cast<String>() ?? const <String>[];
      if (list.isNotEmpty) return list.first;
      return me.uid; // fallback
    }

    // receiver or unknown role -> self
    return me.uid;
  }

  bool isTakenOn(Map<String, dynamic> m, DateTime day) {
    final iso = DateUtils.dateOnly(day).toIso8601String().substring(0, 10);
    final byDate = (m['takenByDate'] as Map?)?.cast<String, dynamic>() ?? const {};
    final v = byDate[iso];
    if (v == true || (v is num && v != 0)) return true;
    if ((m['date'] as String?) == iso && (m['taken'] == true)) return true; // once-med fallback
    return false;
  }

  bool _isScheduledForDay(Map<String, dynamic> m, DateTime day) {
    final repeat = (m['repeat'] ?? 'Once') as String;
    final dateStr = (m['date'] ?? '') as String;
    final fmt = DateFormat('yyyy-MM-dd');

    if (repeat == 'Daily') return true;
    if (repeat == 'Weekly') {
      if (dateStr.isEmpty) return false;
      final d = fmt.parse(dateStr, true);
      return d.weekday == day.weekday;
    }
    // Once (exact date match)
    if (dateStr.isEmpty) return false;
    return fmt.format(day) == dateStr;
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
                                final ownerId = await _getTargetUserId(); // active (receiver if caregiver has one)
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => AddMedicationScreen(ownerId: ownerId)),
                                );
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
                          stream: _targetUidStream().asyncExpand((uid) {
                            return FirebaseFirestore.instance
                                .collection('users').doc(uid)
                                .collection('medications')
                                .snapshots()
                                .map((s) => s.docs);
                          }),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final docs = snapshot.data!;
                            final today = DateTime.now();

                            // Convert to maps and filter like Calendar
                            final medsForToday = docs.map((d) {
                              final m = Map<String, dynamic>.from(d.data());
                              m['id'] = d.id;
                              m['owner'] = d.reference.parent.parent!.id;
                              return m;
                            }).where((m) => _isScheduledForDay(m, today)).toList();

                            if (medsForToday.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text("No medications for today.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                                ),
                              );
                            }

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.76,
                              ),
                              itemCount: medsForToday.length,
                              itemBuilder: (context, index) {
                                final m = medsForToday[index];
                                return _modernMedicationCard({
                                  'id': m['id'],
                                  'owner': m['owner'],
                                  'name': m['name'] ?? 'Unknown',
                                  'time': m['time'] ?? 'Unknown',
                                  'taken': m['taken'] ?? false,
                                  'remainingPills': m['remainingPills'],
                                  'expiryDate': m['expiryDate'],
                                  'repeat': m['repeat'],
                                  'date': m['date'],
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

  Widget _buildProgressGraph() {
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
                  isStrokeCapRound: false,
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

  bool _isDueOn(Map<String, dynamic> m, DateTime day) {
    final repeat = (m['repeat'] as String? ?? '').toLowerCase(); // 'daily'|'weekly'|'once'
    if (repeat == 'daily') return true;

    if (repeat == 'weekly') {
      final int? dow = (m['weekday'] as int?); // 1=Mon..7=Sun (adjust to your schema)
      final int dayDow = (day.weekday);        // 1..7
      return dow != null && dow == dayDow;
    }

    if (repeat == 'once') {
      final String? iso = (m['date'] as String?); // 'yyyy-MM-dd'
      final String dIso = DateUtils.dateOnly(day).toIso8601String().substring(0, 10);
      return iso != null && iso == dIso;
    }

    return false;
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
