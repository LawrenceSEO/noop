import XCTest
@testable import StrandImport

/// Pins LiftingImporter: a Hevy CSV export and a Liftosaur JSON export both parse into one Strength
/// session per workout, with a TRANSPARENT volume-load = Σ(weight × reps). Warm-up sets are excluded
/// from the working volume, lb columns convert to kg, and the note never claims a strain.
final class LiftingImporterTests: XCTestCase {

    // MARK: - Hevy CSV

    func testHevyGroupsSetsIntoOneSessionWithVolumeLoad() {
        // Two exercises, four working sets across one workout. Volume = Σ(kg × reps):
        //   100×5 + 100×5 + 100×5 = 1500 (bench) ; 60×8 = 480 (curl) → 1980 kg.
        let csv = """
        title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps
        Push Day,2026-06-01 18:00:00,2026-06-01 19:00:00,Bench Press,0,warmup,40,10
        Push Day,2026-06-01 18:00:00,2026-06-01 19:00:00,Bench Press,1,normal,100,5
        Push Day,2026-06-01 18:00:00,2026-06-01 19:00:00,Bench Press,2,normal,100,5
        Push Day,2026-06-01 18:00:00,2026-06-01 19:00:00,Bench Press,3,normal,100,5
        Push Day,2026-06-01 18:00:00,2026-06-01 19:00:00,Bicep Curl,0,normal,60,8
        """
        let r = LiftingImporter.parseHevy(text: csv)

        XCTAssertEqual(r.sessionCount, 1)
        XCTAssertEqual(r.skipped, 0)
        let s = r.sessions[0]
        XCTAssertEqual(s.volumeLoadKg, 1980, accuracy: 1e-6)   // warm-up 40×10 excluded
        XCTAssertEqual(s.setCount, 4)                          // 4 working sets, warm-up not counted
        XCTAssertEqual(s.exerciseCount, 2)
        XCTAssertEqual(s.totalReps, 23)
        XCTAssertEqual(s.topSetKg, 100)
        XCTAssertEqual(s.durationS, 3600)
        XCTAssertEqual(s.title, "Push Day")
    }

    func testHevySplitsDistinctWorkoutsAndConvertsPounds() {
        // A lb column converts to kg (135 lb ≈ 61.235 kg). Two start_times → two sessions.
        let csv = """
        title,start_time,exercise_title,set_type,weight_lb,reps
        A,2026-06-01 10:00:00,Squat,normal,135,5
        B,2026-06-02 10:00:00,Deadlift,normal,225,3
        """
        let r = LiftingImporter.parseHevy(text: csv)
        XCTAssertEqual(r.sessionCount, 2)
        XCTAssertEqual(r.sessions[0].volumeLoadKg, 135 * 0.45359237 * 5, accuracy: 1e-4)
        XCTAssertEqual(r.sessions[1].volumeLoadKg, 225 * 0.45359237 * 3, accuracy: 1e-4)
        // Oldest-first ordering.
        XCTAssertLessThan(r.sessions[0].start, r.sessions[1].start)
    }

    func testHevySkipsRowsWithNoUsableDate() {
        let csv = """
        title,start_time,exercise_title,set_type,weight_kg,reps
        Good,2026-06-01 10:00:00,Squat,normal,100,5
        Bad,,Squat,normal,100,5
        """
        let r = LiftingImporter.parseHevy(text: csv)
        XCTAssertEqual(r.sessionCount, 1)
        XCTAssertEqual(r.skipped, 1)
    }

    func testHevyBodyweightSetCountsButAddsNoVolume() {
        // No weight column at all → reps still count the set, volume stays 0.
        let csv = """
        title,start_time,exercise_title,set_type,reps
        Pull,2026-06-01 10:00:00,Pull Up,normal,12
        """
        let r = LiftingImporter.parseHevy(text: csv)
        XCTAssertEqual(r.sessions[0].setCount, 1)
        XCTAssertEqual(r.sessions[0].volumeLoadKg, 0)
        XCTAssertEqual(r.sessions[0].totalReps, 12)
        XCTAssertNil(r.sessions[0].topSetKg)
    }

