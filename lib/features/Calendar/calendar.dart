import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:logger/logger.dart';

// Create a logger instance (for debugging purposes during development)
final logger = Logger();

/// Enum that defines the different calendar views available
/// - month: Standard monthly grid view
/// - week: 7-day layout with summary cards
/// - day: Focused view for a single day
enum CalendarView { month, week, day }

/// Main page that displays the user's medication or event schedule.
/// Allows switching between month, week, and day views.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  // --- STATE VARIABLES ---

  /// The day currently in focus by the calendar (used to navigate views)
  DateTime _focusedDay = DateTime.now();

  /// The day the user has tapped on — defaults to today so it’s never null
  DateTime? _selectedDay = DateTime.now();

  /// Controls which calendar view is currently displayed (month/week/day)
  CalendarView _currentView = CalendarView.month;

  /// Stores reminders (like medications) for each day
  /// The key is the date (without time), and the value is a list of reminders
  final Map<DateTime, List<String>> _reminders = {};

  // --- HELPER METHODS ---

  /// Returns a list of reminders for a specific day.
  /// If no reminders exist for that day, returns an empty list.
  List<String> _getRemindersForDay(DateTime day) {
    return _reminders[DateUtils.dateOnly(day)] ?? [];
  }

  /// Displays a dialog to add a new reminder for a given day.
  /// Uses TextEditingController to capture the user’s input.
  void _addReminder(BuildContext context, DateTime day) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Reminder"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter reminder"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                // Normalize date to remove time component
                final d = DateUtils.dateOnly(day);

                // Add new reminder to the list for this date
                _reminders[d] = [...?_reminders[d], controller.text];

                // Debug logs (disabled for now)
                // logger.d("Reminder added for $d: ${controller.text}");
                // logger.d("Current reminders: $_reminders");
              });
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// Builds a small red dot marker under a date if that day has reminders.
  Widget _buildMarker(DateTime day) {
    if (_reminders.containsKey(day) && _reminders[day]!.isNotEmpty) {
      return Positioned(
        bottom: 1,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red,
          ),
        ),
      );
    }
    return const SizedBox(); // No marker if there are no reminders
  }

  // --- CALENDAR VIEW BUILDERS ---

  /// Monthly calendar view showing all days in grid form
  /// Displays reminders below the calendar for the selected day
  Widget _buildMonthlyView() {
    return Column(
      children: [
        TableCalendar(
          focusedDay: _focusedDay,
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          calendarFormat: CalendarFormat.month,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, _) {
              return _buildMarker(DateUtils.dateOnly(date));
            },
          ),
        ),
        const SizedBox(height: 16),
        // Display the list of reminders for the selected day
        Expanded(
          child: ListView(
            children: _getRemindersForDay(_selectedDay ?? _focusedDay)
                .map((r) => ListTile(
              leading: const Icon(Icons.medical_services),
              title: Text(r),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  /// Weekly view – shows 7 cards (Mon–Sun), each with that day's reminders.
  /// Allows users to see an overview of the week at a glance.
  Widget _buildWeeklyView() {
    // Determine Monday of the current week
    final monday = _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
    final daysOfWeek = List.generate(7, (i) => monday.add(Duration(days: i)));

    return Column(
      children: [
        // Use TableCalendar in week format for navigation and selection
        TableCalendar(
          focusedDay: _focusedDay,
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          calendarFormat: CalendarFormat.week,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, _) {
              return _buildMarker(DateUtils.dateOnly(date));
            },
          ),
        ),
        const SizedBox(height: 16),

        // --- Weekly reminder grid (2 boxes per row) ---
        Expanded(
          child: GridView.builder(
            itemCount: daysOfWeek.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Two day boxes per row
              childAspectRatio: 1.3, // Adjust height
            ),
            itemBuilder: (context, index) {
              final day = daysOfWeek[index];
              final reminders = _getRemindersForDay(day);

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header showing day name and date
                      Text(
                        "${day.weekday == DateTime.monday ? 'Mon' : day.weekday == DateTime.tuesday ? 'Tue' : day.weekday == DateTime.wednesday ? 'Wed' : day.weekday == DateTime.thursday ? 'Thu' : day.weekday == DateTime.friday ? 'Fri' : day.weekday == DateTime.saturday ? 'Sat' : 'Sun'} ${day.day}/${day.month}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Show either “No pills” or list of reminders
                      if (reminders.isEmpty)
                        const Text("No pills", style: TextStyle(color: Colors.grey))
                      else
                        ...reminders.map((pill) => Text("• $pill")),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Daily view – focuses on a single day with navigation arrows.
  /// Designed for detailed review of that day's reminders.
  Widget _buildDailyView() {
    final day = _selectedDay ?? _focusedDay;
    return Column(
      children: [
        const SizedBox(height: 16),

        // --- Header with navigation arrows and day label ---
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left arrow to go to previous day
            IconButton(
              icon: const Icon(Icons.arrow_left),
              iconSize: 50, // Larger arrow for better visibility
              onPressed: () {
                setState(() {
                  _selectedDay = day.subtract(const Duration(days: 1));
                  _focusedDay = _selectedDay!;
                });
              },
            ),

            // Middle box displaying the current day
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${day.weekday == DateTime.monday ? 'Monday' : day.weekday == DateTime.tuesday ? 'Tuesday' : day.weekday == DateTime.wednesday ? 'Wednesday' : day.weekday == DateTime.thursday ? 'Thursday' : day.weekday == DateTime.friday ? 'Friday' : day.weekday == DateTime.saturday ? 'Saturday' : 'Sunday'} ${day.day}/${day.month}/${day.year}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            // Right arrow to go to next day
            IconButton(
              icon: const Icon(Icons.arrow_right),
              iconSize: 50,
              onPressed: () {
                setState(() {
                  _selectedDay = day.add(const Duration(days: 1));
                  _focusedDay = _selectedDay!;
                });
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // --- List of reminders for the current day ---
        Expanded(
          child: ListView(
            children: _getRemindersForDay(day)
                .map((r) => ListTile(
              leading: const Icon(Icons.medical_services),
              title: Text(r),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  // --- MAIN BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    // Select which view to render based on _currentView
    Widget body;
    switch (_currentView) {
      case CalendarView.month:
        body = _buildMonthlyView();
        break;
      case CalendarView.week:
        body = _buildWeeklyView();
        break;
      case CalendarView.day:
        body = _buildDailyView();
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Schedule"),
        // Show a back arrow only for week/day views
        leading: _currentView == CalendarView.month
            ? null
            : IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              // Step backwards in the hierarchy (Day → Week → Month)
              if (_currentView == CalendarView.day) {
                _currentView = CalendarView.week;
              } else if (_currentView == CalendarView.week) {
                _currentView = CalendarView.month;
              }
            });
          },
        ),
        actions: [
          // Dropdown menu to switch between views
          PopupMenuButton<CalendarView>(
            onSelected: (view) {
              setState(() {
                _currentView = view;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: CalendarView.month, child: Text("Month")),
              const PopupMenuItem(
                  value: CalendarView.week, child: Text("Week")),
              const PopupMenuItem(
                  value: CalendarView.day, child: Text("Day")),
            ],
          ),
        ],
      ),

      body: body,

      // Floating Action Button for adding reminders
      // Only visible when a valid day is selected and we’re not in day view
      floatingActionButton: _currentView == CalendarView.day ||
          _selectedDay == null
          ? null
          : FloatingActionButton(
        onPressed: () => _addReminder(context, _selectedDay!),
        child: const Icon(Icons.add),
      ),
    );
  }
}
