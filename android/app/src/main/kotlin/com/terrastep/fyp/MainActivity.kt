package com.terrastep.fyp

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.lifecycle.lifecycleScope
import com.terrastep.fyp.db.TerrastepDatabase
import com.terrastep.fyp.gpx.GpxFileWriter
import com.terrastep.fyp.service.WalkRecorderService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

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
                                db.walkDao().getAllSessions()
                                    .filterNot { it.title.startsWith("Abbottabad Pilot Trail") }
                                    .map { s ->
                                    mapOf(
                                        "sessionId" to s.sessionId,
                                        "title" to s.title,
                                        "startTimeUtcMs" to s.startTimeUtcMs,
                                        "endTimeUtcMs" to s.endTimeUtcMs,
                                        "elapsedDurationMs" to s.elapsedDurationMs,
                                        "movingDurationMs" to s.movingDurationMs,
                                        "totalSteps" to s.totalSteps,
                                        "totalDistanceMeters" to s.totalDistanceMeters,
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
                                            "segmentIndex" to pt.segmentIndex
                                        )
                                    }
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
                    else -> result.notImplemented()
                }
            }
    }

}
