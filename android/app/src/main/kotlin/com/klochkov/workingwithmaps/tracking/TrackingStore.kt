package com.klochkov.workingwithmaps.tracking

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject
import java.util.UUID

/** Durable native inbox. НЕ открывает Drift-файл: его миграциями владеет Dart.
 * SQLite commit предшествует любому сообщению Flutter. Activity/FlutterEngine могут
 * отсутствовать: точки остаются здесь до подтверждения транзакционного импорта.
 * synchronized сериализует channel worker и location worker внутри процесса. */
class TrackingStore private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "tracking_inbox.sqlite", null, 1) {
    companion object {
        @Volatile private var instance: TrackingStore? = null
        fun get(context: Context): TrackingStore = instance ?: synchronized(this) {
            instance ?: TrackingStore(context).also { instance = it }
        }
    }
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)")
        db.execSQL("CREATE TABLE points (id TEXT PRIMARY KEY, data TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("Unsupported tracking inbox migration: $oldVersion -> $newVersion")
    }
    @Synchronized fun state(): JSONObject = readableDatabase.rawQuery("SELECT data FROM state WHERE id=1", null).use {
        if (it.moveToFirst()) JSONObject(it.getString(0)) else JSONObject()
    }
    private fun saveState(value: JSONObject) {
        writableDatabase.insertWithOnConflict("state", null, ContentValues().apply {
            put("id", 1); put("data", value.toString())
        }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
    }
    @Synchronized fun begin(routeId: String) {
        val old = state()
        val next = if (old.optString("routeId") == routeId) old else JSONObject().put("count", 0)
        // Process/service restart creates a gap; ordinary Activity detach does not.
        next.put("routeId", routeId).put("desired", true).put("segmentId", UUID.randomUUID().toString())
            .put("message", "Ожидание GPS").remove("last")
        saveState(next)
    }
    @Synchronized fun stop() {
        saveState(state().put("desired", false).put("message", "Запись остановлена"))
    }
    @Synchronized fun message(text: String) { saveState(state().put("message", text)) }
    @Synchronized fun accept(fix: GpsFix): Boolean {
        val next = state()
        if (!next.optBoolean("desired")) return false
        // A new segment resets geometry, not time: a replayed last fix following
        // process recovery must not become another point with a new UUID.
        if (fix.timestamp <= next.optLong("lastTimestamp", Long.MIN_VALUE)) return false
        if (fix.accuracy.isFinite()) next.put("accuracy", fix.accuracy)
        val previous = next.optJSONObject("last")?.let { fromJson(it) }
        if (!GpsFilter().accepts(fix, previous)) {
            saveState(next.put("message", "Точка отброшена GPS-фильтром"))
            return false
        }
        val point = JSONObject().put("id", UUID.randomUUID().toString())
            .put("routeId", next.getString("routeId")).put("segmentId", next.getString("segmentId"))
            .put("latitude", fix.latitude).put("longitude", fix.longitude).put("accuracy", fix.accuracy)
            .put("speed", fix.speed ?: JSONObject.NULL).put("timestamp", fix.timestamp)
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.insertOrThrow("points", null, ContentValues().apply {
                put("id", point.getString("id")); put("data", point.toString())
            })
            // Baseline and count survive inbox ACK/deletion, preventing filter resets.
            saveState(next.put("last", point).put("lastTimestamp", fix.timestamp).put("count", next.optInt("count") + 1)
                .put("message", "Маршрут отслеживается"))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return true
    }
    @Synchronized fun readBatch(): List<String> = readableDatabase.rawQuery(
        "SELECT data FROM points ORDER BY rowid LIMIT 200", null).use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
    }
    @Synchronized fun acknowledge(ids: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            ids.forEach { db.delete("points", "id=?", arrayOf(it)) }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
    private fun fromJson(p: JSONObject) = GpsFix(p.getDouble("latitude"), p.getDouble("longitude"),
        p.getDouble("accuracy"), if (p.isNull("speed")) null else p.getDouble("speed"), p.getLong("timestamp"))
}
