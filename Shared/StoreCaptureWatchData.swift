#if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
import Foundation

enum StoreCaptureWatchData {
    static var gymExercises: [WatchSessionExercise] {
        [
            .init(exerciseId: "capture-ex-0", exerciseName: "Bench press", equipment: "barbell", completedSets: 2, totalSets: 3),
            .init(exerciseId: "capture-ex-1", exerciseName: "Seated row", equipment: "cable", completedSets: 3, totalSets: 3)
        ]
    }
    static var summary: EnduranceWidgetData {
        .init(weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start,
            distanceMeters: 18_400, activeSeconds: 9_403, activities: 4, distanceUnit: "km", distanceGoalMeters: 30_000,
            runMeters: 10_200, walkMeters: 8_200, cycleMeters: 0,
            nextSessions: [.init(userId: StoreCaptureConfiguration.owner,title: "Easy park run", scheduledAt: Date().addingTimeInterval(86_400),kind: .endurance,sport: .run,targetSeconds:1_800)])
    }
    static var context: WatchContext {
        .init(plans: [.init(id:"capture-plan-0",name:"Upper body A",exercises:[.init(id:"capture-pe",exerciseId:"capture-ex-0",exerciseName:"Bench press",equipment:"barbell",targetSets:3,targetRepsMin:8,targetRepsMax:12,targetWeight:70,restSeconds:90,position:0)])],recentExercises:[],activeSession:nil,lastCompletedSession:nil,
            settings:.init(weightUnit:"kg",defaultWeightIncrement:2.5,restTimerEnabled:true,restTimerDurationSeconds:90),userId:StoreCaptureConfiguration.owner,
            snapshot:.init(workoutsThisWeek:2,weeklyGoal:4,stepsToday:8_642,stepGoal:10_000,workedOutToday:true,currentStreak:6,streakUnit:"weeks",updatedAt:Date(),weekStart:summary.weekStart),
            schemaVersion:2,generatedAt:Date(),isSignedIn:true,
            endurance:.init(summary:summary,goals:[.init(id:"distance",title:"Weekly distance",progress:18.4,target:30,unit:"km")],routes:[.init(id:"park",title:"Regent’s Park loop",sport:.run,distanceMeters:5_000)],phoneRecording:false))
    }
}
#endif
