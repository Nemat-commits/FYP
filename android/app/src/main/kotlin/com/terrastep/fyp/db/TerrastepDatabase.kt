package com.terrastep.fyp.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [WalkSessionEntity::class, TrackPointEntity::class],
    version = 1,
    exportSchema = false
)
abstract class TerrastepDatabase : RoomDatabase() {
    abstract fun walkDao(): WalkDao

    companion object {
        @Volatile
        private var INSTANCE: TerrastepDatabase? = null

        fun getInstance(context: Context): TerrastepDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    TerrastepDatabase::class.java,
                    "terrastep_local.db"
                ).fallbackToDestructiveMigration().build().also { INSTANCE = it }
            }
        }
    }
}
