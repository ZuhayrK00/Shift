import Foundation

struct WorkoutProgramMetadata: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var dayIndex: Int
    var totalDays: Int
    var source: String
}

struct DecodedPlanNotes: Equatable, Sendable {
    var metadata: WorkoutProgramMetadata?
    var userNotes: String?
}

enum PlanNotesCodec {
    private static let prefix = "[shift-program:"
    private static let suffix = "]"

    static func encode(metadata: WorkoutProgramMetadata?, userNotes: String?) -> String? {
        let cleanedNotes = userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let metadata else {
            return cleanedNotes?.isEmpty == false ? cleanedNotes : nil
        }
        guard let data = try? JSONEncoder().encode(metadata) else {
            return cleanedNotes?.isEmpty == false ? cleanedNotes : nil
        }
        let header = prefix + data.base64EncodedString() + suffix
        guard let cleanedNotes, !cleanedNotes.isEmpty else { return header }
        return header + "\n" + cleanedNotes
    }

    static func decode(_ notes: String?) -> DecodedPlanNotes {
        guard let notes, notes.hasPrefix(prefix),
              let headerEnd = notes.firstIndex(of: Character(suffix)) else {
            return DecodedPlanNotes(metadata: nil, userNotes: notes)
        }

        let encodedStart = notes.index(notes.startIndex, offsetBy: prefix.count)
        let encoded = String(notes[encodedStart..<headerEnd])
        guard let data = Data(base64Encoded: encoded),
              let metadata = try? JSONDecoder().decode(WorkoutProgramMetadata.self, from: data) else {
            return DecodedPlanNotes(metadata: nil, userNotes: notes)
        }

        let remainderStart = notes.index(after: headerEnd)
        let remainder = String(notes[remainderStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DecodedPlanNotes(
            metadata: metadata,
            userNotes: remainder.isEmpty ? nil : remainder
        )
    }
}

struct WorkoutProgramSummary: Identifiable {
    var id: String
    var name: String
    var source: String
    var workouts: [WorkoutPlanWithCount]
    var nextWorkout: WorkoutPlanWithCount?
    var isActive: Bool
}

enum WorkoutProgramService {
    static func summaries(
        plans: [WorkoutPlanWithCount],
        completedSessions: [WorkoutSession],
        userID: String
    ) -> (programs: [WorkoutProgramSummary], standalone: [WorkoutPlanWithCount]) {
        let grouped = Dictionary(grouping: plans) {
            PlanNotesCodec.decode($0.plan.notes).metadata?.id
        }
        let standalone = grouped[nil] ?? []
        let activeID = activeProgramID(userID: userID)

        var programs = grouped.compactMap { key, items -> WorkoutProgramSummary? in
            guard let id = key,
                  let firstMetadata = items.compactMap({
                      PlanNotesCodec.decode($0.plan.notes).metadata
                  }).first else { return nil }

            let ordered = items.sorted {
                let lhs = PlanNotesCodec.decode($0.plan.notes).metadata?.dayIndex ?? 0
                let rhs = PlanNotesCodec.decode($1.plan.notes).metadata?.dayIndex ?? 0
                return lhs < rhs
            }
            return WorkoutProgramSummary(
                id: id,
                name: firstMetadata.name,
                source: firstMetadata.source,
                workouts: ordered,
                nextWorkout: nextWorkout(in: ordered, completedSessions: completedSessions),
                isActive: id == activeID
            )
        }
        .sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return ($0.workouts.first?.plan.createdAt ?? .distantPast)
                > ($1.workouts.first?.plan.createdAt ?? .distantPast)
        }

        if !programs.contains(where: \.isActive),
           let newestIndex = programs.indices.max(by: {
               (programs[$0].workouts.first?.plan.createdAt ?? .distantPast)
                   < (programs[$1].workouts.first?.plan.createdAt ?? .distantPast)
           }) {
            programs[newestIndex].isActive = true
            setActiveProgram(programs[newestIndex].id, userID: userID)
            programs.sort {
                if $0.isActive != $1.isActive { return $0.isActive }
                return ($0.workouts.first?.plan.createdAt ?? .distantPast)
                    > ($1.workouts.first?.plan.createdAt ?? .distantPast)
            }
        }

        return (programs, standalone)
    }

    static func setActiveProgram(_ programID: String?, userID: String) {
        let key = activeProgramKey(userID: userID)
        if let programID {
            UserDefaults.standard.set(programID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func activeProgramID(userID: String) -> String? {
        UserDefaults.standard.string(forKey: activeProgramKey(userID: userID))
    }

    private static func nextWorkout(
        in workouts: [WorkoutPlanWithCount],
        completedSessions: [WorkoutSession]
    ) -> WorkoutPlanWithCount? {
        guard !workouts.isEmpty else { return nil }
        let indices = Dictionary(uniqueKeysWithValues: workouts.enumerated().map { ($1.plan.id, $0) })
        guard let lastCompleted = completedSessions
            .filter({ $0.endedAt != nil && $0.planId.flatMap { indices[$0] } != nil })
            .max(by: { $0.startedAt < $1.startedAt }),
              let planID = lastCompleted.planId,
              let lastIndex = indices[planID] else {
            return workouts.first
        }
        return workouts[(lastIndex + 1) % workouts.count]
    }

    private static func activeProgramKey(userID: String) -> String {
        "shift.activeProgram.\(userID)"
    }
}
