import XCTest

/// Guards the durable Info.plist layout. Xcode 16 copies files inside
/// `PBXFileSystemSynchronizedRootGroup` as resources; membershipExceptions
/// are rewritten when Build Settings change. Info.plist must live outside
/// `VoiceDesk/` as an explicit file reference used only via INFOPLIST_FILE.
final class XcodeProjectLayoutTests: XCTestCase {
    func testInfoPlistIsNotAResourceCopy() throws {
        let pbx = try XCTUnwrap(pbxprojContents(), "VoiceDesk.xcodeproj should sit next to VoiceDeskLogic")

        XCTAssertTrue(pbx.contains("INFOPLIST_FILE = Config/Info.plist"))
        XCTAssertFalse(pbx.contains("INFOPLIST_FILE = VoiceDesk/Info.plist"))
        XCTAssertFalse(pbx.contains("path = VoiceDesk/Info.plist"))
        XCTAssertFalse(pbx.contains("PBXFileSystemSynchronizedBuildFileExceptionSet"))
        XCTAssertFalse(pbx.contains("membershipExceptions"))
        XCTAssertFalse(pbx.contains("Info.plist in Resources"))
        XCTAssertFalse(pbx.contains("Info.plist in Copy"))

        let buildFileCopies = pbx.split(separator: "\n").filter {
            $0.contains("PBXBuildFile") && $0.contains("Info.plist")
        }
        XCTAssertTrue(buildFileCopies.isEmpty, "Info.plist must not be a PBXBuildFile resource: \(buildFileCopies)")

        let plist = try XCTUnwrap(configInfoPlistContents())
        XCTAssertTrue(plist.contains("CFBundleURLTypes"))
        XCTAssertTrue(plist.contains("$(GOOGLE_REVERSED_CLIENT_ID)"))
        XCTAssertTrue(plist.contains("GIDClientID"))
        XCTAssertTrue(plist.contains("$(GOOGLE_CLIENT_ID)"))

        XCTAssertFalse(pbx.contains("$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"))
        XCTAssertFalse(pbx.contains("INFOPLIST_PATH"))
        XCTAssertFalse(pbx.contains("com.googleusercontent.apps.REPLACE_ME"))
        XCTAssertTrue(pbx.contains("GENERATE_INFOPLIST_FILE = YES"))
    }

    func testInjectScriptWritesXcconfigOnly() throws {
        let script = try XCTUnwrap(repoFile("scripts/inject-google-secrets.sh"))
        XCTAssertTrue(script.contains("Config/Generated/GoogleSecrets.xcconfig"))
        XCTAssertTrue(script.contains("derive_reversed"))
        XCTAssertFalse(script.contains("INFOPLIST_PATH"))
        XCTAssertFalse(script.contains("TARGET_BUILD_DIR"))
        XCTAssertFalse(script.contains("Set :GIDClientID"))
        XCTAssertFalse(script.contains("CFBundleURLTypes"))
        XCTAssertFalse(script.contains("PlistBuddy -c \"Set"))

        let pbx = try XCTUnwrap(pbxprojContents())
        XCTAssertTrue(pbx.contains("Write GoogleSecrets.xcconfig"))
        XCTAssertTrue(pbx.contains("$(SRCROOT)/Config/Generated/GoogleSecrets.xcconfig"))
        XCTAssertFalse(pbx.contains("$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"))
        let outputBlock = pbx.range(of: "outputPaths = (")
        XCTAssertNotNil(outputBlock)
        if let start = outputBlock {
            let slice = String(pbx[start.lowerBound...]).prefix(280)
            XCTAssertTrue(slice.contains("GoogleSecrets.xcconfig"))
            XCTAssertFalse(slice.contains("INFOPLIST_PATH"))
        }

        let xcconfig = try XCTUnwrap(repoFile("Config/VoiceDesk.xcconfig"))
        XCTAssertTrue(xcconfig.contains("#include? \"Generated/GoogleSecrets.xcconfig\""))
        XCTAssertTrue(xcconfig.contains("INFOPLIST_FILE = Config/Info.plist"))
        XCTAssertFalse(xcconfig.contains("REPLACE_ME"))
        let includeIndex = try XCTUnwrap(xcconfig.range(of: "#include? \"Generated/GoogleSecrets.xcconfig\""))
        let reversedDefault = try XCTUnwrap(xcconfig.range(of: "GOOGLE_REVERSED_CLIENT_ID ="))
        XCTAssertLessThan(reversedDefault.lowerBound, includeIndex.lowerBound)

        let scheme = try XCTUnwrap(repoFile("VoiceDesk.xcodeproj/xcshareddata/xcschemes/VoiceDesk.xcscheme"))
        XCTAssertTrue(scheme.contains("PreActions"))
        XCTAssertTrue(scheme.contains("inject-google-secrets.sh"))
    }

