package com.terrastep.fyp.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface WalkDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSession(session: WalkSessionEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTrackPoint(point: TrackPointEntity): Long

    @Query("SELECT * FROM walk_sessions WHERE sessionId = :sessionId LIMIT 1")
    suspend fun getSession(sessionId: String): WalkSessionEntity?

    @Query("SELECT * FROM walk_sessions ORDER BY startTimeUtcMs DESC")
    suspend fun getAllSessions(): List<WalkSessionEntity>

    @Query("SELECT * FROM track_points WHERE sessionId = :sessionId ORDER BY segmentIndex ASC, sequenceNumber ASC")
    suspend fun getTrackPointsForSession(sessionId: String): List<TrackPointEntity>

    @Query("DELETE FROM walk_sessions WHERE sessionId = :sessionId")
    suspend fun deleteSession(sessionId: String)

    @Query("DELETE FROM track_points WHERE sessionId = :sessionId")
    suspend fun deleteTrackPoints(sessionId: String)
}
