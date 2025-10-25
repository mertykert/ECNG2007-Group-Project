import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MissedCountsChips extends StatelessWidget {
  const MissedCountsChips({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _MissedChip(period: _MissedPeriod.today)),
        SizedBox(width: 8),
        Expanded(child: _MissedChip(period: _MissedPeriod.week)),
        SizedBox(width: 8),
        Expanded(child: _MissedChip(period: _MissedPeriod.month)),
      ],
    );
  }
}

enum _MissedPeriod { today, week, month }

class _MissedChip extends StatelessWidget {
  const _MissedChip({required this.period});
  final _MissedPeriod period;

  @override
  Widget build(BuildContext context) {
    final range = _rangeForPeriod(period);

    return StreamBuilder<int>(
      stream: _missedCountStream(range.start, range.end),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        final label = period == _MissedPeriod.today
            ? 'Today'
            : period == _MissedPeriod.week
            ? 'Week'
            : 'Month';

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showMissedList(context, period, range),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$label:',
                    style: const TextStyle(
                        color: Color(0xFF2d59f0),
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2d59f0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

DateTimeRange _rangeForPeriod(_MissedPeriod p) {
  final now = DateTime.now();
  if (p == _MissedPeriod.today) {
    final start = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: start, end: start.add(const Duration(days: 1)));
  } else if (p == _MissedPeriod.week) {
    final start = now.subtract(Duration(days: now.weekday - 1));
    return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
  } else {
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return DateTimeRange(start: start, end: end);
  }
}

Stream<int> _missedCountStream(DateTime start, DateTime end) async* {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) yield 0;

  final uid = user?.uid;
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('missed');

  yield* ref.snapshots().map((snap) {
    int total = 0;
    for (final doc in snap.docs) {
      final date = DateFormat('yyyy-MM-dd').parse(doc.id);
      if (date.isAfter(start.subtract(const Duration(seconds: 1))) &&
          date.isBefore(end)) {
        final meds = (doc.data()['meds'] as List?) ?? [];
        total += meds.length;
      }
    }
    return total;
  });
}

void _showMissedList(
    BuildContext context, _MissedPeriod period, DateTimeRange range) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) {
      final title = period == _MissedPeriod.today
          ? 'Missed • Today'
          : period == _MissedPeriod.week
          ? 'Missed • This Week'
          : 'Missed • This Month';

      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection('missed')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = <Map<String, dynamic>>[];
          for (final doc in snap.data!.docs) {
            final date = DateFormat('yyyy-MM-dd').parse(doc.id);
            if (date.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
                date.isBefore(range.end)) {
              final meds = (doc['meds'] as List?) ?? [];
              for (final m in meds) {
                items.add({'name': m['name'], 'time': m['time'], 'date': doc.id});
              }
            }
          }

          items.sort((a, b) => b['date'].compareTo(a['date']));

          return SizedBox(
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                  const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No missed doses',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                      : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(items[i]['name'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${items[i]['time'] ?? ''} • ${items[i]['date']}'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
