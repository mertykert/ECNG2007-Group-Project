// lib/features/Calendar/calendar.dart
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:medi_care/widgets/back_button_overlay.dart';
import '../../services/med_reminder_scheduler.dart';
import '../../services/refill_service.dart';
import '../../widgets/app_snackbars.dart';
import '../Medication/add_medication.dart';
import '../../services/notification_service.dart';
import 'package:medi_care/features/Medication/edit_medication.dart';

Map<String, bool> _localTakenCache = {};

enum CalendarView { month, week, day }

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  CalendarView _currentView = CalendarView.month;

  /// Stream all medications for both user and partner (dedup by name/time/date)
  Stream<List<Map<String, dynamic>>> _getMedicationsStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['linkedPartner'];

    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medications')
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => {'id': d.id, 'ownerId': user.uid, ...d.data()}).toList());

    if (partnerId == null || partnerId.toString().isEmpty) {
      yield* userStream;
      return;
    }

    final partnerStream = FirebaseFirestore.instance
        .collection('users')
        .doc(partnerId)
        .collection('medications')
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => {'id': d.id, 'ownerId': partnerId, ...d.data()})
        .toList());

    yield* CombineLatestStream.combine2(
      userStream,
      partnerStream,
          (List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
        final combined = [...a, ...b];
        final unique = <String, Map<String, dynamic>>{};
        for (final med in combined) {
          final key = "${med['name']}_${med['time']}_${med['date']}";
          unique[key] = med;
        }
        return unique.values.toList();
      },
    );
  }

  /// Toggle taken state for a specific date (per-day tracking)
  Future<void> _toggleTaken({
    required String ownerId,
    required String id,
    required bool current,
  }) async {
    final selectedDateStr =
    DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now());
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final localKey = '$id|$selectedDateStr';

    // Optimistic UI
    setState(() => _localTakenCache[localKey] = !current);

    final ownerRef =
    FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medRef = ownerRef.collection('medications').doc(id);

    try {
      final medSnap = await medRef.get();
      if (!medSnap.exists) {
        setState(() => _localTakenCache.remove(localKey));
        return;
      }
      final medData = medSnap.data()!;
      final newStatus = !current;

      // Per-day taken log
      await medRef.update({
        'taken': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Keep Home <-> Schedule in sync for today
      if (selectedDateStr == todayStr) {
        await medRef.update({'taken': newStatus});
      }

      // If taken today, decrement stock (centralized)
      if (newStatus && selectedDateStr == todayStr) {
        final perDose = (medData['perDose'] ?? 1) as int;
        await RefillService.onDoseTaken(ownerId, id, perDose: perDose);
      }

      // Mirror to partner
      final ownerUserDoc = await ownerRef.get();
      final partnerId = ownerUserDoc.data()?['linkedPartner'];
      if (partnerId != null && partnerId.toString().isNotEmpty) {
        final partnerMedRef = FirebaseFirestore.instance
            .collection('users')
            .doc(partnerId)
            .collection('medications');

        final match = await partnerMedRef
            .where('name', isEqualTo: medData['name'])
            .where('time', isEqualTo: medData['time'])
            .get();

        for (var doc in match.docs) {
          await partnerMedRef.doc(doc.id).update({
            'taken': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {
      // Rollback on failure
      setState(() => _localTakenCache.remove(localKey));
    }
  }




  // Cancel local notifications for a med (handles int | num from Firestore)
  Future<void> _cancelMedNotifications(Map<String, dynamic> medData) async {
    try {
      final ids = (medData['notificationIds'] as Map?)?.cast<String, dynamic>();
      if (ids == null) return;
      final reminder = ids['reminder'];
      final expiry = ids['expiry'];
      if (reminder is int) await NotificationService.cancel(reminder);
      if (expiry is int) await NotificationService.cancel(expiry);
    } catch (_) {}
  }

  /// Delete medication — cancels notifications, mirrors to partner, shows red toast
  Future<void> _deleteMed({
    required String ownerId,
    required String id,
    required String name,
  }) async {
    try {
      final ownerRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
      final medSnap = await ownerRef.collection('medications').doc(id).get();
      if (!medSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Medication no longer exists')),
          );
        }
        return;
      }

      // 🔔 cancel ALL reminders (map ids + reminderNotificationId) + show popup
      await MedReminderScheduler.cancelForMed(ownerId, id); // central path
      // Legacy local cleanup (kept as best-effort)
      await _cancelMedNotifications(medSnap.data()!);

      await medSnap.reference.delete();

      // partner mirror (unchanged) ...
      final ownerUserDoc = await ownerRef.get();
      final partnerId = ownerUserDoc.data()?['linkedPartner']?.toString();
      if (partnerId != null && partnerId.isNotEmpty) {
        final partnerMedRef = FirebaseFirestore.instance
            .collection('users')
            .doc(partnerId)
            .collection('medications');

        final match = await partnerMedRef
            .where('name', isEqualTo: medSnap.data()!['name'])
            .where('time', isEqualTo: medSnap.data()!['time'])
            .where('date', isEqualTo: medSnap.data()!['date'])
            .get();

        for (final doc in match.docs) {
          await partnerMedRef.doc(doc.id).delete();
        }
      }

      if (!mounted) return;
      setState(() {}); // refresh
      showMedicationDeletedSuccess(context, name: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error deleting medication: $e')));
      }
    }
  }


  /// Filter meds per selected day
  List<Map<String, dynamic>> _filterForDay(
      List<Map<String, dynamic>> meds, DateTime day) {
    final dayStr = DateFormat('yyyy-MM-dd').format(day);
    return meds.where((m) {
      final repeat = (m['repeat'] ?? 'Once') as String;
      final medDateStr = (m['date'] ?? '') as String;

      if (repeat == 'Daily') return true;
      if (repeat == 'Weekly') {
        if (medDateStr.isEmpty) return false;
        final medDate = DateFormat('yyyy-MM-dd').parse(medDateStr);
        return medDate.weekday == day.weekday;
      }
      return medDateStr == dayStr;
    }).toList();
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "My Medication Schedule",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2d59f0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Wrap(
              spacing: 4,
              children: [
                _viewChip(CalendarView.month, "Month"),
                _viewChip(CalendarView.week, "Week"),
                _viewChip(CalendarView.day, "Day"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewChip(CalendarView view, String label) {
    final active = _currentView == view;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _currentView = view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2d59f0) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF2d59f0),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    if (_currentView == CalendarView.day) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            DateFormat('EEEE, d MMMM yyyy').format(_selectedDay ?? _focusedDay),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d59f0),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TableCalendar(
        focusedDay: _focusedDay,
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        calendarFormat:
        _currentView == CalendarView.week ? CalendarFormat.week : CalendarFormat.month,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        availableGestures: AvailableGestures.all,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF2d59f0),
          ),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration:
          BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
          selectedDecoration:
          const BoxDecoration(color: Color(0xFF2d59f0), shape: BoxShape.circle),
          outsideDaysVisible: false,
          defaultTextStyle: const TextStyle(color: Colors.black87),
          disabledTextStyle: const TextStyle(color: Colors.grey),
          weekendTextStyle: const TextStyle(color: Colors.black54),
        ),
        enabledDayPredicate: (_) => true,
      ),
    );
  }

  Widget _medCard(Map<String, dynamic> med) {
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now());
    final localKey = '${med['id']}|$selectedDateStr';
    final takenStatus = _localTakenCache.containsKey(localKey)
        ? _localTakenCache[localKey]!
        : (med['taken'] == true);

    const blue = Color(0xFF2d59f0);
    final color = takenStatus ? Colors.green : blue;

    final String? expiryIso =
    (med['expiryDate'] as String?)?.trim().isEmpty == true ? null : med['expiryDate'] as String?;
    final int? remainingPills = med['remainingPills'] is int ? med['remainingPills'] as int : null;
    final bool needsRefill = (remainingPills ?? 9999) <= 5;
    final int? daysToExpiry = _daysLeft(expiryIso);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.white,
          elevation: 2,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),   // smaller right padding => no clip
            childrenPadding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(Icons.medical_services_rounded, color: color, size: 22),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    med['name'] ?? 'Medication',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: takenStatus ? Colors.green[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    takenStatus ? 'Taken' : 'Pending',
                    style: TextStyle(
                      color: takenStatus ? Colors.green[900] : Colors.orange[900],
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  "${med['time'] ?? ''}  •  ${med['dosage'] ?? 'N/A'}",
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    // slight left nudge to avoid any right clipping feel
                    padding: const EdgeInsets.only(right: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown, // keeps them on ONE line by scaling down slightly if needed
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (needsRefill)
                            _infoBadge(
                              icon: Icons.local_pharmacy_outlined,
                              label: 'Refill soon',
                              bg: const Color(0xFFFFE5E5),
                              fg: const Color(0xFFE53935),
                            ),
                          if (needsRefill && daysToExpiry != null && daysToExpiry >= 0 && daysToExpiry <= 30)
                            const SizedBox(width: 8),
                          if (daysToExpiry != null && daysToExpiry >= 0 && daysToExpiry <= 30)
                            _infoBadge(
                              icon: Icons.hourglass_bottom_rounded,
                              label: 'Expires in ${daysToExpiry}d',
                              bg: const Color(0xFFFFF1DB),
                              fg: const Color(0xFFF39C12),
                              dense: !needsRefill,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ----- Expanded content: meta line + 4 action buttons -----
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(med['time'] ?? ''),
                  const Spacer(),
                  const Icon(Icons.repeat, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(med['repeat'] ?? 'Once'),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final double w = (c.maxWidth - 12) / 2; // two per row
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: w, height: 44,
                        child: _pillButton(
                          label: takenStatus ? 'Mark Pending' : 'Mark Taken',
                          icon: takenStatus ? Icons.undo : Icons.check_circle_outline,
                          onTap: () => _toggleTaken(
                            ownerId: med['ownerId'],
                            id: med['id'],
                            current: takenStatus,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: w, height: 44,
                        child: _pillButton(
                          label: 'Delete',
                          icon: Icons.delete_outline,
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                                    SizedBox(width: 10),
                                    Text("Confirm Deletion",
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text('Are you sure you want to delete "${med['name']}"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context, true),
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                                    label: const Text('Delete'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _deleteMed(
                                ownerId: med['ownerId'],
                                id: med['id'],
                                name: med['name'] ?? 'Medication',
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        width: w, height: 44,
                        child: _pillButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditMedicationScreen(
                                  ownerId: med['ownerId'],
                                  medId: med['id'],
                                ),
                              ),
                            );
                            if (mounted) setState(() {}); // refresh after edit
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }


  // =============== Helpers ===============

  // days left until expiry (null if unknown/invalid)
  int? _daysLeft(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final d = DateTime.parse(iso);
      return d.difference(DateTime.now()).inDays;
    } catch (_) {
      return null;
    }
  }

  // small “pill” badge with icon + label (used for Refill / Expires soon)
  Widget _infoBadge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    bool dense = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 14 : 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg, fontWeight: FontWeight.w700, fontSize: dense ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }

  // compact outline button (keeps your theme)
  Widget _pillButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    const blue = Color(0xFF2d59f0);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: blue),
      label: Text(label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: blue, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: blue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2d59f0),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddMedicationScreen(initialDate: _selectedDay ?? _focusedDay),
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 70),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      _buildCalendar(),
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _getMedicationsStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final meds =
                          _filterForDay(snapshot.data!, _selectedDay ?? _focusedDay);
                          if (meds.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Center(
                                child: Text(
                                  "No medications for this day",
                                  style:
                                  TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ),
                            );
                          }
                          return Column(children: meds.map(_medCard).toList());
                        },
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
              const Positioned(top: 10, left: 10, child: BackButtonOverlay()),
            ],
          ),
        ),
      ),
    );
  }
}
