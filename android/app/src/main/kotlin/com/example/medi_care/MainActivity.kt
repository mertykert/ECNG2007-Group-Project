package com.example.medi_care

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val PRIME_CHANNEL = "medicare/alarmclock"
    private val EXACT_CHANNEL = "medicare/exact"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel 1: prime an AlarmClock alarm (for Samsung listing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIME_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "primeAlarmClock" -> {
                        try {
                            val minutes = (call.argument<Int>("minutes") ?: 2).coerceAtLeast(1)
                            primeAlarmClock(minutes)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel 2: reliable OS check for exact-alarms capability
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXACT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canScheduleExactAlarms" -> {
                        try {
                            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                            val ok = am.canScheduleExactAlarms()
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Schedules a user-visible AlarmClock alarm a few minutes ahead.
    // This helps Samsung surface the app under “Alarms & reminders”.
    private fun primeAlarmClock(minutesAhead: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            10001,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val triggerAt = System.currentTimeMillis() + minutesAhead * 60_000L
        val info = AlarmManager.AlarmClockInfo(triggerAt, pi)
        alarmManager.setAlarmClock(info, pi)
    }
}
