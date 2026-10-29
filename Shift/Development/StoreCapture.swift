#if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
import SwiftUI
import GRDB
import WidgetKit

/// Seeds only a dedicated simulator's local database. No Supabase session or customer data is used.
enum StoreCapture {
    static var settings: UserSettings {
        var value = UserSettings.default
        value.theme = "dark"; value.distanceUnit = "km"; value.weightUnit = "kg"
        value.hasCompletedOnboarding = true; value.weeklyFrequencyGoal = 4; value.dailyStepGoal = 10_000
        return value
    }
    static let exercises = [
        ("Bench press", "chest", "barbell", 70.0), ("Incline press", "chest", "dumbbell", 26.0),
        ("Lat pulldown", "back", "cable", 55.0), ("Seated row", "back", "cable", 50.0),
        ("Shoulder press", "shoulders", "dumbbell", 22.0), ("Lateral raise", "shoulders", "dumbbell", 10.0),
        ("Squat", "quadriceps", "barbell", 90.0), ("Romanian deadlift", "hamstrings", "barbell", 80.0),
        ("Leg press", "quadriceps", "machine", 140.0), ("Leg curl", "hamstrings", "machine", 40.0),
        ("Biceps curl", "biceps", "dumbbell", 14.0), ("Triceps pushdown", "triceps", "cable", 25.0)
    ]
    static func date(_ days: Int, hour: Int = 8) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }
    static var routeActivity: EnduranceActivity { activity(index: 0, day: -1) }
    static func activity(index: Int, day: Int) -> EnduranceActivity {
        let sport: EnduranceSport = index % 5 == 2 ? .cycle : index % 3 == 1 ? .walk : .run
        let started = date(day, hour: index % 2 == 0 ? 7 : 18)
        let distance = sport == .cycle ? 18_400 + Double(index % 9) * 1_100 : sport == .walk ? 2_800 + Double(index % 6) * 420 : 5_000 + Double(index % 7) * 650
        let seconds = distance * (sport == .cycle ? 0.17 : sport == .walk ? 0.73 : 0.335)
        let coordinates: [(Double, Double)] = [(51.5267,-0.1518),(51.5278,-0.1589),(51.5314,-0.1632),(51.5357,-0.1612),(51.5398,-0.1546),(51.5405,-0.1485),(51.5377,-0.1453),(51.5332,-0.1451),(51.5290,-0.1462),(51.5267,-0.1518)]
        let route = coordinates.enumerated().map { i,p in
            EnduranceRoutePoint(latitude: p.0, longitude: p.1, altitude: 31 + Double(i % 3) * 2, timestamp: started.timeIntervalSince1970 + seconds * Double(i) / 9,
                horizontalAccuracy: 5, verticalAccuracy: 4, activeSeconds: seconds * Double(i) / 9, segment: 0)
        }
        return EnduranceActivity(id: "capture-activity-\(index)", userId: StoreCaptureConfiguration.owner, sport: sport,
            title: sport == .run ? "Regent’s Park run" : sport == .walk ? "Lunch break walk" : "Weekend park ride", startedAt: started,
            endedAt: started.addingTimeInterval(seconds), activeSeconds: seconds, distanceMeters: distance, elevationGainMeters: sport == .cycle ? 116 : 28,
            route: route, splits: (0..<Int(distance / 1_000)).map { .init(number: $0 + 1, distanceMeters: 1_000, activeSeconds: seconds / (distance / 1_000) + Double($0 % 3) * 2) }, notes: "Easy effort. A little fresh air makes all the difference.")
    }
    static func seed() async throws {
        let owner = StoreCaptureConfiguration.owner
        UserDefaults.standard.set(owner, forKey: "shift.cachedUserId")
        UserDefaults.standard.set(StoreCaptureConfiguration.screen == "strength" || StoreCaptureConfiguration.screen == "plans" || StoreCaptureConfiguration.screen == "workout" ? "strength" : "endurance", forKey: "shift.trainingMode")
        WidgetSnapshot.setActiveUserId(owner)
        let configuration = settings
        try await AppDatabase.shared.dbPool.write { db in
            // This capture account exists only in the new, dedicated simulator.
            for table in ["session_sets", "workout_sessions", "plan_exercises", "workout_plans", "weight_entries", "exercise_goals", "endurance_activities", "endurance_goals", "training_sessions", "mutation_queue"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            let stamp = ISO8601DateFormatter.shared.string(from: date(-180))
            let settingsJSON = String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
            try db.execute(sql: "INSERT OR REPLACE INTO profiles(id,name,age,weight,settings,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",arguments: [owner,"Alex Morgan",29,76.4,settingsJSON,stamp,stamp])
            for (i,e) in exercises.enumerated() {
                try db.execute(sql:"INSERT OR IGNORE INTO muscle_groups(id,name,slug) VALUES (?,?,?)",arguments:[e.1,e.1.capitalized,e.1])
                try db.execute(sql:"INSERT OR REPLACE INTO exercises(id,name,slug,primary_muscle_id,equipment,is_built_in) VALUES (?,?,?,?,?,1)",arguments:["capture-ex-\(i)",e.0,e.0.lowercased().replacingOccurrences(of:" ",with:"-"),e.1,e.2])
            }
            for (i,name) in ["Upper body A", "Lower body", "Upper body B", "Full body"].enumerated() {
                try WorkoutPlan(id:"capture-plan-\(i)",userId:owner,name:name,notes:"Build strength, one good session at a time.",position:i,createdAt:date(-90)).insert(db)
                let indices = i == 1 ? [6,7,8,9] : i == 2 ? [2,3,4,5,10] : [0,1,2,3,4,11]
                for (j,index) in indices.enumerated() {
                    try db.execute(sql:"INSERT INTO plan_exercises(id,plan_id,exercise_id,position,target_sets,target_reps_min,target_reps_max,target_weight,rest_seconds) VALUES (?,?,?,?,3,8,12,?,90)",arguments:["capture-pe-\(i)-\(j)","capture-plan-\(i)","capture-ex-\(index)",j,exercises[index].3])
                }
            }
            for index in 0..<64 {
                let days = index == 0 ? 0 : index == 1 ? -1 : -(index * 2 + index / 4)
                let start = date(days, hour: 7), end = start.addingTimeInterval(3_060)
                let plan = index % 3
                try db.execute(sql:"INSERT INTO workout_sessions(id,user_id,plan_id,name,started_at,ended_at) VALUES (?,?,?,?,?,?)",arguments:["capture-workout-\(index)",owner,"capture-plan-\(plan)",["Upper body A","Lower body","Upper body B"][plan],ISO8601DateFormatter.shared.string(from:start),ISO8601DateFormatter.shared.string(from:end)])
                for exercise in (plan == 1 ? [6,7,8,9] : [0,1,2,3,4,11]) {
                    for set in 1...3 {
                        let weight = exercises[exercise].3 - Double(min(12,index / 4)) * 2.5
                        try db.execute(sql:"INSERT INTO session_sets(id,session_id,exercise_id,set_number,reps,weight,is_completed,completed_at) VALUES (?,?,?,?,?,?,1,?)",arguments:["capture-set-\(index)-\(exercise)-\(set)","capture-workout-\(index)","capture-ex-\(exercise)",set,10,weight,ISO8601DateFormatter.shared.string(from:end)])
                    }
                }
            }
            let start = Date().addingTimeInterval(-1_182)
            try db.execute(sql:"INSERT INTO workout_sessions(id,user_id,plan_id,name,started_at) VALUES ('capture-active',?,'capture-plan-0','Upper body A',?)",arguments:[owner,ISO8601DateFormatter.shared.string(from:start)])
            for ex in [0,1,2,3] { for set in 1...3 {
                try db.execute(sql:"INSERT INTO session_sets(id,session_id,exercise_id,set_number,reps,weight,is_completed,completed_at) VALUES (?,'capture-active',?,?,?,?,?,?)",arguments:["capture-active-\(ex)-\(set)","capture-ex-\(ex)",set,10,exercises[ex].3,ex == 0 || ex == 1 && set == 1,ISO8601DateFormatter.shared.string(from:Date())])
            } }
            for index in 0..<28 {
                try WeightEntry(id:"capture-weight-\(index)",userId:owner,weight:80.2 - Double(index)*0.14,recordedAt:date(-84 + index*3)).insert(db)
            }
            for index in 0..<84 {
                var item = activity(index:index,day:index < 4 ? (index < 2 ? -1 : 0) : -(index*2+1))
                if index < 4 {
                    item.sport = index % 2 == 0 ? .run : .walk
                    item.title = item.sport == .run ? "Regent’s Park run" : "Lunch break walk"
                    item.distanceMeters = [5_000.0,4_000,5_200,4_200][index]
                    item.activeSeconds = item.distanceMeters * (item.sport == .run ? 0.335 : 0.73)
                    item.endedAt = item.startedAt.addingTimeInterval(item.activeSeconds)
                    item.route = []
                    item.splits = []
                }
                try EnduranceStore.upsert(item,in:db)
            }
            for goal in [EnduranceGoal(userId:owner,sport:nil,metric:.distance,target:30_000,period:.week), EnduranceGoal(userId:owner,sport:.run,metric:.activities,target:3,period:.week), EnduranceGoal(userId:owner,sport:.walk,metric:.duration,target:7_200,period:.week)] { try EnduranceStore.upsert(goal,in:db) }
            for (i,offset) in [1,2,3,5,6].enumerated() {
                let sport:EnduranceSport = i == 3 ? .cycle : i % 2 == 0 ? .run : .walk
                let item = TrainingSession(userId:owner,title:sport == .run ? "Easy park run" : sport == .walk ? "Make time for a walk" : "Weekend ride",scheduledAt:date(offset,hour:18),kind:.endurance,sport:sport,targetSeconds:sport == .cycle ? 3_600 : 1_800,programID:"capture-week")
                try EnduranceStore.upsert(item,in:db)
            }
            for day in [1,3,5] { try EnduranceStore.upsert(TrainingSession(userId:owner,title:"Upper body A",scheduledAt:date(day,hour:7),kind:.strength,targetSeconds:3_000),in:db) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct StoreCaptureRoot: View {
    @State private var ready = false
    @State private var failure: String?
    var body: some View {
        Group {
            if let failure { Text(failure).textSelection(.enabled) }
            else if ready {
                switch StoreCaptureConfiguration.screen {
                case "weather-changes": NavigationStack { WeatherChangesView() }
                case "widgets": StoreCaptureWidgetsView()
                case "route": NavigationStack { EnduranceDetailView(activity: StoreCapture.routeActivity) }
                case "progress": NavigationStack { EnduranceProgressView() }
                case "calendar": NavigationStack { TrainingCalendarView() }
                case "workout": NavigationStack { WorkoutView(sessionId:"capture-active") }
                case "plan": NavigationStack { PlanEditorView(plan: WorkoutPlan(id:"capture-plan-0",userId:StoreCaptureConfiguration.owner,name:"Upper body A",createdAt:StoreCapture.date(-90)),onDismiss:{ _ in }) }
                case "planner": NavigationStack { EndurancePlannerView() }
                case "coach": NavigationStack { EnduranceCoachView() }
                case "health": EnduranceImportView()
                case "body": NavigationStack { ProgressTrackingView() }
                case "exercises": NavigationStack { ExercisesView() }
                default: MainTabView()
                }
            } else { ProgressView() }
        }.task {
            guard !ready else { return }
            do { try await StoreCapture.seed(); ready = true } catch { failure = error.localizedDescription; print("CAPTURE SEED ERROR",error) }
        }
    }
}
#endif
