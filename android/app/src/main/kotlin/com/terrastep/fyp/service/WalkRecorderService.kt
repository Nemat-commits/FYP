package com.terrastep.fyp.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.*
import androidx.core.app.NotificationCompat
import com.terrastep.fyp.MainActivity
import com.terrastep.fyp.db.TerrastepDatabase
import com.terrastep.fyp.db.TrackPointEntity
import com.terrastep.fyp.db.WalkSessionEntity
import com.terrastep.fyp.geo.HexGridEngine
import com.terrastep.fyp.gpx.GpxFileWriter
import com.terrastep.fyp.sensors.GpsFixPolicy
import com.terrastep.fyp.sensors.LocationTrackerManager
import com.terrastep.fyp.sensors.StepCounterManager
import kotlinx.coroutines.*
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.*

class WalkRecorderService : Service() {

    companion object {
        const val CHANNEL_ID = "terrastep_recorder_channel"
        const val NOTIFICATION_ID = 3001

        var telemetryListener: ((Map<String, Any?>) -> Unit)? = null
        var instance: WalkRecorderService? = null
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var db: TerrastepDatabase
    private lateinit var stepManager: StepCounterManager
    private lateinit var locationManager: LocationTrackerManager

    private var currentSessionId: String? = null
    private var sessionTitle: String = ""
    private var status: String = "IDLE" // IDLE, RECORDING, PAUSED
    private var startTimeUtcMs: Long = 0L
    private var startElapsedRealtimeMs: Long = 0L
    private var accumulatedMovingMsBeforePause: Long = 0L
    private var segmentStartElapsedMs: Long = 0L

    private var segmentIndex: Int = 0
    private var sequenceNumber: Int = 0
    private var totalDistanceMeters: Double = 0.0
    private var lastAcceptedLocation: Location? = null
    private var distanceAnchorSteps = 0
    private var lastRawLocation: Location? = null
    private var gpsStatus = "WAITING"
    private var currentCadenceSpm: Double = 0.0
    private val visitedHexIds = LinkedHashSet<String>()
    private val activePolylines = mutableListOf<MutableList<List<Double>>>()

    private var tickerJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        db = TerrastepDatabase.getInstance(this)
        createNotificationChannel()

        stepManager = StepCounterManager(this) { steps, _, cadence ->
            currentCadenceSpm = cadence
            updateNotification(steps, totalDistanceMeters)
            broadcastTelemetry()
        }

        locationManager = LocationTrackerManager(this, { state ->
            gpsStatus = state
            broadcastTelemetry()
        }) { loc ->
            handleIncomingLocation(loc)
        }
    }

    fun startLocationPreview(): Map<String, Any?> {
        locationManager.startTracking()
        return buildTelemetryPayload()
    }

    fun stopLocationPreview() {
        if (status == "IDLE") locationManager.stopTracking()
    }

    fun getDiagnostics(): Map<String, Any?> {
        return mapOf(
            "hasStepCounter" to stepManager.hasStepCounterHardware(),
            "hasStepDetector" to stepManager.hasStepDetectorHardware(),
            "rawBootSteps" to stepManager.getLastRawBootSteps(),
            "sessionBaselineSteps" to stepManager.getInitialBaseline(),
            "sessionSteps" to stepManager.getCurrentSessionSteps(),
            "status" to status,
            "lastLat" to lastRawLocation?.latitude,
            "lastLon" to lastRawLocation?.longitude,
            "lastAccuracyMeters" to lastRawLocation?.accuracy?.toDouble()
        )
    }

    fun startWalk(): Map<String, Any?> {
        if (status == "RECORDING" || status == "PAUSED") {
            return buildTelemetryPayload()
        }
        val sessionId = UUID.randomUUID().toString()
        currentSessionId = sessionId
        startTimeUtcMs = System.currentTimeMillis()
        val nowElapsed = SystemClock.elapsedRealtime()
        startElapsedRealtimeMs = nowElapsed
        segmentStartElapsedMs = nowElapsed
        accumulatedMovingMsBeforePause = 0L
        segmentIndex = 0
        sequenceNumber = 0
        totalDistanceMeters = 0.0
        lastAcceptedLocation = null
        distanceAnchorSteps = stepManager.getCurrentSessionSteps()
        visitedHexIds.clear()
        activePolylines.clear()
        activePolylines.add(mutableListOf())

        val fmt = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.US)
        sessionTitle = "Abbottabad Walk (${fmt.format(Date(startTimeUtcMs))})"
        status = "RECORDING"

