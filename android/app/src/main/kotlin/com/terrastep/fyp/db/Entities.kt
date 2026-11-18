package com.terrastep.fyp.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "walk_sessions")
data class WalkSessionEntity(
    @PrimaryKey val sessionId: String,
    val title: String,
    val startTimeUtcMs: Long,
    val endTimeUtcMs: Long?,
    val elapsedDurationMs: Long,
    val movingDurationMs: Long,
    val totalSteps: Int,
    val baselineStepsAtStart: Long?,
    val totalDistanceMeters: Double,
    val visitedHexIdsJson: String, // Inert legacy column; kept to preserve existing Room v1 data.
    val gpxFilePath: String?,
    val status: String // RECORDING, PAUSED, COMPLETED
)

@Entity(
    tableName = "track_points",
    indices = [Index(value = ["sessionId", "segmentIndex", "sequenceNumber"])]
)
data class TrackPointEntity(
    @PrimaryKey(autoGenerate = true) val pointId: Long = 0,
    val sessionId: String,
    val segmentIndex: Int,
    val sequenceNumber: Int,
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double,
    val horizontalAccuracyMeters: Float,
    val speedMetersPerSec: Float,
    val timestampUtcMs: Long,
    val elapsedRealtimeMs: Long,
    val cumulativeSessionSteps: Int,
    val hexCellId: String // Inert legacy column; new points store an empty string.
)
