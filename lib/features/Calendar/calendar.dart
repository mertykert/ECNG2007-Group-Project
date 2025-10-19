// lib/features/Calendar/calendar.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:medi_care/widgets/back_button_overlay.dart';
import '../Medication/add_medication.dart';

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

  ///  Helper: Get the current or partner user ID
  Future<String> _getTargetUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc['linkedPartner'];
    return partnerId ?? user.uid;
  }

  ///  Shared meds stream for both caregiver and receiver
  ///  Updated: Stream medications with per-day taken tracking
  Stream<List<Map<String, dynamic>>> _getMedicationsStream() async* {
    final targetUserId = await _getTargetUserId();

    final medsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUserId)
        .collection('medications')
        .snapshots();

    await for (final snap in medsStream) {
      final meds = await Future.wait(snap.docs.map((d) async {
        final data = d.data();
        final medId = d.id;
        final ownerId = targetUserId;

        //  Check if marked taken for selected date
        final dayKey = DateFormat('yyyy-MM-dd')
            .format(_selectedDay ?? DateTime.now());
        final logSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('medications')
            .doc(medId)
            .collection('taken_log')
            .doc(dayKey)
            .get();

        final isTaken = logSnap.exists && (logSnap['taken'] == true);

        return {
          'id': medId,
          'ownerId': ownerId,
          'name': data['name'] ?? 'Unknown',
          'time': data['time'] ?? '',
          'dosage': data['dosage'],
          'repeat': data['repeat'] ?? 'Once',
          'taken': isTaken,
          'date': data['date'] ?? '',
        };
      }).toList());

      yield meds; //  Emit list after processing
    }
  }

  ///  Toggle taken state — syncs for both users
  /// Toggle taken state for a specific date (per-day tracking)
  Future<void> _toggleTaken({
    required String ownerId,
    required String id,
    required bool current,
  }) async {
    final selectedDate = DateFormat('yyyy-MM-dd')
        .format(_selectedDay ?? DateTime.now());
    final localKey = '$id|$selectedDate'; // unique per day

    // ---  Instant visual toggle (optimistic UI) ---
    setState(() {
      _localTakenCache[localKey] = !current;
    });

    // ---  Firestore write ---
    final ownerRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medRef = ownerRef.collection('medications').doc(id);

    try {
      final medSnap = await medRef.get();
      if (!medSnap.exists) return;
      final medData = medSnap.data()!;
      final newStatus = !current;

      // Store taken status for this date only
      await medRef
          .collection('taken_log')
          .doc(selectedDate)
          .set({'taken': newStatus}, SetOptions(merge: true));

      // Mirror to partner (if linked)
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
          await partnerMedRef
              .doc(doc.id)
              .collection('taken_log')
              .doc(selectedDate)
              .set({'taken': newStatus}, SetOptions(merge: true));
        }
      }
    } catch (e) {
      // --- 3️ Rollback if failed ---
      setState(() {
        _localTakenCache.remove(localKey);
      });
    }
  }


  ///  Delete medication — syncs for both users
  Future<void> _deleteMed({
    required String ownerId,
    required String id,
    required String name,
  }) async {
    // Confirm first (nice dialog)
    final ok = await _confirmDelete(name);
    if (ok != true) return;

    final ownerRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medSnap = await ownerRef.collection('medications').doc(id).get();
    if (!medSnap.exists) return;

    final medData = medSnap.data()!;

    // Delete owner’s doc
    await medSnap.reference.delete();

    // Mirror delete to partner if linked
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
          .where('date', isEqualTo: medData['date'])
          .get();

      for (var doc in match.docs) {
        await partnerMedRef.doc(doc.id).delete();
      }
    }

    // Snackbar feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Medication deleted'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _confirmDelete(String medName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
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

  ///  Filter meds per selected day
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

  ///  Header
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

  ///  View selector
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

  ///  Calendar
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

    final format = _currentView == CalendarView.week
        ? CalendarFormat.week
        : CalendarFormat.month;

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
        calendarFormat: format,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        availableGestures: AvailableGestures.all,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF2d59f0),
          ),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Colors.blue.shade100,
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: Color(0xFF2d59f0),
            shape: BoxShape.circle,
          ),
          outsideDaysVisible: false,
        ),
      ),
    );
  }

  ///  Medication card
  Widget _medCard(Map<String, dynamic> med) {
    final selectedDate = DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now());
    final localKey = '${med['id']}|$selectedDate';
    final isTaken = _localTakenCache.containsKey(localKey)
        ? _localTakenCache[localKey]!
        : (med['taken'] == true);
    final themeColor = const Color(0xFF2d59f0);
    final color = isTaken ? Colors.green : themeColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.white,
          elevation: 2,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            childrenPadding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(Icons.medical_services_rounded, color: color, size: 22),
            ),
            title: Text(
              med['name'] ?? 'Medication',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "${med['time'] ?? ''}  •  ${med['dosage'] ?? 'N/A'}",
                style: const TextStyle(color: Colors.black54),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isTaken ? Colors.green[100] : Colors.orange[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isTaken ? 'Taken' : 'Pending',
                style: TextStyle(
                  color: isTaken ? Colors.green[900] : Colors.orange[900],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: themeColor),
                      foregroundColor: themeColor,
                    ),
                    onPressed: () async => _toggleTaken(
                      ownerId: med['ownerId'],     // <-- pass the ownerId
                      id: med['id'],
                      current: isTaken,
                    ),
                    icon: Icon(isTaken ? Icons.undo : Icons.check_circle_outline),
                    label: Text(isTaken ? 'Mark Pending' : 'Mark Taken'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: themeColor),
                      foregroundColor: themeColor,
                    ),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                              SizedBox(width: 10),
                              Text("Confirm Deletion", style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          content: Text(
                            'Are you sure you want to delete "${med['name']}"?',
                            style: const TextStyle(color: Colors.black87, fontSize: 16),
                          ),
                          actionsPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          actions: [
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey[700],
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
                      if (ok == true)  await _deleteMed(
                        ownerId: med['ownerId'],   // <-- pass the ownerId
                        id: med['id'],
                        name: med['name'] ?? 'Medication',
                      );
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: themeColor),
                      foregroundColor: themeColor,
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddMedicationScreen(
                              initialDate: _selectedDay ?? _focusedDay),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  ///  Build UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      body: SafeArea(
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
                        final meds = _filterForDay(
                            snapshot.data!, _selectedDay ?? _focusedDay);
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
                        return Column(
                          children: meds.map(_medCard).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
            const Positioned(top: 10, left: 10, child: BackButtonOverlay()),
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton(
                backgroundColor: const Color(0xFF2d59f0),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddMedicationScreen(
                          initialDate: _selectedDay ?? _focusedDay),
                    ),
                  );
                },
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
