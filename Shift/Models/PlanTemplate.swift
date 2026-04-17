import Foundation

// MARK: - Plan Template Data Model

struct PlanTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let level: PlanLevel
    let daysPerWeek: Int
    let days: [PlanTemplateDay]

    var category: String {
        switch daysPerWeek {
        case 1...2: return "Single Workouts"
        case 3: return "3-Day Splits"
        case 4: return "4-Day Splits"
        case 5: return "5-Day Splits"
        default: return "6-Day Splits"
        }
    }
}

enum PlanLevel: String {
    case beginner = "BEGINNER"
    case intermediate = "INTERMEDIATE"
    case advanced = "ADVANCED"
}

struct PlanTemplateDay: Identifiable {
    let id = UUID().uuidString
    let name: String
    let exercises: [PlanTemplateExercise]

    var exerciseCount: Int { exercises.count }
}

struct PlanTemplateExercise {
    let slug: String       // used for keyword matching against Exercise.name
    let sets: Int
    let repsMin: Int
    let repsMax: Int?
    let restSeconds: Int
    let groupTag: String?  // exercises with same non-nil groupTag form a superset
}

// MARK: - Plan Template Library
//
// All exercise slugs below are chosen to keyword-match the ExerciseDB
// exercise catalogue that populates the local database. Each slug is
// split on hyphens into keywords and scored against every exercise name
// to find the best match. When an exercise exists under a slightly
// different name (e.g. "dumbbell incline bench press" instead of
// "incline dumbbell press"), the keyword overlap still finds it.

struct PlanTemplateLibrary {

    static let all: [PlanTemplate] = [
        // --- BEGINNER ---
        fullBodyStrength,
        upperLowerBeginner,

        // --- INTERMEDIATE ---
        pushPullLegs,
        upperLowerIntermediate,
        fullBodyHypertrophy,

        // --- ADVANCED ---
        pushPullLegsAdvanced,
        broSplit,
    ]

    // MARK: - Beginner: Full Body Strength (3 days)

