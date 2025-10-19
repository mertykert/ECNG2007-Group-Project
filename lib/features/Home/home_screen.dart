import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:medi_care/features/Calendar/calendar.dart';
import 'package:medi_care/features/Medication/add_medication.dart';
import 'package:medi_care/widgets/link_partner_dialog.dart';
import 'package:rxdart/rxdart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String caregiverName = "Loading...";
  final ValueNotifier<List<double>> weeklyProgressNotifier =
  ValueNotifier(List.filled(7, 0.0));
  final ValueNotifier<double> _todayProgressNotifier = ValueNotifier(0.0);
  StreamSubscription? _medListener;
  Timer? _updateThrottle;

  @override
  void initState() {
    super.initState();
    _loadCaregiverName();
    _setupMedicationsListener();
  }

  @override
  void dispose() {
    _medListener?.cancel();
    weeklyProgressNotifier.dispose();
    _todayProgressNotifier.dispose();
    super.dispose();
  }

  //  Load current user or partner UID
  Future<String> _getTargetUserId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    final doc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    return doc['linkedPartner'] ?? user.uid;
  }

  //  Load user name
  Future<void> _loadCaregiverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      setState(() => caregiverName = doc['name'] ?? 'Caregiver');
    }
  }

  //  Success popup
  Future<void> _showSuccessPopup(String title, String message) async {
    await showDialog(
      context: context,
      builder: (_) =>
          AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(
                16)),
            title: Text(
                title, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(message, textAlign: TextAlign.center),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                    "OK", style: TextStyle(color: Color(0xFF2d59f0))),
              )
            ],
          ),
    );
  }

  //  Confirm delete dialog
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
            Text("Confirm Deletion",
                style: TextStyle(fontWeight: FontWeight.bold)),
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
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  //  Listen for medication updates
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

  //  Merge current user + partner meds for today

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getTodayMedicationsStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc['linkedPartner'];
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> userStream =
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medications')
        .where('date', isEqualTo: today)
        .snapshots()
        .map<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((snap) => snap.docs);

    if (partnerId == null || partnerId.toString().isEmpty) {
      yield* userStream;
      return;
    }

    final Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> partnerStream =
    FirebaseFirestore.instance
        .collection('users')
        .doc(partnerId)
        .collection('medications')
        .where('date', isEqualTo: today)
        .snapshots()
        .map<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((snap) => snap.docs);

    // Merge user + partner and remove duplicates based on name+time+date
    yield* Rx.combineLatest2<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>,
        List<QueryDocumentSnapshot<Map<String, dynamic>>>,
        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      userStream,
      partnerStream,
          (a, b) {
        final combined = [...a, ...b];
        final uniqueMap = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

        for (var doc in combined) {
          final data = doc.data();
          final key =
              "${data['name'] ?? ''}_${data['time'] ?? ''}_${data['date'] ?? ''}";
          uniqueMap[key] = doc; // overwrite duplicates
        }

        return uniqueMap.values.toList();
      },
    );
  }



  //  Toggle taken status
  Future<void> _markAsTaken(String ownerId, String id, bool currentStatus) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medSnap = await userRef.collection('medications').doc(id).get();
    if (!medSnap.exists) return;

    final medData = medSnap.data()!;
    final newStatus = !currentStatus;

    // update current owner's medication
    await medSnap.reference.update({'taken': newStatus});

    //  find linked partner
    final ownerDoc = await FirebaseFirestore.instance.collection('users').doc(ownerId).get();
    final partnerId = ownerDoc['linkedPartner'];
    if (partnerId == null || partnerId.toString().isEmpty) return;

    // find partner’s matching medication (same name, time, and date)
    final partnerRef = FirebaseFirestore.instance
        .collection('users')
        .doc(partnerId)
        .collection('medications');

    final match = await partnerRef
        .where('name', isEqualTo: medData['name'])
        .where('time', isEqualTo: medData['time'])
        .where('date', isEqualTo: medData['date'])
        .get();

    for (var doc in match.docs) {
      await doc.reference.update({'taken': newStatus});
    }

    _loadTodayProgress(ownerId);
    setState(() {});
  }


  //  Delete medication
  Future<void> _deleteMedication(String ownerId, String id) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(ownerId);
    final medSnap = await userRef.collection('medications').doc(id).get();
    if (!medSnap.exists) return;

    final medData = medSnap.data()!;
    final medName = medData['name'] ?? 'Medication';

    await medSnap.reference.delete();

    //  also delete from linked partner
    final ownerDoc = await FirebaseFirestore.instance.collection('users').doc(ownerId).get();
    final partnerId = ownerDoc['linkedPartner'];
    if (partnerId != null && partnerId.toString().isNotEmpty) {
      final partnerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .collection('medications');

      final match = await partnerRef
          .where('name', isEqualTo: medData['name'])
          .where('time', isEqualTo: medData['time'])
          .where('date', isEqualTo: medData['date'])
          .get();

      for (var doc in match.docs) {
        await doc.reference.delete();
      }
    }

    //  show a styled snackbar after delete
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '"$medName" deleted successfully',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }


  //  Load today's progress
  Future<void> _loadTodayProgress(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc['linkedPartner'];
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    List<QuerySnapshot> results = [];

    results.add(await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medications')
        .where('date', isEqualTo: today)
        .get());

    if (partnerId != null && partnerId
        .toString()
        .isNotEmpty) {
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
    } else {
      final total = allDocs.length;
      final taken = allDocs
          .where((d) => d['taken'] == true)
          .length;
      _todayProgressNotifier.value = taken / total;
    }
  }

  //  Load weekly progress
  Future<void> _loadWeeklyProgress(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc['linkedPartner'];
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    List<double> progress = [];

    for (int i = 0; i < 7; i++) {
      final dateStr =
      DateFormat('yyyy-MM-dd').format(startOfWeek.add(Duration(days: i)));
      List<QuerySnapshot> results = [];

      results.add(await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medications')
          .where('date', isEqualTo: dateStr)
          .get());

      if (partnerId != null && partnerId
          .toString()
          .isNotEmpty) {
        results.add(await FirebaseFirestore.instance
            .collection('users')
            .doc(partnerId)
            .collection('medications')
            .where('date', isEqualTo: dateStr)
            .get());
      }

      final allDocs = results.expand((r) => r.docs).toList();
      if (allDocs.isEmpty) {
        progress.add(0.0);
      } else {
        final total = allDocs.length;
        final taken = allDocs
            .where((d) => d['taken'] == true)
            .length;
        progress.add(taken / total);
      }
    }

    weeklyProgressNotifier.value = progress;
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final hour = DateTime
        .now()
        .hour;
    String greeting;
    IconData greetingIcon;
    if (hour < 12) {
      greeting = "Good Morning";
      greetingIcon = Icons.wb_sunny_rounded;
    } else if (hour < 18) {
      greeting = "Good Afternoon";
      greetingIcon = Icons.wb_cloudy_rounded;
    } else {
      greeting = "Good Evening";
      greetingIcon = Icons.nightlight_round;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildSidebar(context),
      body: SafeArea(
      child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Modern Header ---
              // --- Simple Clean Header (icons swapped) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 👈 Drawer Menu (left)
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(
                        Icons.menu_rounded,
                        color: Color(0xFF2d59f0),
                        size: 28,
                      ),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),

                  // 👉 Greeting & Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          caregiverName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ☀️ Greeting Icon on the far right
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d59f0).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      greetingIcon,
                      color: const Color(0xFF2d59f0),
                      size: 22,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),
              ValueListenableBuilder<List<double>>(
                valueListenable: weeklyProgressNotifier,
                builder: (context, weeklyProgress, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Summary Card ---
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2d59f0),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ValueListenableBuilder<double>(
                          valueListenable: _todayProgressNotifier,
                          builder: (context, todayProgress, _) {
                            final percentage =
                            (todayProgress * 100).clamp(0, 100).toStringAsFixed(
                                0);
                            return Column(
                              children: [
                                Text("Pills Taken: $percentage%",
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: todayProgress,
                                    color: Colors.white,
                                    backgroundColor: Colors.white30,
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 25),

                      const Text("Weekly Progress",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      _buildProgressGraph(),
                      const SizedBox(height: 25),

                      Row(
                        children: [
                          Expanded(
                            child: _modernButton("Add Medication",
                                Icons.add_circle_outline, onTap: () async {
                                  final added = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (
                                            _) => const AddMedicationScreen()),
                                  );
                                  if (added == true && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: const [
                                            Icon(Icons.check_circle, color: Colors.white),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                "Medication added successfully!",
                                                style: TextStyle(fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: const Color(0xFF2d59f0),
                                        behavior: SnackBarBehavior.floating,
                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                }),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _modernButton("View Schedule",
                                Icons.calendar_today_outlined, onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const SchedulePage()),
                                  );
                                }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),

                      const Text("Today's Medications",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
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

                          final meds = snapshot.data!; // List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          if (meds.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  "No medications added yet.",
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
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
                              childAspectRatio: 0.9,
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
    );
  }

  Widget _buildProgressGraph() {
    return ValueListenableBuilder<List<double>>(
      valueListenable: weeklyProgressNotifier,
      builder: (context, weeklyProgress, _) {
        return Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 6,
              minY: 0,
              maxY: 1,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (x, _) {
                      const days = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ];
                      if (x.toInt() < 0 || x.toInt() > 6)
                        return const SizedBox();
                      return Text(days[x.toInt()],
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500));
                    },
                  ),
                ),
                leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: const Color(0xFF2d59f0),
                  barWidth: 4,
                  spots: List.generate(
                      7, (i) => FlSpot(i.toDouble(), weeklyProgress[i])),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF2d59f0).withOpacity(0.25),
                        Colors.transparent
                      ],
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

  Widget _modernButton(String label, IconData icon,
      {required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 15)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2d59f0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 3,
      ),
    );
  }

  Widget _modernMedicationCard(Map<String, dynamic> med) {
    final bool isTaken = med['taken'] ?? false;
    final String name = med['name'] ?? 'Unknown';
    final String time = med['time'] ?? 'Unknown';
    final String id = med['id'];
    final String owner = med['owner'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                (isTaken ? Colors.green : const Color(0xFF2d59f0))
                    .withOpacity(0.12),
                child: Icon(Icons.medical_services_rounded,
                    color: isTaken
                        ? Colors.green
                        : const Color(0xFF2d59f0),
                    size: 22),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
                onPressed: () async {
                  final ok = await _confirmDelete(name);
                  if (ok) await _deleteMedication(owner, id);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 4),
          Text(time,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              HapticFeedback.selectionClick();
              _markAsTaken(owner, id, isTaken);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isTaken
                    ? Colors.green.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isTaken ? 'Taken' : 'Pending',
                style: TextStyle(
                  color:
                  isTaken ? Colors.green.shade700 : Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    const blue = Color(0xFF2d59f0);

    return Drawer(
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      backgroundColor: Colors.transparent, // 👈 make it transparent
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), // 👈 frosted blur
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8), // translucent white
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 25,
                  offset: const Offset(4, 4),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.8),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Profile Header ---
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                blue.withOpacity(0.85),
                                blue.withOpacity(0.65)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: blue.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(10),
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            caregiverName,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Divider(color: Colors.blue.shade100, thickness: 1),

                    // --- Sidebar Items ---
                    _modernSidebarItem(
                      icon: Icons.qr_code_2_rounded,
                      label: "View Partner Code",
                      color: blue,
                      onTap: () async {
                        Navigator.pop(context);
                        final doc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user!.uid)
                            .get();
                        final code = doc['partnerCode'] ?? 'N/A';
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: const Text("Your Partner Code",
                                style: TextStyle(fontWeight: FontWeight.bold)),
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
                                    const SnackBar(
                                        content: Text("Partner code copied")),
                                  );
                                },
                                child: const Text("Copy",
                                    style: TextStyle(color: blue)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Close",
                                    style: TextStyle(color: blue)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    _modernSidebarItem(
                      icon: Icons.person_add_alt_1_rounded,
                      label: "Link Partner",
                      color: blue,
                      onTap: () {
                        Navigator.pop(context);
                        showDialog(
                            context: context,
                            builder: (_) => const LinkPartnerDialog());
                      },
                    ),
                    _modernSidebarItem(
                      icon: Icons.link_off_rounded,
                      label: "Unlink Partner",
                      color: blue,
                      onTap: () async {
                        Navigator.pop(context);
                        // existing unlink code here...
                      },
                    ),

                    Divider(color: Colors.blue.shade100, thickness: 1),
                    const SizedBox(height: 10),

                    _modernSidebarItem(
                      icon: Icons.switch_account_rounded,
                      label: "Switch Account",
                      color: blue,
                      onTap: () async {
                        Navigator.pop(context);
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, "/signin");
                        }
                      },
                    ),
                    _modernSidebarItem(
                      icon: Icons.logout_rounded,
                      label: "Log Out",
                      color: Colors.redAccent,
                      onTap: () async {
                        Navigator.pop(context);
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, "/welcome");
                        }
                      },
                    ),

                    const Spacer(),
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        "MediCare v1.0",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modernSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = const Color(0xFF2d59f0),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: color.withOpacity(0.12),
      highlightColor: color.withOpacity(0.08),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
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
}
