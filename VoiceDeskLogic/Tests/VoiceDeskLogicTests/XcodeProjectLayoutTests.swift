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
        XCTAssertTrue(plist.contains("<key>GIT_SHA</key>"))
        XCTAssertTrue(plist.contains("$(GIT_SHA)"))
        XCTAssertTrue(plist.contains("<key>GIT_BRANCH</key>"))
        XCTAssertTrue(plist.contains("$(GIT_BRANCH)"))
        // GENERATE_INFOPLIST_FILE already maps MARKETING_VERSION / CURRENT_PROJECT_VERSION.
        XCTAssertFalse(plist.contains("CFBundleShortVersionString"))
        XCTAssertFalse(plist.contains("CFBundleVersion"))

        XCTAssertFalse(pbx.contains("$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"))
        XCTAssertFalse(pbx.contains("INFOPLIST_PATH"))
        XCTAssertFalse(pbx.contains("com.googleusercontent.apps.REPLACE_ME"))
        XCTAssertTrue(pbx.contains("GENERATE_INFOPLIST_FILE = YES"))
    }

    func testVersionXcconfigIsSourceOfTruth() throws {
        let version = try XCTUnwrap(repoFile("Config/Version.xcconfig"))
        XCTAssertTrue(version.contains("MARKETING_VERSION = 0.1.0"))
        XCTAssertTrue(version.contains("CURRENT_PROJECT_VERSION = 4"))
        XCTAssertFalse(version.contains("0.1.1.32"))
        XCTAssertTrue(version.contains("0.x.y = dogfood only"))
        XCTAssertTrue(version.contains("1.0.0 = first build anyone else may have"))

        let xcconfig = try XCTUnwrap(repoFile("Config/VoiceDesk.xcconfig"))
        XCTAssertTrue(xcconfig.contains("#include \"Version.xcconfig\""))
        let versionInclude = try XCTUnwrap(xcconfig.range(of: "#include \"Version.xcconfig\""))
        let generatedInclude = try XCTUnwrap(xcconfig.range(of: "#include? \"Generated/GoogleSecrets.xcconfig\""))
        XCTAssertLessThan(versionInclude.lowerBound, generatedInclude.lowerBound)

        let pbx = try XCTUnwrap(pbxprojContents())
        let appDebug = pbx.range(of: "A1000000000000000000000E /* Debug */")
        let appRelease = pbx.range(of: "A1000000000000000000000F /* Release */")
        let testsDebug = pbx.range(of: "B10000000000000000000007 /* Debug */")
        XCTAssertNotNil(appDebug)
        XCTAssertNotNil(appRelease)
        XCTAssertNotNil(testsDebug)
        if let start = appDebug, let end = testsDebug {
            let appSlice = String(pbx[start.lowerBound..<end.lowerBound])
            XCTAssertFalse(
                appSlice.contains("MARKETING_VERSION"),
                "VoiceDesk app target must inherit MARKETING_VERSION from Version.xcconfig"
            )
            XCTAssertFalse(
                appSlice.contains("CURRENT_PROJECT_VERSION"),
                "VoiceDesk app target must inherit CURRENT_PROJECT_VERSION from Version.xcconfig"
            )
        }
    }

    func testInjectScriptWritesXcconfigOnly() throws {
        let script = try XCTUnwrap(repoFile("scripts/inject-google-secrets.sh"))
        XCTAssertTrue(script.contains("Config/Generated/GoogleSecrets.xcconfig"))
        XCTAssertTrue(script.contains("derive_reversed"))
        XCTAssertTrue(script.contains("GIT_SHA"))
        XCTAssertTrue(script.contains("GIT_BRANCH"))
        XCTAssertTrue(script.contains("rev-parse --short=7"))
        XCTAssertTrue(script.contains("git -C"))
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
        XCTAssertTrue(xcconfig.contains("#include \"Version.xcconfig\""))
        XCTAssertTrue(xcconfig.contains("#include? \"Generated/GoogleSecrets.xcconfig\""))
        XCTAssertTrue(xcconfig.contains("INFOPLIST_FILE = Config/Info.plist"))
        XCTAssertTrue(xcconfig.contains("DEVELOPMENT_TEAM ="))
        XCTAssertTrue(xcconfig.contains("GIT_SHA ="))
        XCTAssertTrue(xcconfig.contains("GIT_BRANCH ="))
        XCTAssertFalse(xcconfig.contains("REPLACE_ME"))
        let includeIndex = try XCTUnwrap(xcconfig.range(of: "#include? \"Generated/GoogleSecrets.xcconfig\""))
        let versionInclude = try XCTUnwrap(xcconfig.range(of: "#include \"Version.xcconfig\""))
        let reversedDefault = try XCTUnwrap(xcconfig.range(of: "GOOGLE_REVERSED_CLIENT_ID ="))
        let teamDefault = try XCTUnwrap(xcconfig.range(of: "DEVELOPMENT_TEAM ="))
        let shaDefault = try XCTUnwrap(xcconfig.range(of: "GIT_SHA ="))
        XCTAssertLessThan(versionInclude.lowerBound, includeIndex.lowerBound)
        XCTAssertLessThan(reversedDefault.lowerBound, includeIndex.lowerBound)
        XCTAssertLessThan(teamDefault.lowerBound, includeIndex.lowerBound)
        XCTAssertLessThan(shaDefault.lowerBound, includeIndex.lowerBound)

        let example = try XCTUnwrap(repoFile("VoiceDesk/Secrets.example.plist"))
        XCTAssertTrue(example.contains("<key>DEVELOPMENT_TEAM</key>"))
        XCTAssertTrue(example.contains("<key>VOICE_DOGFOOD_GITHUB_TOKEN</key>"))
        XCTAssertTrue(example.contains("<key>VOICE_DOGFOOD_GIST_ID</key>"))
        XCTAssertTrue(example.contains("<key>VOICE_DOGFOOD_UPLOAD_SECRET</key>"))
        XCTAssertTrue(script.contains("DEVELOPMENT_TEAM"))
        XCTAssertTrue(pbx.contains("DEVELOPMENT_TEAM = \"$(DEVELOPMENT_TEAM)\""))
        let teamLines = pbx.split(separator: "\n").filter { $0.contains("DEVELOPMENT_TEAM") }
        XCTAssertFalse(teamLines.isEmpty)
        for line in teamLines {
            XCTAssertTrue(
                line.contains("$(DEVELOPMENT_TEAM)"),
                "pbxproj must not pin a literal team id: \(line)"
            )
        }

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
            <key>DEVELOPMENT_TEAM</key>
            <string>A1B2C3D4E5</string>
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
        XCTAssertTrue(generated.contains("DEVELOPMENT_TEAM = A1B2C3D4E5"))
        XCTAssertTrue(generated.contains("GIT_SHA ="))
        XCTAssertTrue(generated.contains("GIT_BRANCH ="))
        XCTAssertFalse(generated.contains("REPLACE_ME"))
        // Temp SRCROOT is not a git repo — never invent a SHA.
        let shaLine = generated.split(separator: "\n").first { $0.hasPrefix("GIT_SHA") }
        XCTAssertEqual(shaLine.map(String.init), "GIT_SHA =")
        try? FileManager.default.removeItem(at: root)
    }

    func testInjectScriptWritesDevelopmentTeamWithoutGoogleClient() throws {
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
            .appendingPathComponent("voicedesk-inject-team-\(UUID().uuidString)")
        let secretsDir = root.appendingPathComponent("VoiceDesk")
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
        let secrets = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DEVELOPMENT_TEAM</key>
            <string>Z9Y8X7W6V5</string>
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
        XCTAssertTrue(generated.contains("DEVELOPMENT_TEAM = Z9Y8X7W6V5"))
        XCTAssertTrue(generated.contains("GOOGLE_CLIENT_ID ="))
        XCTAssertTrue(generated.contains("GIT_SHA ="))
        try? FileManager.default.removeItem(at: root)
    }

    func testInjectScriptMissingTeamIsNotAFailure() throws {
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
            .appendingPathComponent("voicedesk-inject-noteam-\(UUID().uuidString)")
        let secretsDir = root.appendingPathComponent("VoiceDesk")
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
        let secrets = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>GOOGLE_CLIENT_ID</key>
            <string>123-abc.apps.googleusercontent.com</string>
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
        XCTAssertFalse(generated.contains("DEVELOPMENT_TEAM ="))
        XCTAssertTrue(generated.contains("GIT_SHA ="))
        try? FileManager.default.removeItem(at: root)
    }

    func testInjectScriptBakesShortSHAFromSRCROOTGit() throws {
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
            .appendingPathComponent("voicedesk-inject-git-\(UUID().uuidString)")
        let secretsDir = root.appendingPathComponent("VoiceDesk")
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
        try "note".write(to: root.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        let gitEnv = [
            "GIT_AUTHOR_NAME": "VoiceDesk Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "VoiceDesk Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        ]
        func runGit(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            process.environment = ProcessInfo.processInfo.environment.merging(gitEnv) { _, new in new }
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " "))")
        }
        try runGit(["init"])
        try runGit(["checkout", "-b", "cursor/test-bake"])
        try runGit(["add", "README"])
        try runGit(["commit", "-m", "bake"])
        let shaProcess = Process()
        shaProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        shaProcess.arguments = ["-C", root.path, "rev-parse", "--short=7", "HEAD"]
        let pipe = Pipe()
        shaProcess.standardOutput = pipe
        try shaProcess.run()
        shaProcess.waitUntilExit()
        let expectedSHA = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        XCTAssertFalse(expectedSHA.isEmpty)

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
        XCTAssertTrue(generated.contains("GIT_SHA = \(expectedSHA)"))
        XCTAssertTrue(generated.contains("GIT_BRANCH = cursor/test-bake"))
        XCTAssertFalse(generated.contains("1fa0a0e"), "must bake the temp repo SHA, not a committed fixture")
        try? FileManager.default.removeItem(at: root)
    }

    func testLiveSyncUsesRecentInboxLimitOf25() throws {
        let sync = try XCTUnwrap(repoFile("VoiceDesk/Voice/GoogleSync.swift"))
        XCTAssertTrue(sync.contains("GoogleSyncPolicy.recentInboxLimit"))
        XCTAssertFalse(sync.contains("recentMessageLimit: Int = 8"))
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertTrue(app.contains("DeskSnapshotMerge.applying"))
        XCTAssertFalse(
            app.contains("deskSnapshot = next"),
            "sync must merge into the hot store, not replace it"
        )
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
