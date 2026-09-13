package com.klochkov.workingwithmaps

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.klochkov.workingwithmaps.tracking.LocationTrackingService
import com.klochkov.workingwithmaps.tracking.TrackingStore
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Transport only: Activity can disappear without stopping recording. The service
 * keeps applicationContext and SQLite, never Activity, MethodChannel or an event sink. */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var notificationReply: MethodChannel.Result? = null
    private var visible = false
    override fun onPostResume() { super.onPostResume(); visible = true }
    override fun onPause() { visible = false; super.onPause() }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val store = TrackingStore.get(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "field_inspector/tracking").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                // Channel calls arrive on main. SQLite runs on an executor; replies
                // return to main. read -> Drift commit -> ack is an explicit protocol.
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) result.success(true)
                        else if (notificationReply != null) result.error("busy", "Permission request in progress", null)
                        else { notificationReply = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 701) }
                    }
                    "startTracking" -> {
                        val routeId = call.argument<String>("routeId")
                        if (routeId.isNullOrBlank()) result.error("argument", "routeId required", null)
                        else if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) result.error("permission", "Разрешите точную геолокацию в настройках приложения", null)
                        else {
                            // Android12+ restricts background FGS starts; Android14+
                            // additionally enforces while-in-use permission at creation.
                            // A permission dialog can briefly precede onPostResume, so
                            // wait one UI turn; never schedule a background launch.
                            Handler(mainLooper).postDelayed({
                                if (!visible || isFinishing || isDestroyed) result.error("not_visible", "Откройте приложение для запуска tracking", null)
                                else try {
                                    val intent = Intent(this, LocationTrackingService::class.java)
                                        .putExtra("routeId", routeId).putExtra("reply", receiver(result))
                                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                                } catch (e: Exception) { result.error("fgs_start", e.message, null) }
                            }, 150)
                        }
                    }
                    "stopTracking" -> {
                        val service = LocationTrackingService.instance
                        if (service != null) service.stopRecording(receiver(result))
                        else execute(result) { store.stop(); null }
                    }
                    "isTracking" -> execute(result) {
                        store.state().put("running", LocationTrackingService.recording).toString()
                    }
                    "readPoints" -> execute(result) { store.readBatch() }
                    "ackPoints" -> {
                        val ids = call.argument<List<String>>("ids")
                        if (ids == null || ids.size > 200) result.error("argument", "Invalid ACK batch", null)
                        else execute(result) { store.acknowledge(ids); null }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    private fun execute(result: MethodChannel.Result, action: () -> Any?) {
        io.execute {
            try { val value = action(); runOnUiThread { result.success(value) } }
            catch (e: Exception) { runOnUiThread { result.error("native_storage", e.message, null) } }
        }
    }
    private fun receiver(result: MethodChannel.Result): ResultReceiver {
        val completed = AtomicBoolean(false)
        val handler = Handler(mainLooper)
        handler.postDelayed({ if (completed.compareAndSet(false, true)) result.error("timeout", "Нет подтверждения сервиса; проверьте состояние", null) }, 15000)
        return object : ResultReceiver(handler) {
            override fun onReceiveResult(code: Int, data: Bundle?) {
                if (!completed.compareAndSet(false, true)) return
                if (code == 0) result.success(null) else result.error("tracking", data?.getString("error"), null)
            }
        }
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 701) {
            // Denial doesn't forbid FGS. Dart can explain notification settings;
            // we do not demand ACCESS_BACKGROUND_LOCATION or loop permission dialogs.
            notificationReply?.success(grants.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationReply = null
        }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null); channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun onDestroy() {
        notificationReply?.error("detached", "Activity destroyed", null); notificationReply = null
        io.shutdown()
        super.onDestroy()
    }
}