    // MARK: - Liftosaur JSON

    func testLiftosaurParsesHistoryRecords() {
        // startTime is epoch ms. Two entries; volume = 80×5 + 80×5 + 100×3 = 1100 kg.
        let json = """
        { "history": [
          { "startTime": 1748772000000, "endTime": 1748775600000, "dayName": "Day 1",
            "entries": [
              { "sets": [ { "weight": 80, "completedReps": 5 }, { "weight": 80, "completedReps": 5 } ] },
              { "sets": [ { "weight": { "value": 100, "unit": "kg" }, "completedReps": 3 } ] }
            ] }
        ] }
        """
        let r = LiftingImporter.parseLiftosaur(data: Data(json.utf8))
        XCTAssertEqual(r.sessionCount, 1)
        let s = r.sessions[0]
        XCTAssertEqual(s.volumeLoadKg, 1100, accuracy: 1e-6)
        XCTAssertEqual(s.setCount, 3)
        XCTAssertEqual(s.exerciseCount, 2)
        XCTAssertEqual(s.totalReps, 13)
        XCTAssertEqual(s.start, Date(timeIntervalSince1970: 1748772000))
        XCTAssertEqual(s.durationS, 3600)
    }

    func testLiftosaurConvertsPoundUnitAndSkipsUncompletedSets() {
        // Entry-level lb unit applies; a set with no completedReps is a template entry → skipped.
        let json = """
        { "history": [
          { "startTime": 1748772000000, "entries": [
              { "unit": "lb", "sets": [ { "weight": 100, "completedReps": 5 }, { "weight": 100, "reps": 5 } ] }
          ] }
        ] }
        """
        let r = LiftingImporter.parseLiftosaur(data: Data(json.utf8))
        let s = r.sessions[0]
        XCTAssertEqual(s.setCount, 1)                                   // template set without completedReps skipped
        XCTAssertEqual(s.volumeLoadKg, 100 * 0.45359237 * 5, accuracy: 1e-4)
    }

    func testLiftosaurBareArrayAndStorageWrappers() {
        // Bare array form.
        let bare = """
        [ { "startTime": 1748772000000, "entries": [ { "sets": [ { "weight": 50, "completedReps": 10 } ] } ] } ]
        """
        XCTAssertEqual(LiftingImporter.parseLiftosaur(data: Data(bare.utf8)).sessionCount, 1)
        // { storage: { history: [...] } } wrapper form.
        let wrapped = """
        { "storage": { "history": [
          { "startTime": 1748772000000, "entries": [ { "sets": [ { "weight": 50, "completedReps": 10 } ] } ] }
        ] } }
        """
        XCTAssertEqual(LiftingImporter.parseLiftosaur(data: Data(wrapped.utf8)).sessionCount, 1)
    }

    // MARK: - Auto-detection + note

    func testDetectFormatRoutesByLeadingByte() {
        XCTAssertEqual(LiftingImporter.detectFormat(data: Data("  { \"history\": [] }".utf8)), .liftosaurJson)
        XCTAssertEqual(LiftingImporter.detectFormat(data: Data("[]".utf8)), .liftosaurJson)
        XCTAssertEqual(LiftingImporter.detectFormat(data: Data("title,start_time\n".utf8)), .hevyCsv)
    }

    func testVolumeLoadNoteIsHonestlyLabelled() {
        let s = LiftingSession(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0),
                               volumeLoadKg: 12400, setCount: 18, exerciseCount: 5, totalReps: 120,
                               topSetKg: 140, title: "Leg Day")
        let note = s.volumeLoadNote()
        XCTAssertTrue(note.contains("volume load 12,400 kg"), note)
        XCTAssertTrue(note.contains("Strength"), note)
        XCTAssertTrue(note.contains("18 sets"), note)
        XCTAssertTrue(note.contains("5 exercises"), note)
        XCTAssertTrue(note.contains("Leg Day"), note)
    }
}
