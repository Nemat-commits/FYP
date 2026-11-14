package com.terrastep.fyp.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock

class StepCounterManager(
    context: Context,
    private val onStepUpdated: (sessionSteps: Int, rawBootSteps: Long, cadenceSpm: Double) -> Unit
) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val stepCounterSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    private val stepDetectorSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

    private var isRecording = false
    private var isPaused = false

    private var initialBootBaseline: Long? = null
    private var currentSegmentBaseline: Long? = null
    private var accumulatedStepsBeforePause: Int = 0
    private var currentSessionSteps: Int = 0
    private var lastRawSensorValue: Long = 0L

    // Rolling 60-second step timestamps (monotonic ms) for live cadence calculation
    private val recentStepTimestampsMs = ArrayDeque<Long>()

    fun hasStepCounterHardware(): Boolean = stepCounterSensor != null
    fun hasStepDetectorHardware(): Boolean = stepDetectorSensor != null
    fun getLastRawBootSteps(): Long = lastRawSensorValue
    fun getInitialBaseline(): Long? = initialBootBaseline
    fun getCurrentSessionSteps(): Int = currentSessionSteps

    fun startSession() {
        accumulatedStepsBeforePause = 0
        currentSessionSteps = 0
        initialBootBaseline = null
        currentSegmentBaseline = null
        recentStepTimestampsMs.clear()
        isRecording = true
        isPaused = false
        registerSensors()
    }

    fun pauseSession() {
        if (!isRecording || isPaused) return
        accumulatedStepsBeforePause = currentSessionSteps
        currentSegmentBaseline = null
        isPaused = true
    }

    fun resumeSession() {
        if (!isRecording || !isPaused) return
        currentSegmentBaseline = null
        isPaused = false
    }

    fun stopSession() {
        isRecording = false
        isPaused = false
        sensorManager.unregisterListener(this)
    }

    private fun registerSensors() {
        sensorManager.unregisterListener(this)
        stepCounterSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
        stepDetectorSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST)
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || !isRecording) return
        val nowElapsedMs = SystemClock.elapsedRealtime()

        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> {
                val rawValue = event.values[0].toLong()
                lastRawSensorValue = rawValue
                if (initialBootBaseline == null) {
                    initialBootBaseline = rawValue
                }
                if (isPaused) return

                if (currentSegmentBaseline == null || rawValue < currentSegmentBaseline!!) {
                    currentSegmentBaseline = rawValue
                }
                val delta = (rawValue - currentSegmentBaseline!!).toInt().coerceAtLeast(0)
                val previousSteps = currentSessionSteps
                currentSessionSteps = accumulatedStepsBeforePause + delta

                val addedSteps = (currentSessionSteps - previousSteps).coerceAtLeast(0)
                repeat(addedSteps.coerceAtMost(20)) {
                    recentStepTimestampsMs.addLast(nowElapsedMs)
                }
                pruneOldStepTimestamps(nowElapsedMs)
                onStepUpdated(currentSessionSteps, rawValue, computeCadence(nowElapsedMs))
            }

            Sensor.TYPE_STEP_DETECTOR -> {
                if (isPaused) return
                // Fallback only if hardware TYPE_STEP_COUNTER is missing on the device
                if (stepCounterSensor == null && event.values.isNotEmpty() && event.values[0] == 1.0f) {
                    currentSessionSteps += 1
                    lastRawSensorValue = currentSessionSteps.toLong()
                    recentStepTimestampsMs.addLast(nowElapsedMs)
                    pruneOldStepTimestamps(nowElapsedMs)
                    onStepUpdated(currentSessionSteps, lastRawSensorValue, computeCadence(nowElapsedMs))
                }
            }
        }
    }

    private fun pruneOldStepTimestamps(nowElapsedMs: Long) {
        while (recentStepTimestampsMs.isNotEmpty() && nowElapsedMs - recentStepTimestampsMs.first() > 30_000L) {
            recentStepTimestampsMs.removeFirst()
        }
    }

    private fun computeCadence(nowElapsedMs: Long): Double {
        pruneOldStepTimestamps(nowElapsedMs)
        if (recentStepTimestampsMs.size < 2) return 0.0
        val windowSec = ((nowElapsedMs - recentStepTimestampsMs.first()).coerceAtLeast(5_000L)) / 1000.0
        return (recentStepTimestampsMs.size / windowSec) * 60.0
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
