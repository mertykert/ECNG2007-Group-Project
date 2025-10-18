import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:medi_care/widgets/back_button_overlay.dart';

class AddMedicationScreen extends StatefulWidget {
  final DateTime? initialDate;
  const AddMedicationScreen({super.key, this.initialDate});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  TimeOfDay? _selectedTime;
  String _repeat = 'Once';
  bool _taken = false;

  DateTime get _targetDate =>
      DateUtils.dateOnly(widget.initialDate ?? DateTime.now());

  // ---------- UNIVERSAL DONE BUTTON ----------
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
      child: const Text(
        "Done",
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ---------- TIME PICKER ----------
  Future<void> _pickTime() async {
    TimeOfDay temp = _selectedTime ?? TimeOfDay.now();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 340,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Select Time",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      initialDateTime: DateTime.now(),
                      onDateTimeChanged: (v) {
                        temp = TimeOfDay(hour: v.hour, minute: v.minute);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _doneButton(() {
                  setState(() => _selectedTime = temp);
                  Navigator.pop(context);
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- SMART DOSAGE PICKER ----------
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              height: 340,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Select Dosage",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Quantity picker
                        Expanded(
                          child: CupertinoPicker(
                            magnification: 1.2,
                            itemExtent: 42,
                            onSelectedItemChanged: (i) =>
                                setModalState(() => quantity = i + 1),
                            selectionOverlay: _blueOverlay(),
                            children: List.generate(
                                10,
                                    (i) => Center(
                                    child: Text("${i + 1}",
                                        style: const TextStyle(fontSize: 18)))),
                          ),
                        ),
                        // Unit picker
                        Expanded(
                          child: CupertinoPicker(
                            magnification: 1.2,
                            itemExtent: 42,
                            onSelectedItemChanged: (i) =>
                                setModalState(() => unit = units[i]),
                            selectionOverlay: _blueOverlay(),
                            children: units
                                .map((u) => Center(
                                child: Text(u,
                                    style:
                                    const TextStyle(fontSize: 18))))
                                .toList(),
                          ),
                        ),
                        // Strength picker (only for tablets/capsules)
                        if (unit.contains("tablet") || unit.contains("capsule"))
                          Expanded(
                            child: CupertinoPicker(
                              magnification: 1.2,
                              itemExtent: 42,
                              onSelectedItemChanged: (i) =>
                                  setModalState(() => strength = strengths[i]),
                              selectionOverlay: _blueOverlay(),
                              children: strengths
                                  .map((mg) => Center(
                                  child: Text("$mg mg each",
                                      style: const TextStyle(
                                          fontSize: 18))))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _doneButton(() {
                    String dosage;
                    if (unit.contains("tablet") || unit.contains("capsule")) {
                      dosage = "$quantity $unit ($strength mg each)";
                    } else {
                      dosage = "$quantity $unit";
                    }
                    setState(() => _dosageCtrl.text = dosage);
                    Navigator.pop(context);
                  }),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- REPEAT PICKER ----------
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
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Repeat Frequency",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CupertinoPicker(
                      magnification: 1.2,
                      itemExtent: 42,
                      scrollController:
                      FixedExtentScrollController(initialItem: selected),
                      onSelectedItemChanged: (i) =>
                          setModalState(() => selected = i),
                      selectionOverlay: _blueOverlay(),
                      children: repeats
                          .map((r) => Center(
                          child: Text(r,
                              style: const TextStyle(fontSize: 18))))
                          .toList(),
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

  // ---------- COMMON OVERLAY ----------
  Widget _blueOverlay() {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal:
          BorderSide(color: Colors.blue.shade300.withOpacity(0.8), width: 2),
        ),
      ),
    );
  }

  // ---------- SAVE ----------
  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate() || _selectedTime == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final partnerId = userDoc.data()?['linkedPartner'];

    final medicationData = {
      'name': _nameCtrl.text.trim(),
      'dosage': _dosageCtrl.text.trim(),
      'time': _selectedTime!.format(context),
      'repeat': _repeat,
      'taken': _taken,
      'date': DateFormat('yyyy-MM-dd').format(_targetDate),
      'createdAt': FieldValue.serverTimestamp(),
      'addedBy': user.uid, // Optional – helps track who added it
    };

    // Save for current user
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medications')
        .add(medicationData);

    //  Also save for linked partner (if exists)
    if (partnerId != null && partnerId.toString().isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .collection('medications')
          .add(medicationData);
    }

    // ---------- ADD TO CALENDAR ----------
    final eventData = {
      'title': 'Take ${_nameCtrl.text.trim()}',
      'time': _selectedTime!.format(context),
      'date': DateFormat('yyyy-MM-dd').format(_targetDate),
      'repeat': _repeat,
      'linkedMed': _nameCtrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Save for current user
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar')
        .add(eventData);

    // Also save for linked partner
    if (partnerId != null && partnerId.toString().isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(partnerId)
          .collection('calendar')
          .add(eventData);
    }


    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final prettyDate = DateFormat('EEE, d MMM').format(_targetDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 200,
                top: 16,
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
                        const Text(
                          "Add Medication",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2d59f0),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            prettyDate,
                            style: const TextStyle(
                              color: Color(0xFF2d59f0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    _inputCard(
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Medication Name",
                          prefixIcon: Icon(Icons.medication_outlined),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                        validator: (v) =>
                        v!.isEmpty ? "Enter a medication name" : null,
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _showDosagePicker,
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.health_and_safety_outlined,
                                color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _dosageCtrl.text.isEmpty
                                    ? "Select Dosage"
                                    : _dosageCtrl.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _dosageCtrl.text.isEmpty
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.black45),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _pickTime,
                      child: _inputCard(
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_outlined,
                                color: Colors.black54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedTime == null
                                    ? "Select Time"
                                    : _selectedTime!.format(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _selectedTime == null
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.black45),
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
                                  fontSize: 16,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.black45),
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
                          onChanged: (v) =>
                              setState(() => _taken = v ?? false),
                        ),
                        const Text("Already taken",
                            style: TextStyle(fontSize: 15)),
                      ],
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saveMedication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2d59f0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          "Save Medication",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
            const BackButtonOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _inputCard({required Widget child}) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
