package com.terrastep.fyp

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.lifecycle.lifecycleScope
import com.terrastep.fyp.db.TerrastepDatabase
import com.terrastep.fyp.db.TrackPointEntity
import com.terrastep.fyp.db.WalkSessionEntity
import com.terrastep.fyp.geo.HexGridEngine
import com.terrastep.fyp.gpx.GpxFileWriter
import com.terrastep.fyp.service.WalkRecorderService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.cos
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.terrastep.fyp/methods"
    private val EVENT_CHANNEL = "com.terrastep.fyp/telemetry"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val serviceIntent = Intent(this, WalkRecorderService::class.java)
        startService(serviceIntent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    WalkRecorderService.telemetryListener = { payload ->
                        events?.success(payload)
                    }
                    WalkRecorderService.instance?.let {
                        events?.success(it.buildTelemetryPayload())
                    }
                }

                override fun onCancel(arguments: Any?) {
                    WalkRecorderService.telemetryListener = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val svc = WalkRecorderService.instance
                when (call.method) {
                    "startLocationPreview" -> {
                        result.success(svc?.startLocationPreview() ?: emptyMap<String, Any?>())
                    }
                    "stopLocationPreview" -> {
                        svc?.stopLocationPreview()
                        result.success(null)
                    }
                    "getDiagnostics" -> {
                        result.success(svc?.getDiagnostics() ?: emptyMap<String, Any?>())
                    }
                    "startWalk" -> {
                        result.success(svc?.startWalk() ?: emptyMap<String, Any?>())
                    }
                    "pauseWalk" -> {
                        result.success(svc?.pauseWalk() ?: emptyMap<String, Any?>())
                    }
                    "resumeWalk" -> {
                        result.success(svc?.resumeWalk() ?: emptyMap<String, Any?>())
                    }
                    "finishWalk" -> {
                        lifecycleScope.launch {
                            val summary = svc?.finishWalk() ?: emptyMap()
                            result.success(summary)
                        }
                    }
                    "getSavedSessions" -> {
                        lifecycleScope.launch {
                            val list = withContext(Dispatchers.IO) {
                                val db = TerrastepDatabase.getInstance(this@MainActivity)
                                db.walkDao().getAllSessions().map { s ->
                                    mapOf(
                                        "sessionId" to s.sessionId,
                                        "title" to s.title,
                                        "startTimeUtcMs" to s.startTimeUtcMs,
                                        "endTimeUtcMs" to s.endTimeUtcMs,
                                        "elapsedDurationMs" to s.elapsedDurationMs,
                                        "movingDurationMs" to s.movingDurationMs,
                                        "totalSteps" to s.totalSteps,
                                        "totalDistanceMeters" to s.totalDistanceMeters,
                                        "visitedHexIdsJson" to s.visitedHexIdsJson,
                                        "gpxFilePath" to s.gpxFilePath,
                                        "status" to s.status
                                    )
                                }
                            }
                            result.success(list)
                        }
                    }
                    "getSessionDetail" -> {
                        val sessionId = call.argument<String>("sessionId") ?: ""
                        lifecycleScope.launch {
                            val detail = withContext(Dispatchers.IO) {
                                val db = TerrastepDatabase.getInstance(this@MainActivity)
                                val session = db.walkDao().getSession(sessionId)
                                val points = db.walkDao().getTrackPointsForSession(sessionId)
                                val gpxFile = session?.gpxFilePath?.let { File(it) }
                                val gpxContent = if (gpxFile != null && gpxFile.exists()) {
                                    gpxFile.readText()
                                } else if (session != null) {
                                    val generated = GpxFileWriter.writeSessionGpx(this@MainActivity, session, points)
                                    generated.readText()
                                } else ""

                                val hexList = mutableListOf<String>()
                                session?.visitedHexIdsJson?.let { json ->
                                    val arr = JSONArray(json)
                                    for (i in 0 until arr.length()) hexList.add(arr.getString(i))
                                }
                                val hexPolygons = hexList.map { hId ->
                                    mapOf(
                                        "hexId" to hId,
                                        "ring" to HexGridEngine.hexIdToBoundaryLatLon(hId).map { listOf(it.second, it.first) }
                                    )
                                }

                                mapOf(
                                    "sessionId" to sessionId,
                                    "gpxXml" to gpxContent,
                                    "gpxFilePath" to (session?.gpxFilePath ?: ""),
                                    "pointCount" to points.size,
                                    "points" to points.map { pt ->
                                        mapOf(
                                            "lat" to pt.latitude,
                                            "lon" to pt.longitude,
                                            "ele" to pt.altitudeMeters,
                                            "steps" to pt.cumulativeSessionSteps,
                                            "segmentIndex" to pt.segmentIndex,
                                            "hexId" to pt.hexCellId
                                        )
                                    },
                                    "hexPolygons" to hexPolygons
                                )
                            }
                            result.success(detail)
                        }
                    }
                    "exportToDownloads" -> {
                        val sessionId = call.argument<String>("sessionId") ?: ""
                        lifecycleScope.launch {
                            try {
                                val savedPath = withContext(Dispatchers.IO) {
                                    val db = TerrastepDatabase.getInstance(this@MainActivity)
                                    val session = db.walkDao().getSession(sessionId)
                                        ?: throw IllegalStateException("Session not found")
                                    val points = db.walkDao().getTrackPointsForSession(sessionId)
                                    val file = session.gpxFilePath?.let { File(it) }?.takeIf { it.exists() }
                                        ?: GpxFileWriter.writeSessionGpx(this@MainActivity, session, points)
                                    GpxFileWriter.copyToPublicDownloads(this@MainActivity, file)
                                }
                                result.success(savedPath)
                            } catch (e: Exception) {
                                result.error("EXPORT_ERR", e.message, null)
                            }
                        }
                    }
                    "generateDemoWalk" -> {
                        lifecycleScope.launch {
                            val summary = withContext(Dispatchers.IO) {
                                createDemoAbbottabadWalk()
                            }
                            result.success(summary)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private suspend fun createDemoAbbottabadWalk(): Map<String, Any?> {
        val db = TerrastepDatabase.getInstance(this)
        val sessionId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val startMs = now - 15 * 60 * 1000L
        val points = mutableListOf<TrackPointEntity>()
        val hexes = LinkedHashSet<String>()

        var lat = 34.1688
        var lon = 73.2215
        var steps = 0
        var dist = 0.0

        for (i in 0 until 60) {
            val angle = i * 0.08
            val dLat = 0.00014 * cos(angle)
            val dLon = 0.00018 * sin(angle)
            lat += dLat
            lon += dLon
            steps += 11
            dist += 18.5
            val hexId = HexGridEngine.latLonToHexId(lat, lon)
            hexes.add(hexId)
            points.add(
                TrackPointEntity(
                    sessionId = sessionId,
                    segmentIndex = if (i < 30) 0 else 1,
                    sequenceNumber = i + 1,
                    latitude = lat,
                    longitude = lon,
                    altitudeMeters = 1256.0 + (i * 0.2),
                    horizontalAccuracyMeters = 4.2f,
                    speedMetersPerSec = 1.35f,
                    timestampUtcMs = startMs + (i * 15_000L),
                    elapsedRealtimeMs = i * 15_000L,
                    cumulativeSessionSteps = steps,
                    hexCellId = hexId
                )
            )
        }

        val fmt = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.US)
        val entity = WalkSessionEntity(
            sessionId = sessionId,
            title = "Abbottabad Pilot Trail (${fmt.format(Date(startMs))})",
            startTimeUtcMs = startMs,
            endTimeUtcMs = now,
            elapsedDurationMs = 15 * 60 * 1000L,
            movingDurationMs = 14 * 60 * 1000L,
            totalSteps = steps,
            baselineStepsAtStart = 10420L,
            totalDistanceMeters = dist,
            visitedHexIdsJson = JSONArray(hexes.toList()).toString(),
            gpxFilePath = null,
            status = "COMPLETED"
        )
        db.walkDao().upsertSession(entity)
        for (pt in points) db.walkDao().insertTrackPoint(pt)
        val gpxFile = GpxFileWriter.writeSessionGpx(this, entity, points)
        val updated = entity.copy(gpxFilePath = gpxFile.absolutePath)
        db.walkDao().upsertSession(updated)
        return mapOf(
            "sessionId" to sessionId,
            "gpxFilePath" to gpxFile.absolutePath
        )
    }
}