        promoteToForeground()
        stepManager.startSession()
        locationManager.startTracking()

        serviceScope.launch {
            db.walkDao().upsertSession(
                WalkSessionEntity(
                    sessionId = sessionId,
                    title = sessionTitle,
                    startTimeUtcMs = startTimeUtcMs,
                    endTimeUtcMs = null,
                    elapsedDurationMs = 0L,
                    movingDurationMs = 0L,
                    totalSteps = 0,
                    baselineStepsAtStart = stepManager.getInitialBaseline(),
                    totalDistanceMeters = 0.0,
                    visitedHexIdsJson = "[]",
                    gpxFilePath = null,
                    status = status
                )
            )
        }

        startTicker()
        broadcastTelemetry()
        return buildTelemetryPayload()
    }

    fun pauseWalk(): Map<String, Any?> {
        if (status != "RECORDING") return buildTelemetryPayload()
        val nowElapsed = SystemClock.elapsedRealtime()
        accumulatedMovingMsBeforePause += (nowElapsed - segmentStartElapsedMs).coerceAtLeast(0L)
        status = "PAUSED"
        stepManager.pauseSession()
        lastAcceptedLocation = null
        distanceAnchorSteps = stepManager.getCurrentSessionSteps()
        updateNotification(stepManager.getCurrentSessionSteps(), totalDistanceMeters)
        persistSessionCheckpoint()
        broadcastTelemetry()
        return buildTelemetryPayload()
    }

    fun resumeWalk(): Map<String, Any?> {
        if (status != "PAUSED") return buildTelemetryPayload()
        segmentStartElapsedMs = SystemClock.elapsedRealtime()
        segmentIndex += 1
        activePolylines.add(mutableListOf())
        lastAcceptedLocation = null
        distanceAnchorSteps = stepManager.getCurrentSessionSteps()
        status = "RECORDING"
        stepManager.resumeSession()
        updateNotification(stepManager.getCurrentSessionSteps(), totalDistanceMeters)
        persistSessionCheckpoint()
        broadcastTelemetry()
        return buildTelemetryPayload()
    }

    suspend fun finishWalk(): Map<String, Any?> {
        val sessionId = currentSessionId ?: return emptyMap()
        val nowElapsed = SystemClock.elapsedRealtime()
        if (status == "RECORDING") {
            accumulatedMovingMsBeforePause += (nowElapsed - segmentStartElapsedMs).coerceAtLeast(0L)
        }
        val elapsedMs = (nowElapsed - startElapsedRealtimeMs).coerceAtLeast(0L)
        val movingMs = accumulatedMovingMsBeforePause
        val finalSteps = stepManager.getCurrentSessionSteps()

        status = "IDLE"
        tickerJob?.cancel()
        stepManager.stopSession()
        locationManager.stopTracking()

        val result = withContext(Dispatchers.IO) {
            val points = db.walkDao().getTrackPointsForSession(sessionId)
            val hexJson = JSONArray(visitedHexIds.toList()).toString()
            val completedEntity = WalkSessionEntity(
                sessionId = sessionId,
                title = sessionTitle,
                startTimeUtcMs = startTimeUtcMs,
                endTimeUtcMs = System.currentTimeMillis(),
                elapsedDurationMs = elapsedMs,
                movingDurationMs = movingMs,
                totalSteps = finalSteps,
                baselineStepsAtStart = stepManager.getInitialBaseline(),
                totalDistanceMeters = totalDistanceMeters,
                visitedHexIdsJson = hexJson,
                gpxFilePath = null,
                status = "COMPLETED"
            )
            val gpxFile = GpxFileWriter.writeSessionGpx(this@WalkRecorderService, completedEntity, points)
            val finalEntity = completedEntity.copy(gpxFilePath = gpxFile.absolutePath)
            db.walkDao().upsertSession(finalEntity)
            mapOf(
                "sessionId" to finalEntity.sessionId,
                "title" to finalEntity.title,
                "totalSteps" to finalEntity.totalSteps,
                "totalDistanceMeters" to finalEntity.totalDistanceMeters,
                "movingDurationMs" to finalEntity.movingDurationMs,
                "gpxFilePath" to gpxFile.absolutePath,
                "pointCount" to points.size,
                "hexCount" to visitedHexIds.size
            )
        }

        currentSessionId = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        broadcastTelemetry()
        return result
    }

    private fun handleIncomingLocation(loc: Location) {
        // Ignore stale/out-of-order fixes (including duplicates from the two providers).
        val ageMs = (SystemClock.elapsedRealtimeNanos() - loc.elapsedRealtimeNanos) / 1_000_000
        if (!GpsFixPolicy.isFresh(ageMs)) return
        if (lastRawLocation != null && loc.elapsedRealtimeNanos <= lastRawLocation!!.elapsedRealtimeNanos) return
        val previousRaw = lastRawLocation
        if (previousRaw != null && previousRaw.hasAccuracy() && previousRaw.accuracy <= 25f &&
            (!loc.hasAccuracy() || loc.accuracy > 25f) &&
            (SystemClock.elapsedRealtimeNanos() - previousRaw.elapsedRealtimeNanos) / 1_000_000 < 15000) return
        lastRawLocation = loc
        gpsStatus = if (!loc.hasAccuracy() || loc.accuracy > 25f) "POOR_ACCURACY" else "FIX"
        if (status != "RECORDING") {
            broadcastTelemetry()
            return
        }
        val sessionId = currentSessionId ?: return

        // Accuracy filter: ignore fixes worse than 25m
        if (!loc.hasAccuracy() || loc.accuracy > 25.0f) {
            broadcastTelemetry()
            return
        }

        val steps = stepManager.getCurrentSessionSteps()
        val hasStepHardware = stepManager.hasStepCounterHardware() || stepManager.hasStepDetectorHardware()
        // Never draw a route or accumulate distance while the pedometer says stationary.
        // Drop the old anchor after stopping so drift during rest cannot become a later leg.
        if (hasStepHardware && !stepManager.hasRecentStepActivity()) {
            lastAcceptedLocation = null
            distanceAnchorSteps = steps
            broadcastTelemetry()
            return
        }
        val prev = lastAcceptedLocation
        if (prev != null) {
            val distDelta = prev.distanceTo(loc).toDouble()
            val accuracy = maxOf(prev.accuracy, loc.accuracy).toDouble()
            if (!GpsFixPolicy.acceptsWalking(
                    distDelta, loc.elapsedRealtimeNanos - prev.elapsedRealtimeNanos,
                    accuracy, hasStepHardware, steps - distanceAnchorSteps,
                    if (loc.hasSpeed()) loc.speed.toDouble() else null,
                    if (loc.hasSpeedAccuracy()) loc.speedAccuracyMetersPerSecond.toDouble() else null
                )) {
                // A large rejected discontinuity must not remain the anchor indefinitely.
                if (distDelta > maxOf(10.0, accuracy * 2) &&
                    (!hasStepHardware || distDelta > (steps - distanceAnchorSteps) * 1.8 + 1.2)) {
                    lastAcceptedLocation = null
                    distanceAnchorSteps = steps
                }
                broadcastTelemetry()
                return
            }
            totalDistanceMeters += distDelta
        } else if (activePolylines.lastOrNull()?.isNotEmpty() == true) {
            // Resume after a stationary gap without a line across GPS drift.
            segmentIndex += 1
            activePolylines.add(mutableListOf())
        }

        lastAcceptedLocation = loc
        distanceAnchorSteps = steps
        sequenceNumber += 1
        val hexId = HexGridEngine.latLonToHexId(loc.latitude, loc.longitude)
        visitedHexIds.add(hexId)

        if (activePolylines.isEmpty()) {
            activePolylines.add(mutableListOf())
        }
        activePolylines.last().add(listOf(loc.longitude, loc.latitude))

        val pointEntity = TrackPointEntity(
            sessionId = sessionId,
            segmentIndex = segmentIndex,
            sequenceNumber = sequenceNumber,
            latitude = loc.latitude,
            longitude = loc.longitude,
            altitudeMeters = if (loc.hasAltitude()) loc.altitude else 1255.0,
            horizontalAccuracyMeters = if (loc.hasAccuracy()) loc.accuracy else 5.0f,
            speedMetersPerSec = if (loc.hasSpeed()) loc.speed else 1.2f,
            timestampUtcMs = System.currentTimeMillis(),
            elapsedRealtimeMs = SystemClock.elapsedRealtime(),
            cumulativeSessionSteps = stepManager.getCurrentSessionSteps(),
            hexCellId = hexId
        )

        serviceScope.launch {
            db.walkDao().insertTrackPoint(pointEntity)
            persistSessionCheckpoint()
        }
        broadcastTelemetry()
    }

    private fun persistSessionCheckpoint() {
        val sessionId = currentSessionId ?: return
        val nowElapsed = SystemClock.elapsedRealtime()
        val movingMs = if (status == "RECORDING") {
            accumulatedMovingMsBeforePause + (nowElapsed - segmentStartElapsedMs).coerceAtLeast(0L)
        } else {
            accumulatedMovingMsBeforePause
        }
        val elapsedMs = (nowElapsed - startElapsedRealtimeMs).coerceAtLeast(0L)
        val hexJson = JSONArray(visitedHexIds.toList()).toString()

        serviceScope.launch {
            db.walkDao().upsertSession(
                WalkSessionEntity(
                    sessionId = sessionId,
                    title = sessionTitle,
                    startTimeUtcMs = startTimeUtcMs,
                    endTimeUtcMs = null,
                    elapsedDurationMs = elapsedMs,
                    movingDurationMs = movingMs,
                    totalSteps = stepManager.getCurrentSessionSteps(),
                    baselineStepsAtStart = stepManager.getInitialBaseline(),
                    totalDistanceMeters = totalDistanceMeters,
                    visitedHexIdsJson = hexJson,
                    gpxFilePath = null,
                    status = status
                )
            )
        }
    }

    private fun startTicker() {
        tickerJob?.cancel()
        tickerJob = serviceScope.launch(Dispatchers.Main) {
            while (isActive && (status == "RECORDING" || status == "PAUSED")) {
                broadcastTelemetry()
                delay(1000L)
            }
        }
    }

    private fun broadcastTelemetry() {
        val payload = buildTelemetryPayload()
        Handler(Looper.getMainLooper()).post {
            telemetryListener?.invoke(payload)
        }
    }

    fun buildTelemetryPayload(): Map<String, Any?> {
        val nowElapsed = SystemClock.elapsedRealtime()
        val movingMs = when (status) {
            "RECORDING" -> accumulatedMovingMsBeforePause + (nowElapsed - segmentStartElapsedMs).coerceAtLeast(0L)
            "PAUSED" -> accumulatedMovingMsBeforePause
            else -> 0L
        }
        val elapsedMs = if (status == "IDLE") 0L else (nowElapsed - startElapsedRealtimeMs).coerceAtLeast(0L)
        val loc = lastRawLocation
        val fixAgeMs = loc?.let { (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1_000_000 }
        val hasFix = loc != null && fixAgeMs != null && fixAgeMs in 0..15000
        val currentHex = if (loc != null) HexGridEngine.latLonToHexId(loc.latitude, loc.longitude) else "h3r9_0_0"

        val hexPolygons = visitedHexIds.map { hexId ->
            mapOf(
                "hexId" to hexId,
                "ring" to HexGridEngine.hexIdToBoundaryLatLon(hexId).map { listOf(it.second, it.first) }
            )
        }

        return mapOf(
            "sessionId" to currentSessionId,
            "status" to status,
            "elapsedDurationMs" to elapsedMs,
            "movingDurationMs" to movingMs,
            "steps" to stepManager.getCurrentSessionSteps(),
            "rawBootSteps" to stepManager.getLastRawBootSteps(),
            "cadenceSpm" to currentCadenceSpm,
            "distanceMeters" to totalDistanceMeters,
            "latitude" to (loc?.latitude ?: 34.1688),
            "longitude" to (loc?.longitude ?: 73.2215),
            "hasLocationFix" to hasFix,
            "gpsStatus" to (if (!hasFix && gpsStatus == "FIX") "WAITING" else gpsStatus),
            "accuracyMeters" to (loc?.accuracy?.toDouble() ?: 0.0),
            "currentHexId" to currentHex,
            "visitedHexCount" to visitedHexIds.size,
            "polylines" to activePolylines,
            "hexPolygons" to hexPolygons,
            "hasStepSensor" to (stepManager.hasStepCounterHardware() || stepManager.hasStepDetectorHardware())
        )
    }

    private fun promoteToForeground() {
        val notification = buildNotification(0, 0.0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(steps: Int, distanceM: Double) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(steps, distanceM))
    }

    private fun buildNotification(steps: Int, distanceM: Double): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val distKm = String.format(Locale.US, "%.2f km", distanceM / 1000.0)
        val stateLabel = if (status == "PAUSED") "Paused" else "Recording Walk"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Terrastep • $stateLabel")
            .setContentText("$steps steps • $distKm")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Terrastep Active Walk Recorder",
                NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
