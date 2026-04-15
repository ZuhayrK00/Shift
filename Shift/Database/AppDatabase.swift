import Foundation
@preconcurrency import GRDB

// MARK: - AppDatabase

/// Manages the local SQLite database via a GRDB DatabasePool.
/// All repositories access the database through `AppDatabase.shared.dbPool`.
final class AppDatabase {

    // MARK: Shared singleton

    static let shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    // MARK: Storage

    let dbPool: DatabasePool

    // MARK: Init

    init() throws {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let databaseURL = documentsURL.appendingPathComponent("shift.db")

        // GRDB writer config
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL mode for better read/write concurrency
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
        try migrator.migrate(dbPool)
    }

    // MARK: - Migrator

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Wipe the database on schema changes during development.
        // Remove this line once real users exist and replace with proper migrations.
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("createTables") { db in
            // muscle_groups
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS muscle_groups (
                    id   TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    slug TEXT NOT NULL UNIQUE
                )
            """)

            // exercises
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS exercises (
                    id                    TEXT PRIMARY KEY NOT NULL,
                    name                  TEXT NOT NULL,
                    slug                  TEXT NOT NULL,
                    instructions          TEXT,
                    primary_muscle_id     TEXT NOT NULL,
                    secondary_muscle_ids  TEXT NOT NULL DEFAULT '[]',
                    equipment             TEXT,
                    is_built_in           INTEGER NOT NULL DEFAULT 1,
                    created_by            TEXT,
                    image_url             TEXT,
                    secondary_image_url   TEXT,
                    level                 TEXT,
                    force                 TEXT,
                    mechanic              TEXT,
                    category              TEXT,
                    instructions_steps    TEXT,
                    body_part             TEXT,
                    description           TEXT
                )
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_exercises_primary_muscle
                    ON exercises (primary_muscle_id)
            """)

            // workout_plans
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workout_plans (
                    id         TEXT PRIMARY KEY NOT NULL,
                    user_id    TEXT NOT NULL,
                    name       TEXT NOT NULL,
                    notes      TEXT,
                    created_at TEXT NOT NULL
                )
            """)

            // plan_exercises
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS plan_exercises (
                    id               TEXT PRIMARY KEY NOT NULL,
                    plan_id          TEXT NOT NULL,
                    exercise_id      TEXT NOT NULL,
                    position         INTEGER NOT NULL DEFAULT 0,
                    target_sets      INTEGER NOT NULL DEFAULT 3,
                    target_reps_min  INTEGER,
                    target_reps_max  INTEGER,
                    target_weight    REAL,
                    rest_seconds     INTEGER,
                    group_id         TEXT
                )
            """)

            // workout_sessions
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workout_sessions (
                    id         TEXT PRIMARY KEY NOT NULL,
                    user_id    TEXT NOT NULL,
                    plan_id    TEXT,
                    name       TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    ended_at   TEXT,
                    notes      TEXT
                )
            """)

            // session_sets
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS session_sets (
                    id           TEXT PRIMARY KEY NOT NULL,
                    session_id   TEXT NOT NULL,
                    exercise_id  TEXT NOT NULL,
                    set_number   INTEGER NOT NULL,
                    reps         INTEGER NOT NULL DEFAULT 0,
                    weight       REAL,
                    rpe          REAL,
                    is_completed INTEGER NOT NULL DEFAULT 0,
                    completed_at TEXT,
                    set_type     TEXT NOT NULL DEFAULT 'normal',
                    group_id     TEXT
                )
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_session_sets_session
                    ON session_sets (session_id)
            """)

            // mutation_queue — offline write buffer drained by sync service
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS mutation_queue (
                    id         INTEGER PRIMARY KEY AUTOINCREMENT,
                    table_name TEXT NOT NULL,
                    op         TEXT NOT NULL,
                    payload    TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
            """)

            // profiles — mirrors public.profiles from Supabase; settings stored as JSON TEXT
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS profiles (
                    id                  TEXT PRIMARY KEY NOT NULL,
                    name                TEXT,
                    age                 INTEGER,
                    weight              REAL,
                    profile_picture_url TEXT,
                    settings            TEXT NOT NULL DEFAULT '{}',
                    created_at          TEXT NOT NULL,
                    updated_at          TEXT NOT NULL
                )
            """)
        }

        migrator.registerMigration("addExerciseGoals") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS exercise_goals (
                    id                     TEXT PRIMARY KEY NOT NULL,
                    user_id                TEXT NOT NULL,
                    exercise_id            TEXT NOT NULL,
                    target_weight_increase REAL NOT NULL,
                    baseline_weight        REAL NOT NULL,
                    deadline               TEXT NOT NULL,
                    is_completed           INTEGER NOT NULL DEFAULT 0,
                    completed_at           TEXT,
                    created_at             TEXT NOT NULL
                )
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_exercise_goals_exercise
                    ON exercise_goals (exercise_id)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_exercise_goals_user
                    ON exercise_goals (user_id)
            """)
        }

        migrator.registerMigration("addMissingIndexes") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workout_sessions_user_started
                    ON workout_sessions (user_id, started_at)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_session_sets_exercise
                    ON session_sets (exercise_id)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_plan_exercises_exercise
                    ON plan_exercises (exercise_id)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_plan_exercises_plan
                    ON plan_exercises (plan_id)
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_exercise_goals_user_completed
                    ON exercise_goals (user_id, is_completed)
            """)
        }

        migrator.registerMigration("addWeightEntries") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS weight_entries (
                    id          TEXT PRIMARY KEY NOT NULL,
                    user_id     TEXT NOT NULL,
                    weight      REAL NOT NULL,
                    unit        TEXT NOT NULL DEFAULT 'kg',
                    source      TEXT NOT NULL DEFAULT 'manual',
                    recorded_at TEXT NOT NULL,
                    created_at  TEXT NOT NULL
                )
            """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_weight_entries_user
                    ON weight_entries (user_id, recorded_at)
            """)
        }

        migrator.registerMigration("addSessionSetNotes") { db in
            try db.execute(sql: """
                ALTER TABLE session_sets ADD COLUMN notes TEXT
            """)
        }

        return migrator
    }
}