    static let fullBodyStrength = PlanTemplate(
        id: "tpl-full-body-strength",
        name: "Full Body Strength",
        description: "A simple 3-day full body program focused on the main compound lifts. Perfect for beginners looking to build a strength foundation.",
        level: .beginner,
        daysPerWeek: 3,
        days: [
            PlanTemplateDay(name: "Day A — Full Body", exercises: [
                .init(slug: "barbell-squat", sets: 3, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bench-press", sets: 3, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 3, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Day B — Full Body", exercises: [
                .init(slug: "barbell-deadlift", sets: 3, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-crunch", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Day C — Full Body", exercises: [
                .init(slug: "barbell-front-squat", sets: 3, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "barbell-bench-press", sets: 3, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "pull-up", sets: 3, repsMin: 5, repsMax: 8, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Beginner: Upper / Lower (4 days)

    static let upperLowerBeginner = PlanTemplate(
        id: "tpl-upper-lower-beginner",
        name: "Upper / Lower",
        description: "A balanced 4-day split alternating between upper and lower body. Great for beginners ready to move beyond full body training.",
        level: .beginner,
        daysPerWeek: 4,
        days: [
            PlanTemplateDay(name: "Upper A — Strength", exercises: [
                .init(slug: "barbell-bench-press", sets: 4, repsMin: 5, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 5, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-curl", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "triceps-pushdown", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
            ]),
            PlanTemplateDay(name: "Lower A — Strength", exercises: [
                .init(slug: "barbell-squat", sets: 4, repsMin: 5, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "leg-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Upper B — Hypertrophy", exercises: [
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-hammer-curl", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "chest-dip", sets: 2, repsMin: 8, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
            ]),
            PlanTemplateDay(name: "Lower B — Hypertrophy", exercises: [
                .init(slug: "barbell-front-squat", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-sumo-squat", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-crunch", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Intermediate: Push / Pull / Legs (6 days)

    static let pushPullLegs = PlanTemplate(
        id: "tpl-push-pull-legs",
        name: "Push / Pull / Legs",
        description: "The classic PPL split run twice per week. Each muscle group is hit twice with a mix of compound and isolation work. Ideal for intermediate lifters.",
        level: .intermediate,
        daysPerWeek: 6,
        days: [
            PlanTemplateDay(name: "Push A", exercises: [
                .init(slug: "barbell-bench-press", sets: 4, repsMin: 5, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "triceps-pushdown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "barbell-lying-triceps-extension", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
            ]),
            PlanTemplateDay(name: "Pull A", exercises: [
                .init(slug: "barbell-deadlift", sets: 3, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "pull-up", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "barbell-curl", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "dumbbell-hammer-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
            ]),
            PlanTemplateDay(name: "Legs A", exercises: [
                .init(slug: "barbell-squat", sets: 4, repsMin: 5, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "leg-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Push B", exercises: [
                .init(slug: "dumbbell-shoulder-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "chest-dip", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "triceps-pushdown", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Pull B", exercises: [
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss3"),
                .init(slug: "dumbbell-hammer-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss3"),
            ]),
            PlanTemplateDay(name: "Legs B", exercises: [
                .init(slug: "barbell-front-squat", sets: 3, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-sumo-squat", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Intermediate: Upper / Lower (4 days)

    static let upperLowerIntermediate = PlanTemplate(
        id: "tpl-upper-lower-intermediate",
        name: "Upper / Lower Power & Hypertrophy",
        description: "A 4-day upper/lower split combining heavy compound days with higher-rep hypertrophy days. Great for building both strength and size.",
        level: .intermediate,
        daysPerWeek: 4,
        days: [
            PlanTemplateDay(name: "Upper — Power", exercises: [
                .init(slug: "barbell-bench-press", sets: 4, repsMin: 4, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 4, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 3, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "pull-up", sets: 3, repsMin: 5, repsMax: 8, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-curl", sets: 2, repsMin: 8, repsMax: 10, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "chest-dip", sets: 2, repsMin: 8, repsMax: 10, restSeconds: 60, groupTag: "ss1"),
            ]),
            PlanTemplateDay(name: "Lower — Power", exercises: [
                .init(slug: "barbell-squat", sets: 4, repsMin: 4, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-deadlift", sets: 3, repsMin: 3, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "leg-press", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Upper — Hypertrophy", exercises: [
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "triceps-pushdown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
            ]),
            PlanTemplateDay(name: "Lower — Hypertrophy", exercises: [
                .init(slug: "barbell-front-squat", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-sumo-squat", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-crunch", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Intermediate: Full Body Hypertrophy (3 days)

    static let fullBodyHypertrophy = PlanTemplate(
        id: "tpl-full-body-hypertrophy",
        name: "Full Body Hypertrophy",
        description: "A 3-day full body program designed for muscle growth with moderate loads and higher rep ranges. Each session hits every major muscle group.",
        level: .intermediate,
        daysPerWeek: 3,
        days: [
            PlanTemplateDay(name: "Full Body A", exercises: [
                .init(slug: "barbell-bench-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-squat", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "barbell-curl", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "triceps-pushdown", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "cable-crunch", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Full Body B", exercises: [
                .init(slug: "dumbbell-shoulder-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Full Body C", exercises: [
                .init(slug: "barbell-deadlift", sets: 3, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "pull-up", sets: 3, repsMin: 6, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 10, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Advanced: PPL 6-day

    static let pushPullLegsAdvanced = PlanTemplate(
        id: "tpl-ppl-advanced",
        name: "Push / Pull / Legs — High Volume",
        description: "An advanced 6-day PPL with higher volume and intensity techniques including supersets. For experienced lifters looking to maximise growth.",
        level: .advanced,
        daysPerWeek: 6,
        days: [
            PlanTemplateDay(name: "Push A — Heavy", exercises: [
                .init(slug: "barbell-bench-press", sets: 5, repsMin: 4, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "dumbbell-shoulder-press", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "triceps-pushdown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "barbell-lying-triceps-extension", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss1"),
                .init(slug: "chest-dip", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Pull A — Heavy", exercises: [
                .init(slug: "barbell-deadlift", sets: 4, repsMin: 3, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "pull-up", sets: 4, repsMin: 6, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "barbell-curl", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "dumbbell-hammer-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
            ]),
            PlanTemplateDay(name: "Legs A — Heavy", exercises: [
                .init(slug: "barbell-squat", sets: 5, repsMin: 4, repsMax: 6, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "leg-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 5, repsMin: 10, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Push B — Volume", exercises: [
                .init(slug: "dumbbell-shoulder-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 4, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-fly", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "push-up", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "triceps-pushdown", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Pull B — Volume", exercises: [
                .init(slug: "lat-pulldown", sets: 4, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "dumbbell-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss3"),
                .init(slug: "dumbbell-hammer-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: "ss3"),
            ]),
            PlanTemplateDay(name: "Legs B — Volume", exercises: [
                .init(slug: "barbell-front-squat", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-sumo-squat", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "leg-extension", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: "ss4"),
                .init(slug: "lying-leg-curl", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: "ss4"),
                .init(slug: "seated-calf-raise", sets: 5, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-crunch", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )

    // MARK: - Advanced: Bro Split (5 days)

    static let broSplit = PlanTemplate(
        id: "tpl-bro-split",
        name: "Classic Body Part Split",
        description: "A traditional 5-day split dedicating one session to each major body part. High volume per muscle group with a full week to recover.",
        level: .advanced,
        daysPerWeek: 5,
        days: [
            PlanTemplateDay(name: "Chest", exercises: [
                .init(slug: "barbell-bench-press", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "dumbbell-incline-bench-press", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "cable-fly", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "chest-dip", sets: 3, repsMin: 8, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "push-up", sets: 3, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Back", exercises: [
                .init(slug: "barbell-deadlift", sets: 4, repsMin: 5, repsMax: 5, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-bent-over-row", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "pull-up", sets: 4, repsMin: 6, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "lat-pulldown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "cable-seated-row", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Shoulders", exercises: [
                .init(slug: "dumbbell-shoulder-press", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 150, groupTag: nil),
                .init(slug: "barbell-upright-row", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "dumbbell-lateral-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-rear-delt-fly", sets: 4, repsMin: 15, repsMax: 20, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Legs", exercises: [
                .init(slug: "barbell-squat", sets: 4, repsMin: 6, repsMax: 8, restSeconds: 180, groupTag: nil),
                .init(slug: "barbell-romanian-deadlift", sets: 4, repsMin: 8, repsMax: 10, restSeconds: 120, groupTag: nil),
                .init(slug: "leg-press", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 120, groupTag: nil),
                .init(slug: "leg-extension", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: "ss1"),
                .init(slug: "lying-leg-curl", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 90, groupTag: "ss1"),
                .init(slug: "dumbbell-rear-lunge", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 90, groupTag: nil),
                .init(slug: "seated-calf-raise", sets: 4, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
            PlanTemplateDay(name: "Arms & Core", exercises: [
                .init(slug: "barbell-curl", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90, groupTag: nil),
                .init(slug: "barbell-lying-triceps-extension", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90, groupTag: nil),
                .init(slug: "dumbbell-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "triceps-pushdown", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: "ss2"),
                .init(slug: "dumbbell-hammer-curl", sets: 3, repsMin: 10, repsMax: 12, restSeconds: 60, groupTag: nil),
                .init(slug: "hanging-leg-raise", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
                .init(slug: "cable-crunch", sets: 3, repsMin: 12, repsMax: 15, restSeconds: 60, groupTag: nil),
            ]),
        ]
    )
}
