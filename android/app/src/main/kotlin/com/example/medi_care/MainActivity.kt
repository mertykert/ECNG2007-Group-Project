package com.example.medi_care

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "medicare/alarmclock"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
    }

    // Schedules a user-visible AlarmClock alarm in a few minutes.
    // This makes Samsung list the app under “Alarms & reminders”.
    private fun primeAlarmClock(minutesAhead: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // Foreground intent when the alarm fires (harmless for priming).
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
