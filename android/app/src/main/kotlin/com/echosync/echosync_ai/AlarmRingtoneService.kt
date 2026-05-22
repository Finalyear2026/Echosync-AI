package com.echosync.echosync_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmRingtoneService : Service() {

    companion object {
        private const val TAG = "AlarmRingtoneService"
        private const val CHANNEL_ID = "alarm_ringtone_channel"
        private const val NOTIFICATION_ID = 9002
        const val ACTION_START = "com.echosync.echosync_ai.START_ALARM"
        const val ACTION_STOP = "com.echosync.echosync_ai.STOP_ALARM"
        const val EXTRA_TITLE = "alarm_title"
        const val EXTRA_PERSISTENT = "alarm_persistent"
        private const val AUTO_STOP_MS = 5 * 60 * 1000L // 5 minutes for non-persistent

        fun start(context: Context, title: String = "Alarm", persistent: Boolean = true) {
            val intent = Intent(context, AlarmRingtoneService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PERSISTENT, persistent)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(Intent(context, AlarmRingtoneService::class.java).apply {
                action = ACTION_STOP
            })
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioManager: AudioManager? = null
    private var originalAlarmVolume: Int = -1
    private var volumeOverridden: Boolean = false
    private val autoStopHandler = Handler(Looper.getMainLooper())
    private val autoStopRunnable = Runnable {
        Log.d(TAG, "Non-persistent alarm auto-stopped after timeout")
        stopRinging()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRinging()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Alarm"
                val persistent = intent?.getBooleanExtra(EXTRA_PERSISTENT, true) ?: true
                acquireWakeLock()
                startForeground(NOTIFICATION_ID, buildNotification(title, persistent))
                startRinging(persistent)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        autoStopHandler.removeCallbacks(autoStopRunnable)
        stopRinging()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startRinging(persistent: Boolean = true) {
        // For persistent alarms: force max alarm volume, saving original to restore later
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        if (persistent) {
            try {
                val maxVol = audioManager!!.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                originalAlarmVolume = audioManager!!.getStreamVolume(AudioManager.STREAM_ALARM)
                audioManager!!.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    maxVol,
                    0 // no UI flag — silent volume change
                )
                volumeOverridden = true
                Log.d(TAG, "Persistent alarm: forced alarm volume to max ($maxVol), was $originalAlarmVolume")
            } catch (e: Exception) {
                Log.e(TAG, "Could not set alarm volume: ${e.message}")
            }
        }

        try {
            // Get alarm ringtone URI — falls back to notification, then ringtone
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setLegacyStreamType(AudioManager.STREAM_ALARM)
                        .build()
                )
                setDataSource(applicationContext, alarmUri)
                isLooping = true
                prepare()
                start()
            }
            Log.d(TAG, "Alarm ringtone started (persistent=$persistent)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ringtone: ${e.message}")
        }

        // Non-persistent: auto-stop after 5 minutes
        if (!persistent) {
            autoStopHandler.postDelayed(autoStopRunnable, AUTO_STOP_MS)
            Log.d(TAG, "Non-persistent alarm: auto-stop scheduled in 5 minutes")
        }

        // Vibrate in alarm pattern
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(VibratorManager::class.java)
                vibrator = vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            }
            val pattern = longArrayOf(0, 1000, 500, 1000, 500)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibration failed: ${e.message}")
        }
    }

    private fun stopRinging() {
        // Restore alarm volume if we overrode it
        if (volumeOverridden && originalAlarmVolume >= 0) {
            try {
                audioManager?.setStreamVolume(AudioManager.STREAM_ALARM, originalAlarmVolume, 0)
                Log.d(TAG, "Alarm volume restored to $originalAlarmVolume")
            } catch (e: Exception) {
                Log.e(TAG, "Could not restore alarm volume: ${e.message}")
            }
            volumeOverridden = false
        }
        autoStopHandler.removeCallbacks(autoStopRunnable)
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping media player: ${e.message}")
        }
        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling vibration: ${e.message}")
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "EchoSync:AlarmWakeLock"
            )
            wakeLock?.acquire(60_000L) // max 60s
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock error: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release error: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Alarm Ringtone",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Keeps alarm ringing"
                setShowBadge(false)
                setSound(null, null) // Sound is handled by MediaPlayer, not the channel
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, persistent: Boolean = true): Notification {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, AlarmRingtoneService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Full-screen intent: wakes the screen and shows over lock screen
        val fullScreenIntent = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("alarm_ringing", true)
                putExtra("alarm_title", title)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val bodyText = if (persistent)
            "Persistent alarm — tap to dismiss"
        else
            "Alarm is ringing — tap to open"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔔 $title")
            .setContentText(bodyText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(0, "Dismiss", stopIntent)
            .setOngoing(persistent) // persistent = can't swipe; non-persistent = swipeable
            .setAutoCancel(!persistent)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
}
