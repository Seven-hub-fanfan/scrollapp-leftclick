import AppKit

// Isolated bundle/defaults/storage; changes real WindowServer cursors, so quit Scrollapp first.
// Requires -D SCROLLAPP_TESTING. Downloads real public release assets, without a mock transport.
@main struct VerifySkinLifecycle {
    static func wait(_ timeout: Double = 130, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition(), "Operation timed out")
    }
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let assets = SkinAssetStore(directory: directory.appendingPathComponent("downloads"))
        SkinAssetStore.shared = assets
        UserDefaults.standard.set("frog", forKey: "cursorTheme")
        UserDefaults.standard.set(1.0, forKey: "cursorScale")
        UserDefaults.standard.set(false, forKey: "cursorClickMarkerEnabled")
        let store = CursorSkinStore(directory: directory.appendingPathComponent("cursors"))
        var checks: [String] = []
        store.start(); wait(30) { !store.isBusy }
        precondition(store.isReady && store.activeID == "system" && store.missingDownload)
        precondition(assets.installed == Set(SkinPackage.all.filter(\.isBundled).map(\.id))
                     && assets.progress.isEmpty)
        checks.append("upgrade-missing-skin-safe-no-auto-download")
        for package in SkinPackage.all.filter({ !$0.isCursorArchive && !$0.isBundled }) {
            assets.download(package.id)
            wait { assets.progress[package.id] == nil }
            precondition(assets.isInstalled(package.id), "Real download failed: \(assets.errors)")
            _ = try assets.validatedRoles(package)
            precondition(CursorCatalog.roles(for: CursorCatalog.theme(package.id)).count == 13)
            checks.append("\(package.id)-real-https-download-and-13-roles")
        }
        store.apply("frog")
        store.removeSkin("frog")
        precondition(assets.isInstalled("frog"), "Deleted resource while apply was pending")
        wait(30) { !store.isBusy }
        precondition(store.activeID == "frog" && store.appliedCount == 47 && !store.missingDownload,
                     "Apply failed: \(store.errorKey ?? "")")
        checks.append("apply-downloaded-frog-and-block-busy-delete")
        store.removeSkin("xiaoqi")
        precondition(!assets.isInstalled("xiaoqi") && store.activeID == "frog")
        checks.append("inactive-delete-preserves-active-cursor")
        store.setCursorScale(2)
        store.setClickMarkerEnabled(true)
        store.apply("frog"); wait(30) { !store.isBusy }
        store.removeSkin("frog"); wait(30) { !store.isBusy }
        precondition(store.activeID == "system" && !assets.isInstalled("frog"))
        precondition(store.cursorScale == 2 && store.appliedCursorScale == 2 && store.appliedMarkerDiameter == 5)
        precondition(CursorCatalog.roles(for: CursorCatalog.theme("frog")).isEmpty)
        checks.append("active-delete-restores-invalidates-and-preserves-size-marker")
        assets.download("xiaoqi"); wait { assets.progress["xiaoqi"] == nil }
        precondition(assets.isInstalled("xiaoqi"))
        store.apply("xiaoqi"); wait(30) { !store.isBusy }
        precondition(store.activeID == "xiaoqi" && store.appliedCount == 47)
        checks.append("redownload-and-apply")
        var stopped = false
        store.shutdown { stopped = true }; wait(30) { stopped }
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("cursors/recovery.plist").path))
        checks.append("quit-restores-global-cursors")
        let data = try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("lifecycle.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
