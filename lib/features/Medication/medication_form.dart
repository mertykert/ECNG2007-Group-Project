// ============================================================================
// lib/features/Medication/medication_form.dart
// Adds canonical 24h time "time24" alongside the display "time".
// UI unchanged.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:medi_care/services/med_reminder_scheduler.dart';
import '../../analytics/analytics_service.dart';
import '../../widgets/back_button_overlay.dart';
import '../../services/notification_service.dart';
import '../../services/refill_service.dart';

enum MedicationFormMode { add, edit }

class MedicationForm extends StatefulWidget {
  final MedicationFormMode mode;
  final DateTime? initialDate;
  final String? ownerId;
  final String? medId;

  const MedicationForm({
    super.key,
    required this.mode,
    this.initialDate,
    this.ownerId,
    this.medId,
  });

  @override
  State<MedicationForm> createState() => _MedicationFormState();
}

class _MedicationFormState extends State<MedicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();

  bool _dosageError = false;

  TimeOfDay? _selectedTime;
  String _repeat = 'Once';
  bool _taken = false;

  bool _loading = false;
  Map<String, dynamic>? _existingDoc;

  DateTime get _targetDate {
    if (widget.mode == MedicationFormMode.edit && _existingDoc != null) {
      final ds = (_existingDoc!['date'] ?? '') as String;
      if (ds.isNotEmpty) {
        return DateTime.tryParse(ds) ?? DateUtils.dateOnly(DateTime.now());
      }
    }
    return DateUtils.dateOnly(widget.initialDate ?? DateTime.now());
  }

  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay? _parseUiTime(String raw) {
    final s = raw.replaceAll('\u202F', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    try {
      final dt = DateFormat.jm().parse(s);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      try {
        final p = s.split(':');
        final h = int.parse(p[0]);
        final m = p.length > 1 ? int.parse(p[1]) : 0;
        if (h >= 0 && h < 24 && m >= 0 && m < 60) {
          return TimeOfDay(hour: h, minute: m);
        }
      } catch (_) {}
    }
    return null;
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    if (widget.mode == MedicationFormMode.edit) {
      _prefillForEdit();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _expiryCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillForEdit() async {
    setState(() => _loading = true);
    try {
      final ownerId = widget.ownerId ?? FirebaseAuth.instance.currentUser?.uid;
      if (ownerId == null || widget.medId == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .collection('medications')
          .doc(widget.medId!)
          .get();
      if (!snap.exists) return;

      _existingDoc = snap.data();
      final data = _existingDoc!;

      _nameCtrl.text   = (data['name'] ?? '').toString();
      _dosageCtrl.text = (data['dosage'] ?? '').toString();
      _expiryCtrl.text = (data['expiryDate'] ?? '').toString();
      _totalCtrl.text  = _asInt(data['totalPills']).toString();
      _taken           = data['taken'] == true;
      _repeat          = (data['repeat'] ?? 'Once').toString();

      // Prefer time24 → zero parsing failures
      final time24 = (data['time24'] ?? '').toString().trim();
      final timeStr = (data['time'] ?? '').toString();

      if (time24.isNotEmpty) {
        final parts = time24.split(':');
        final h = int.tryParse(parts.elementAt(0));
        final m = int.tryParse(parts.elementAt(1));
        if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
          _selectedTime = TimeOfDay(hour: h, minute: m);
        }
      }
      if (_selectedTime == null && timeStr.isNotEmpty) {
        _selectedTime = _parseUiTime(timeStr);
      }

      setState(() {});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _doneButton(VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2d59f0),
        foregroundColor: Colors.white,
        minimumSize: const Size(140, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 4,
      ),
      onPressed: onPressed,
      child: const Text("Done", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _pickTime() async {
    TimeOfDay temp = _selectedTime ?? TimeOfDay.now();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 340,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 50, height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text("Select Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      initialDateTime: DateTime(
                        DateTime.now().year, DateTime.now().month, DateTime.now().day,
                        temp.hour, temp.minute,
                      ),
                      onDateTimeChanged: (v) {
                        temp = TimeOfDay(hour: v.hour, minute: v.minute);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2d59f0),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 4,
                  ),
                  onPressed: () {
                    setState(() => _selectedTime = temp);
                    Navigator.pop(context);
                  },
                  child: const Text("Done", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDosagePicker() {
    int quantity = 1;
    int strength = 5;
    String unit = "tablet(s)";
    final units = ["tablet(s)", "capsule(s)", "ml", "drop(s)"];
    final strengths = [5, 10, 25, 50, 100, 250, 500];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SizedBox(
                height: 340,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 50, height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text("Select Dosage",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              magnification: 1.3, squeeze: 1.1, diameterRatio: 1.2, itemExtent: 42,
                              scrollController: FixedExtentScrollController(initialItem: 0),
                              selectionOverlay: _greyOverlay(),
                              onSelectedItemChanged: (i) => setModalState(() => quantity = i + 1),
                              children: List.generate(
                                10,
                                    (i) => Center(
                                  child: Text("${i + 1}",
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87)),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              magnification: 1.3, squeeze: 1.1, diameterRatio: 1.2, itemExtent: 42,
                              selectionOverlay: _greyOverlay(),
                              onSelectedItemChanged: (i) => setModalState(() => unit = units[i]),
                              children: units
                                  .map((u) => Center(
                                child: Text(u,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87)),
                              ))
                                  .toList(),
                            ),
                          ),
                          if (unit.contains("tablet") || unit.contains("capsule"))
                            Expanded(
                              child: CupertinoPicker(
                                magnification: 1.3, squeeze: 1.1, diameterRatio: 1.2, itemExtent: 42,
                                selectionOverlay: _greyOverlay(),
                                onSelectedItemChanged: (i) => setModalState(() => strength = strengths[i]),
                                children: strengths
                                    .map((mg) => Center(
                                  child: Text("$mg mg each",
                                      style: const TextStyle(
                                          fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87)),
                                ))
                                    .toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2d59f0),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(140, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 4,
                      ),
                      onPressed: () {
                        String dosage;
                        if (unit.contains("tablet") || unit.contains("capsule")) {
                          dosage = "$quantity $unit ($strength mg each)";
                        } else {
                          dosage = "$quantity $unit";
                        }
                        setState(() {
                          _dosageCtrl.text = dosage;
                          _dosageError = false;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text("Done", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickRepeat() async {
    final repeats = ["Once", "Daily", "Weekly"];
    int selected = repeats.indexOf(_repeat);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: 320,
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Column(
                children: [
                  Container(
                    width: 50, height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("Repeat Frequency", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CupertinoPicker(
                      magnification: 1.2, itemExtent: 42,
                      scrollController: FixedExtentScrollController(initialItem: selected),
                      onSelectedItemChanged: (i) => setModalState(() => selected = i),
                      selectionOverlay: _greyOverlay(),
                      children: repeats.map((r) => Center(child: Text(r, style: const TextStyle(fontSize: 18)))).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _doneButton(() {
                    setState(() => _repeat = repeats[selected]);
                    Navigator.pop(context);
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _greyOverlay() {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: Colors.blue.shade300.withOpacity(0.8), width: 2),
        ),
      ),
    );
  }

  int _extractPillCountFromDosage(String dosageText) {
    final match = RegExp(r'(\d+)').firstMatch(dosageText);
    return match != null ? int.parse(match.group(1)!) : 1;
  }

  Future<void> _cancelLocalNotificationsFrom(Map<String, dynamic>? ids) async {
    if (ids == null) return;
    try {
      final reminder = ids['reminder'];
      final expiry = ids['expiry'];
      if (reminder is int) await NotificationService.cancel(reminder);
      if (expiry is int) await NotificationService.cancel(expiry);
    } catch (_) {}
  }

  Future<Map<String, int>> _scheduleNotifications({
    required String name,
    required String dosage,
    required String repeat,
    required DateTime anchorDate,
    required TimeOfDay timeOfDay,
    String? expiryDateText,
  }) async {
    final ids = <String, int>{};
    final firstTrigger = DateTime(
      anchorDate.year, anchorDate.month, anchorDate.day,
      timeOfDay.hour, timeOfDay.minute,
    );

    final title = "Time to take $name";
    final body  = "Dosage: $dosage";

    if (repeat == 'Once') {
      final now = DateTime.now();
      final when = firstTrigger.isAfter(now) ? firstTrigger : firstTrigger.add(const Duration(days: 1));
      ids['reminder'] = await NotificationService.scheduleOnce(when, title, body);
    } else if (repeat == 'Daily') {
      ids['reminder'] = await NotificationService.scheduleDaily(firstTrigger, title, body);
    } else {
      ids['reminder'] = await NotificationService.scheduleWeekly(firstTrigger, title, body);
    }

    // Expiry notifications intentionally omitted per your requirement.
    return ids;
  }

  // Replace your _saveMedication() with this version (only diffs are the refill bits).
  Future<void> _saveMedication() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_dosageCtrl.text.isEmpty) {
      setState(() => _dosageError = true);
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a time')));
      return;
    }

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final ownerId = widget.ownerId ?? user?.uid;
      if (ownerId == null) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(ownerId);

      final dateStr  = DateFormat('yyyy-MM-dd').format(_targetDate);
      final timeStr  = _selectedTime!.format(context);
      final time24   = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
      final total    = int.tryParse(_totalCtrl.text.trim()) ?? 0;
      final perDose  = _extractPillCountFromDosage(_dosageCtrl.text);

      if (widget.mode == MedicationFormMode.add) {
        // ---------- ADD ----------
        final base = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'dosage': _dosageCtrl.text.trim(),
          'time': timeStr,
          'time24': time24,     // canonical
          'repeat': _repeat,
          'taken': _taken,
          'date': dateStr,
          'createdAt': FieldValue.serverTimestamp(),
          'ownerUid': ownerId,
          'addedBy': ownerId,
          'expiryDate': _expiryCtrl.text.trim(),
          'totalPills': total,
          'perDose': perDose,
          'remainingPills': total,    // start full
          'lowStockNotified': false,
        };

        // ✅ compute & merge refill fields (needsRefill, threshold, etc.)
        final payload = {...base, ...RefillService.computeRefillPatch(base)};

        final medRef = await userRef.collection('medications').add(payload);

        // Single source of truth for alarms
        await MedReminderScheduler.scheduleForMed(
          uid: ownerId,
          medId: medRef.id,
          medData: {
            'name': _nameCtrl.text.trim(),
            'time': timeStr,
            'time24': time24,
            'repeat': _repeat,
            'date': dateStr,
            'expiryDate': _expiryCtrl.text.trim(),
          },
        );

        await RefillService.checkOne(ownerId, medRef.id);

        if (!mounted) return;
        await AppAnalytics.logMedicationAdded(
          ownerUid: ownerId,
          repeat: (payload['repeat'] as String?) ?? 'Once',
        );
        _showOk("Medication added successfully!");
        if (Navigator.canPop(context)) Navigator.pop(context, true);

        _nameCtrl.clear();
        _dosageCtrl.clear();
        _expiryCtrl.clear();
        _totalCtrl.clear();
      } else {
        // ---------- EDIT ----------
        if (widget.medId == null) return;
        final docRef = userRef.collection('medications').doc(widget.medId!);
        final snap = await docRef.get();
        if (!snap.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medication not found')));
          return;
        }
        final old = snap.data()!;

        // Cancel previous timers before re-schedule
        await MedReminderScheduler.cancelTimersForMed(ownerId, widget.medId!);

        final oldTotal = (old['totalPills'] ?? 0) as int;
        final oldRemaining = (old['remainingPills'] ?? oldTotal) as int;
        final newTotal = int.tryParse(_totalCtrl.text.trim()) ?? oldTotal;

        // ✅ If total increased, treat as a refill: reset remaining to newTotal.
        // Else clamp remaining within [0, newTotal].
        int newRemaining;
        if (newTotal > oldTotal) {
          newRemaining = newTotal;
        } else {
          newRemaining = oldRemaining.clamp(0, newTotal);
        }

        final baseUpdate = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'dosage': _dosageCtrl.text.trim(),
          'time': timeStr,
          'time24': time24,
          'repeat': _repeat,
          'taken': _taken,
          'date': dateStr,
          'ownerUid': ownerId,
          'expiryDate': _expiryCtrl.text.trim(),
          'totalPills': newTotal,
          'perDose': perDose,
          'remainingPills': newRemaining,
          // do not blindly carry old lowStockNotified; compute again below
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // ✅ recompute refill fields from new totals/remaining
        final refillPatch = RefillService.computeRefillPatch({
          'totalPills': newTotal,
          'remainingPills': newRemaining,
          'refillThreshold': old['refillThreshold'],
        });

        await docRef.set({...baseUpdate, ...refillPatch}, SetOptions(merge: true));

        // Re-schedule with new time/repeat
        await MedReminderScheduler.scheduleForMed(
          uid: ownerId,
          medId: widget.medId!,
          medData: {
            'name': _nameCtrl.text.trim(),
            'time': timeStr,
            'time24': time24,
            'repeat': _repeat,
            'date': dateStr,
            'expiryDate': _expiryCtrl.text.trim(),
          },
        );

        await RefillService.checkOne(ownerId, widget.medId!);

        if (!mounted) return;
        _showOk("Medication updated.");
        if (Navigator.canPop(context)) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showOk(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Medication saved successfully!",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2d59f0),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
        elevation: 3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prettyDate = DateFormat('EEE, d MMM').format(_targetDate);
    final title = widget.mode == MedicationFormMode.add ? "Add Medication" : "Edit Medication";

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      body: SafeArea(
        child: Stack(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 20, right: 20,
                top: 12,
                bottom: (MediaQuery.of(context).viewInsets.bottom > 0
                    ? MediaQuery.of(context).viewInsets.bottom + 12
                    : 24),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 60),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2d59f0),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/schedule'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              prettyDate,
                              style: const TextStyle(
                                color: Color(0xFF2d59f0), fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    _inputCard(
                      child: Row(
                        children: [
                          const Icon(Icons.medication_outlined, color: Colors.black54),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _nameCtrl,
                              style: const TextStyle(fontSize: 16, color: Colors.black87),
                              decoration: const InputDecoration(
                                hintText: "Medication Name",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? "Enter a medication name" : null,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _showDosagePicker,
                      child: _inputCard(
                        child: Row(
                          children: [
                            Icon(Icons.health_and_safety_outlined,
                                color: _dosageError ? Colors.redAccent : Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _dosageCtrl.text.isEmpty ? "Select Dosage" : _dosageCtrl.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _dosageCtrl.text.isEmpty
                                      ? (_dosageError ? Colors.redAccent : Colors.grey)
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                          ],
                        ),
                      ),
                    ),
                    if (_dosageError)
                      const Padding(
                        padding: EdgeInsets.only(left: 14, top: 4),
                        child: Text("Required field", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _pickTime,
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_outlined, color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedTime == null ? "Select Time" : _selectedTime!.format(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _selectedTime == null ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _pickRepeat,
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.repeat, color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _repeat,
                                style: const TextStyle(
                                  fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: () async {
                        final today = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: today,
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 365 * 5)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Color(0xFF2d59f0),
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black87,
                                ),
                                dialogBackgroundColor: Colors.white,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _expiryCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                          });
                        }
                      },
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _expiryCtrl.text.isEmpty ? "Select Expiry Date" : _expiryCtrl.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _expiryCtrl.text.isEmpty ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: () async {
                        final selected = await showModalBottomSheet<int>(
                          context: context,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (context) {
                            int current = int.tryParse(_totalCtrl.text) ?? 10;
                            return SizedBox(
                              height: 250,
                              child: Column(
                                children: [
                                  const SizedBox(height: 10),
                                  const Text("Select Total Pills",
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: CupertinoPicker(
                                      scrollController: FixedExtentScrollController(initialItem: (current - 1).clamp(0, 99)),
                                      itemExtent: 40,
                                      onSelectedItemChanged: (i) => current = i + 1,
                                      children: List.generate(
                                        100,
                                            (i) => Center(
                                          child: Text("${i + 1} pills", style: const TextStyle(fontSize: 18)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, current),
                                    child: const Text("Done",
                                        style: TextStyle(fontSize: 16, color: Color(0xFF2d59f0))),
                                  )
                                ],
                              ),
                            );
                          },
                        );
                        if (selected != null) setState(() => _totalCtrl.text = selected.toString());
                      },
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.format_list_numbered_rounded, color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _totalCtrl.text.isEmpty ? "Total Pills" : "${_totalCtrl.text} pills",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _totalCtrl.text.isEmpty ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Checkbox(
                          value: _taken,
                          activeColor: const Color(0xFF2d59f0),
                          onChanged: (v) => setState(() => _taken = v ?? false),
                        ),
                        const Text("Already taken", style: TextStyle(fontSize: 15)),
                      ],
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity, height: 56,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveMedication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2d59f0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 5,
                        ),
                        child: Text(
                          widget.mode == MedicationFormMode.add ? "Save Medication" : "Save Changes",
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            const Positioned(top: 24, left: 16, child: BackButtonOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _inputCard({required Widget child}) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