    func testInjectScriptDerivesReversedClientIDFromSecrets() throws {
        var url = URL(fileURLWithPath: #filePath)
        var scriptURL: URL?
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("scripts/inject-google-secrets.sh")
            if FileManager.default.fileExists(atPath: candidate.path) {
                scriptURL = candidate
                break
            }
        }
        let inject = try XCTUnwrap(scriptURL)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicedesk-inject-\(UUID().uuidString)")
        let secretsDir = root.appendingPathComponent("VoiceDesk")
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
        let secrets = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>GOOGLE_CLIENT_ID</key>
            <string>123-abc.apps.googleusercontent.com</string>
            <key>GOOGLE_REVERSED_CLIENT_ID</key>
            <string>com.googleusercontent.apps.REPLACE_ME</string>
        </dict>
        </plist>
        """
        try secrets.write(to: secretsDir.appendingPathComponent("Secrets.plist"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [inject.path]
        var environment = ProcessInfo.processInfo.environment
        environment["SRCROOT"] = root.path
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let generated = try String(
            contentsOf: root.appendingPathComponent("Config/Generated/GoogleSecrets.xcconfig"),
            encoding: .utf8
        )
        XCTAssertTrue(generated.contains("GOOGLE_CLIENT_ID = 123-abc.apps.googleusercontent.com"))
        XCTAssertTrue(generated.contains("GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.123-abc"))
        XCTAssertFalse(generated.contains("REPLACE_ME"))
        try? FileManager.default.removeItem(at: root)
    }

    func testLiveSyncUsesRecentInboxLimitOf25() throws {
        let sync = try XCTUnwrap(repoFile("VoiceDesk/Voice/GoogleSync.swift"))
        XCTAssertTrue(sync.contains("GoogleSyncPolicy.recentInboxLimit"))
        XCTAssertFalse(sync.contains("recentMessageLimit: Int = 8"))
    }

    func testGoogleSignInPackageIsPinned() throws {
        let pbx = try XCTUnwrap(pbxprojContents(), "VoiceDesk.xcodeproj should sit next to VoiceDeskLogic")
        XCTAssertTrue(pbx.contains("XCRemoteSwiftPackageReference \"GoogleSignIn-iOS\""))
        XCTAssertTrue(pbx.contains("https://github.com/google/GoogleSignIn-iOS"))
        XCTAssertTrue(pbx.contains("kind = exactVersion"))
        XCTAssertTrue(pbx.contains("version = 9.2.0"))
        XCTAssertFalse(pbx.contains("upToNextMajorVersion"))
        XCTAssertFalse(pbx.contains("minimumVersion = 9.0.0"))
        XCTAssertTrue(pbx.contains("productName = GoogleSignIn"))
        XCTAssertFalse(pbx.contains("productName = GoogleSignInSwift"))

        let resolved = try XCTUnwrap(
            repoFile("VoiceDesk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            "Package.resolved must be committed so Xcode can find GoogleSignIn"
        )
        XCTAssertTrue(resolved.contains("\"identity\" : \"googlesignin-ios\""))
        XCTAssertTrue(resolved.contains("\"version\" : \"9.2.0\""))
        XCTAssertTrue(resolved.contains("\"revision\" : \"08d8dcecafb575f98879ffdbb8302c1b9ad65d19\""))
        XCTAssertTrue(resolved.contains("appauth-ios"))
        XCTAssertTrue(resolved.contains("gtmappauth"))
        XCTAssertTrue(resolved.contains("\"version\" : \"5.0.0\""))
        XCTAssertTrue(resolved.contains("gtm-session-fetcher"))
    }

    private func pbxprojContents() -> String? {
        repoFile("VoiceDesk.xcodeproj/project.pbxproj")
    }

    private func configInfoPlistContents() -> String? {
        repoFile("Config/Info.plist")
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }
}
