import XCTest
@testable import Shift

final class FormatTests: XCTestCase {

    // MARK: - pluralise

    func testPluralise_singularCount() {
        XCTAssertEqual(pluralise(1, "set"), "1 set")
    }

    func testPluralise_pluralCount_appendsS() {
        XCTAssertEqual(pluralise(3, "set"), "3 sets")
    }

    func testPluralise_zeroCount_usesPlural() {
        XCTAssertEqual(pluralise(0, "rep"), "0 reps")
    }

    func testPluralise_customPlural() {
        XCTAssertEqual(pluralise(2, "entry", "entries"), "2 entries")
    }

    func testPluralise_customPlural_singularStillWorks() {
        XCTAssertEqual(pluralise(1, "entry", "entries"), "1 entry")
    }

    func testPluralise_uppercaseSingular() {
        XCTAssertEqual(pluralise(1, "SET"), "1 SET")
    }

    func testPluralise_uppercasePlural() {
        XCTAssertEqual(pluralise(3, "SET"), "3 SETs")
    }

    // MARK: - Weight conversion

    func testConvertWeight_kgToKg_unchanged() {
        XCTAssertEqual(convertWeight(60, to: "kg"), 60, accuracy: 0.001)
    }

    func testConvertWeight_kgToLbs() {
        XCTAssertEqual(convertWeight(60, to: "lbs"), 60 * 2.20462, accuracy: 0.01)
    }

    func testConvertWeightToKg_fromKg_unchanged() {
        XCTAssertEqual(convertWeightToKg(60, from: "kg"), 60, accuracy: 0.001)
    }

    func testConvertWeightToKg_fromLbs() {
        XCTAssertEqual(convertWeightToKg(132.277, from: "lbs"), 60, accuracy: 0.01)
    }

    func testConvertWeight_roundTrip() {
        let original = 80.0
        let lbs = convertWeight(original, to: "lbs")
        let backToKg = convertWeightToKg(lbs, from: "lbs")
        XCTAssertEqual(backToKg, original, accuracy: 0.001)
    }

    // MARK: - formatWeight

    func testFormatWeight_kg_wholeNumber() {
        XCTAssertEqual(formatWeight(60, unit: "kg"), "60 kg")
    }

    func testFormatWeight_kg_fractional() {
        XCTAssertEqual(formatWeight(60.5, unit: "kg"), "60.5 kg")
    }

    func testFormatWeight_lbs_displaysConverted() {
        let result = formatWeight(60, unit: "lbs")
        // 60 kg × 2.20462 = 132.2772 → "132 lbs"
        XCTAssertTrue(result.hasSuffix("lbs"))
        XCTAssertTrue(result.hasPrefix("132"))
    }

    func testFormatWeight_zero() {
        XCTAssertEqual(formatWeight(0, unit: "kg"), "0 kg")
    }

    // MARK: - toLocalDateKey

    func testToLocalDateKey_formatsAsYYYYMMDD() {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = DateComponents(year: 2026, month: 4, day: 15, hour: 14, minute: 30)
        let date = cal.date(from: comps)!
        XCTAssertEqual(toLocalDateKey(date), "2026-04-15")
    }

    func testToLocalDateKey_midnight() {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0)
        let date = cal.date(from: comps)!
        XCTAssertEqual(toLocalDateKey(date), "2026-01-01")
    }

    // MARK: - noonOfLocalDate

    func testNoonOfLocalDate_setsTimeToNoon() {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = DateComponents(year: 2026, month: 4, day: 15, hour: 22, minute: 45)
        let date = cal.date(from: comps)!

        let noon = noonOfLocalDate(date)
        let noonComps = cal.dateComponents([.hour, .minute, .second], from: noon)
        XCTAssertEqual(noonComps.hour, 12)
        XCTAssertEqual(noonComps.minute, 0)
        XCTAssertEqual(noonComps.second, 0)
    }

    func testNoonOfLocalDate_preservesDay() {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "en_US_POSIX")
        let comps = DateComponents(year: 2026, month: 7, day: 20, hour: 3)
        let date = cal.date(from: comps)!

        let noon = noonOfLocalDate(date)
        let noonComps = cal.dateComponents([.year, .month, .day], from: noon)
        XCTAssertEqual(noonComps.year, 2026)
        XCTAssertEqual(noonComps.month, 7)
        XCTAssertEqual(noonComps.day, 20)
    }
}
