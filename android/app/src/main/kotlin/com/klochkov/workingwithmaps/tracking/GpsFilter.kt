package com.klochkov.workingwithmaps.tracking

import kotlin.math.*

data class GpsFix(val latitude: Double, val longitude: Double, val accuracy: Double,
                  val speed: Double?, val timestamp: Long)

/**
 * Чистый фильтр предметной области на Kotlin; интерфейс, Android Location и Play Services не
 * нужны. Правила совпадают с Dart LocationPointFilter: база — последняя ПРИНЯТАЯ точка.
 * Сообщённую скорость сохраняем, а скорость выброса вычисляем по Haversine.
 */
class GpsFilter(private val maxAccuracy: Double = 50.0,
                private val minDistance: Double = 5.0, private val maxSpeed: Double = 15.0) {
    fun accepts(current: GpsFix, previous: GpsFix?): Boolean {
        if (!current.latitude.isFinite() || current.latitude !in -90.0..90.0 ||
            !current.longitude.isFinite() || current.longitude !in -180.0..180.0 ||
            !current.accuracy.isFinite() || current.accuracy !in 0.0..maxAccuracy ||
            current.speed?.let { !it.isFinite() || it < 0 } == true) return false
        if (previous == null) return true
        val seconds = (current.timestamp - previous.timestamp) / 1000.0
        if (seconds <= 0) return false
        val lat1 = Math.toRadians(previous.latitude)
        val lat2 = Math.toRadians(current.latitude)
        val a = sin((lat2 - lat1) / 2).pow(2) + cos(lat1) * cos(lat2) *
            sin(Math.toRadians(current.longitude - previous.longitude) / 2).pow(2)
        val distance = 6371008.8 * 2 * asin(sqrt(a.coerceIn(0.0, 1.0)))
        return distance >= minDistance && distance / seconds <= maxSpeed
    }
}
