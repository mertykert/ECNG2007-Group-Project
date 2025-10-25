import 'package:flutter/material.dart';

class MedStatusBadges extends StatelessWidget {
  final String? expiryDate;          // ISO yyyy-MM-dd or null
  final int? remainingPills;         // null if unknown
  final bool dense;                  // smaller in Schedule, normal on Home
  final EdgeInsetsGeometry margin;

  const MedStatusBadges({
    super.key,
    this.expiryDate,
    this.remainingPills,
    this.dense = false,
    this.margin = const EdgeInsets.only(top: 8),
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (remainingPills != null && remainingPills! <= 5) {
      chips.add(_chip(
        icon: Icons.local_pharmacy_outlined,
        label: 'Refill soon',
        color: const Color(0xFFE57373), // soft red
      ));
    }

    final days = _daysToExpiry(expiryDate);
    if (days != null) {
      chips.add(_chip(
        icon: Icons.hourglass_bottom,
        label: 'Expires in ${days}d',
        color: const Color(0xFFFBC02D), // amber
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: margin,
      child: Wrap(
        spacing: dense ? 8 : 10,
        runSpacing: dense ? 6 : 8,
        children: chips,
      ),
    );
  }

  int? _daysToExpiry(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    try {
      final d = DateTime.parse(iso);
      final diff = d.difference(DateTime.now()).inDays;
      return diff < 0 ? 0 : diff; // 0d if already passed (still shows)
    } catch (_) {
      return null;
    }
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final bg = color.withOpacity(0.12);
    final fg = color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 16 : 18, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
