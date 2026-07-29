import Foundation

struct WarmupPrescription: Equatable, Sendable {
    var weightKg: Double
    var reps: Int
}

struct PlateLoading: Equatable, Sendable {
    var targetWeight: Double
    var barWeight: Double
    var platesPerSide: [Double]
    var actualWeight: Double
}

enum WorkoutUtilityService {
    /// A short ramp that prepares the movement without creating extra fatigue.
    static func warmups(
        workingWeightKg: Double,
        incrementKg: Double
    ) -> [WarmupPrescription] {
        guard workingWeightKg.isFinite, workingWeightKg > 0 else { return [] }
        let increment = incrementKg.isFinite ? max(0.5, incrementKg) : 2.5
        let stages: [(Double, Int)] = workingWeightKg < 30
            ? [(0.55, 8), (0.75, 5)]
            : [(0.40, 8), (0.60, 5), (0.80, 3)]

        var result: [WarmupPrescription] = []
        for (percentage, reps) in stages {
            let rounded = (workingWeightKg * percentage / increment).rounded() * increment
            let weight = max(increment, min(rounded, workingWeightKg - increment))
            guard weight > 0,
                  weight < workingWeightKg,
                  result.last?.weightKg != weight else { continue }
            result.append(WarmupPrescription(weightKg: weight, reps: reps))
        }
        return result
    }

    /// Greedy loading using common metric or imperial plates. The result is
    /// intentionally rounded down so it never silently exceeds the target.
    static func plateLoading(
        targetWeight: Double,
        barWeight: Double,
        unit: String
    ) -> PlateLoading {
        let isImperial = ["lb", "lbs"].contains(unit.lowercased())
        let plates = isImperial
            ? [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]
            : [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
        var perSide = max(0, targetWeight - barWeight) / 2
        var selected: [Double] = []
        for plate in plates {
            while perSide + 0.0001 >= plate {
                selected.append(plate)
                perSide -= plate
            }
        }
        let actual = barWeight + selected.reduce(0, +) * 2
        return PlateLoading(
            targetWeight: targetWeight,
            barWeight: barWeight,
            platesPerSide: selected,
            actualWeight: actual
        )
    }
}
