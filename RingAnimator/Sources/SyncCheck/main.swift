import Foundation
import RingAnimatorCore

// What happens to your animations when a new build arrives.
//
// This is the one piece of the app that can destroy work nobody can get
// back: it runs unattended at launch, over a library someone may have
// spent a day editing. So every branch of `UseCaseLibrary.sync` gets a
// case here, including the ones whose correct behaviour is "do nothing".
//
// `swift run SyncCheck` — run by preflight.sh.

@MainActor
func run() -> Int32 {
    var failed = false
    func check(_ label: String, _ ok: Bool, _ detail: String) {
        print("  \(ok ? "✓" : "✗") \(label) — \(detail)")
        if !ok { failed = true }
    }

    guard let bundled = UseCaseLibrary.bundled else {
        print("  ✗ no bundled library in the app")
        return 1
    }
    print("  bundled library: \(bundled.presets.count) animations, cut \(bundled.generatedAt)")

    // Each case gets its own store file and its own record, so they can't
    // contaminate each other.
    let support = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/RingAnimator")
    let recordURL = support.appendingPathComponent("use-case-install-record.json")
    let realRecord = try? Data(contentsOf: recordURL)
    defer {
        // Put the real record back: this process shares Application
        // Support with the app.
        if let realRecord {
            try? realRecord.write(to: recordURL)
        } else {
            try? FileManager.default.removeItem(at: recordURL)
        }
    }

    func freshStore(_ name: String, seeded: Bool) -> RingPresetStore {
        let url = support.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: recordURL)
        UseCaseLibrary.invalidateCache()
        let store = RingPresetStore(fileName: name)
        if seeded { store.append(contentsOf: bundled.presets) }
        return store
    }
    func cleanUp(_ name: String) {
        try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
    }

    // 1. A machine that has never seen this library gets all of it.
    let empty = freshStore("sync-check-empty.json", seeded: false)
    let firstRun = UseCaseLibrary.sync(into: empty)
    check("a fresh install gets the whole library",
          firstRun.added.count == bundled.presets.count && empty.presets.count == bundled.presets.count,
          "\(firstRun.added.count) added, store holds \(empty.presets.count)")

    // 2. Running it again changes nothing. An update that keeps "updating"
    //    the same animations is one nobody trusts.
    let secondRun = UseCaseLibrary.sync(into: empty)
    check("running it again is a no-op", secondRun.isEmpty, secondRun.isEmpty ? "nothing to do" : secondRun.summary)

    // An edit that is still an edit is reported every launch, so it must
    // not count as something having changed — see `changedAnything`.
    if var edited = empty.presets.first {
        edited.speed += 1
        empty.update(edited)
        let noisy = UseCaseLibrary.sync(into: empty)
        check("a standing edit isn't reported as a change",
              !noisy.changedAnything && noisy.keptYours.count == 1,
              "keptYours \(noisy.keptYours.count), changed \(noisy.changedAnything)")
    }
    cleanUp("sync-check-empty.json")

    // 3. A library already here, with no record of where it came from —
    //    the upgrade path from the build before this feature existed.
    //    Nothing should move, and everything should end up recorded.
    let existing = freshStore("sync-check-existing.json", seeded: true)
    let adopt = UseCaseLibrary.sync(into: existing)
    let record = UseCaseLibrary.currentRecord()
    check("an existing library is adopted, not rewritten",
          adopt.isEmpty && existing.presets.count == bundled.presets.count,
          "\(adopt.summary.isEmpty ? "nothing changed" : adopt.summary), \(record.fingerprints.count) recorded")

    // 4. An edited animation survives. This is the case that matters.
    if var mine = existing.presets.first {
        let originalName = mine.name
        mine.name = "My Version"
        mine.speed = 3.21
        existing.update(mine)
        let afterEdit = UseCaseLibrary.sync(into: existing)
        let stillMine = existing.presets.first(where: { $0.id == mine.id })
        check("an animation you edited is left alone",
              stillMine?.name == "My Version" && stillMine?.speed == 3.21,
              "name \"\(stillMine?.name ?? "?")\", speed \(stillMine?.speed ?? -1)")
        check("and the sync says it kept yours",
              afterEdit.keptYours.contains("My Version"),
              afterEdit.keptYours.isEmpty ? "reported nothing" : afterEdit.keptYours.joined(separator: ", "))
        check("origin reads as edited", UseCaseLibrary.origin(of: stillMine ?? mine) == .edited,
              "\(UseCaseLibrary.origin(of: stillMine ?? mine))")
        _ = originalName
    }

    // 5. Something you deleted stays deleted.
    if let doomed = existing.presets.last {
        existing.delete(doomed.id)
        let afterDelete = UseCaseLibrary.sync(into: existing)
        check("an animation you deleted is not resurrected",
              !existing.presets.contains(where: { $0.id == doomed.id }) && afterDelete.added.isEmpty,
              "\(afterDelete.added.count) re-added")
    }

    // 6. Something you made yourself is never touched, and reads as local.
    let mine = RingPreset(name: "Only Mine", config: RingConfig())
    _ = existing.add(mine)
    let afterLocal = UseCaseLibrary.sync(into: existing)
    check("an animation you made is untouched",
          existing.presets.contains(where: { $0.id == mine.id }) && !afterLocal.changedAnything,
          afterLocal.changedAnything ? afterLocal.summary : "nothing changed")
    check("origin reads as local", UseCaseLibrary.origin(of: mine) == .local, "\(UseCaseLibrary.origin(of: mine))")

    // 7. A *newer* bundled version replaces one you never touched. Faked by
    //    recording a stale fingerprint for an untouched animation, which is
    //    exactly the state a new build's library produces.
    if let untouched = existing.presets.first(where: { UseCaseLibrary.origin(of: $0) == .bundled }),
       var stale = bundled.presets.first(where: { $0.id == untouched.id }) {
        stale.speed = untouched.speed + 1
        existing.update(stale)                       // pretend this is what shipped last time
        var doctored = UseCaseLibrary.currentRecord()
        doctored.fingerprints[untouched.id.uuidString] = UseCaseLibrary.fingerprint(stale)
        writeRecord(doctored, to: recordURL)
        // Written straight to the file, so the in-memory copy has to go.
        UseCaseLibrary.invalidateCache()
        let afterUpdate = UseCaseLibrary.sync(into: existing)
        let now = existing.presets.first(where: { $0.id == untouched.id })
        check("an untouched animation takes the new version",
              now?.speed == untouched.speed && afterUpdate.updated.count == 1,
              "speed \(now?.speed ?? -1) (was \(stale.speed), bundled \(untouched.speed))")
    }
    cleanUp("sync-check-existing.json")

    return failed ? 1 : 0
}

func writeRecord(_ record: UseCaseLibrary.InstallRecord, to url: URL) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try? encoder.encode(record).write(to: url, options: .atomic)
}

print("bundled library sync:")
exit(run())
