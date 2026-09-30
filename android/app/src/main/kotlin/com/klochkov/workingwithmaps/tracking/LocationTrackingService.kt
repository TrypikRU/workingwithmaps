package com.klochkov.workingwithmaps.tracking

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*
import android.util.Log
import com.google.android.gms.location.*
import com.klochkov.workingwithmaps.MainActivity

/**
 * Самостоятельно запущенный сервис не привязан к Activity или FlutterEngine. Закрытие
 * представления Flutter не вызывает stopSelf: запись завершает явная команда остановки. Android
 * всё же может завершить процесс по запросу пользователя или правилам энергосбережения
 * производителя. START_STICKY запрашивает восстановление, но не гарантирует его и не обходит
 * ограничения FGS.
 */
class LocationTrackingService : Service() {
    companion object {
        const val TAG = "FieldTracking"
        const val STOP = "field.tracking.STOP"
        private const val CHANNEL = "field_route_location"
        private const val NOTIFICATION = 1001
        @Volatile var instance: LocationTrackingService? = null
            private set
        @Volatile var recording = false
            private set
    }
    private lateinit var store: TrackingStore
    private lateinit var fused: FusedLocationProviderClient
    private lateinit var thread: HandlerThread
    private lateinit var worker: Handler
    private var stopping = false
    private var registered = false
    private var starting = false
    private val replies = mutableListOf<ResultReceiver>()
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            // Обработка выполняется в нашем HandlerThread. Фильтрация и фиксация в SQLite происходят
            // здесь, а не в EventChannel или изоляте Flutter. Сортировка пакетов
            // упорядочивает координаты; последняя сохранённая точка защищает от дубликатов.
            if (stopping) return
            try {
                result.locations.sortedBy { it.time }.forEach { location ->
                    val age = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
                    if (!location.hasAccuracy() || age < 0 || age > 30_000_000_000L) return@forEach
                    val accepted = store.accept(GpsFix(location.latitude, location.longitude,
                        location.accuracy.toDouble(),
                        if (location.hasSpeed() && location.speed >= 0 && location.speed.isFinite()) location.speed.toDouble() else null,
                        location.time / 1000 * 1000))
                    if (accepted) {
                        Log.i(TAG, "point committed; count=${store.state().optInt("count")}")
                        notifyProgress()
                    }
                }
            } catch (e: Exception) { fail("Ошибка записи GPS: ${e.javaClass.simpleName}") }
        }
        override fun onLocationAvailability(value: LocationAvailability) {
            if (!value.isLocationAvailable && !stopping) {
                try { store.message("GPS недоступен: ожидание сигнала / проверьте геолокацию") }
                catch (e: Exception) { fail("Ошибка журнала записи маршрута: ${e.javaClass.simpleName}") }
            }
        }
    }
    override fun onCreate() {
        super.onCreate()
        store = TrackingStore.get(this)
        fused = LocationServices.getFusedLocationProviderClient(this)
        thread = HandlerThread("FieldLocationWriter").apply { start() }
        worker = Handler(thread.looper)
        instance = this
        // Android 8+ требует канал до startForeground. Уровень LOW исключает звук при
        // каждом обновлении счётчика. Видимость и важность задаёт пользователь в настройках.
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Отслеживание обхода", NotificationManager.IMPORTANCE_LOW))
        }
    }
    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val reply = intent?.getParcelableExtra<ResultReceiver>("reply")
        if (intent?.action == STOP) {
            stopRecording(reply)
            return START_NOT_STICKY
        }
        // Сразу переводим сервис в активный режим, до асинхронной подписки на координаты и ввода-вывода.
        // Android 14 проверяет доступ во время использования и здесь, а не только в Activity.
        // Обрабатываем SecurityException и ограничения FGS, не допуская циклических сбоев сервиса.
        try {
            if (!hasLocationPermission()) error("Нет разрешения на точную геолокацию")
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(0), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(NOTIFICATION, notification(0))
        } catch (e: Exception) {
            reply?.send(1, Bundle().apply { putString("error", e.message) })
            Log.w(TAG, "FGS promotion refused: ${e.javaClass.simpleName}")
            stopSelf()
            return START_NOT_STICKY
        }
        worker.post {
            try {
                if (stopping) {
                    reply?.send(1, Bundle().apply { putString("error", "Сервис останавливается; повторите запуск") })
                    return@post
                }
                val persisted = store.state()
                val id = intent?.getStringExtra("routeId") ?: persisted.optString("routeId")
                if (id.isBlank() || (intent == null && !persisted.optBoolean("desired"))) {
                    stopRecording(reply)
                } else if ((registered || starting) && persisted.optString("routeId") != id) {
                    reply?.send(1, Bundle().apply { putString("error", "Уже записывается другой обход") })
                } else if (registered) {
                    notifyProgress()
                    reply?.send(0, Bundle.EMPTY)
                } else if (starting) {
                    if (reply != null) replies.add(reply)
                } else {
                    if (reply != null) replies.add(reply)
                    starting = true
                    store.begin(id)
                    subscribe()
                }
            } catch (e: Exception) { fail("Не удалось запустить запись: ${e.javaClass.simpleName}", reply) }
        }
        return START_STICKY
    }
    private fun hasLocationPermission() = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    @Suppress("MissingPermission")
    private fun subscribe() {
        // Разрешение могло быть отозвано между проверкой Activity и этим обратным вызовом.
        // Точная геолокация нужна приложению: приблизительные координаты обычно не проходят порог 50 м.
        if (!hasLocationPermission()) { fail("Разрешите точную геолокацию"); return }
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000)
            .setMinUpdateIntervalMillis(2000).setMaxUpdateDelayMillis(0).build()
        fused.requestLocationUpdates(request, callback, thread.looper)
            .addOnSuccessListener {
                worker.post {
                    if (stopping) { fused.removeLocationUpdates(callback); return@post }
                    registered = true; starting = false; recording = true
                    replies.forEach { it.send(0, Bundle.EMPTY) }; replies.clear()
                    notifyProgress()
                    worker.post(permissionWatch)
                    Log.i(TAG, "location subscription active")
                }
            }.addOnFailureListener { e -> worker.post { fail("Fused location: ${e.javaClass.simpleName}") } }
    }
    private val permissionWatch = object : Runnable {
        override fun run() {
            if (stopping) return
            if (!hasLocationPermission()) { fail("Доступ к геолокации отозван"); return }
            worker.postDelayed(this, 5000)
        }
    }
    private fun notification(count: Int): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle("Полевой инспектор")
            .setContentText("Маршрут отслеживается · Собрано GPS-точек: $count")
            .setStyle(Notification.BigTextStyle().bigText("Маршрут отслеживается\nСобрано GPS-точек: $count"))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE).build()
    }
    private fun notifyProgress() {
        // Отказ в POST_NOTIFICATIONS на API 33+ не запрещает FGS. Android показывает
        // сервис в диспетчере задач, но может скрыть уведомление из шторки.
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(store.state().optInt("count")))
    }
    fun stopRecording(reply: ResultReceiver?) {
        worker.post {
            // Барьер записи: сначала завершаются уже поставленные в очередь транзакции. Новые вызовы
            // видят stopping=true. Затем подтверждаем остановку, чтобы Dart импортировал остаток и завершил обход.
            stopping = true; recording = false
            fused.removeLocationUpdates(callback)
            try {
                store.stop()
                reply?.send(0, Bundle.EMPTY)
            } catch (e: Exception) { reply?.send(1, Bundle().apply { putString("error", "Не удалось сохранить остановку") }) }
            replies.forEach { it.send(1, Bundle().apply { putString("error", "Запуск отменён") }) }; replies.clear()
            Handler(mainLooper).post { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
        }
    }
    private fun fail(message: String, reply: ResultReceiver? = null) {
        Log.w(TAG, message)
        stopping = true; recording = false
        fused.removeLocationUpdates(callback)
        try { store.message(message) } catch (_: Exception) { /* Сохраняем существующую входящую очередь даже при заполненном диске. */ }
        val error = Bundle().apply { putString("error", message) }
        reply?.send(1, error)
        replies.filter { it !== reply }.forEach { it.send(1, error) }; replies.clear()
        Handler(mainLooper).post { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    }
    override fun onDestroy() {
        // Это не остановка пользователем: сохраняем обход для восстановления при открытии приложения.
        // Входящую очередь не удаляем. quitSafely позволяет завершить начатые транзакции SQLite.
        recording = false; instance = null
        worker.post { stopping = true; fused.removeLocationUpdates(callback); worker.removeCallbacks(permissionWatch) }
        thread.quitSafely()
        Log.i(TAG, "service destroyed; durable inbox retained")
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
