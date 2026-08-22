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
        XCTAssertFalse(pbx.contains("PBXShellScriptBuildPhase"))
        XCTAssertFalse(pbx.contains("Inject Google secrets"))
        XCTAssertFalse(pbx.contains("shellScript"))
        XCTAssertTrue(pbx.contains("GENERATE_INFOPLIST_FILE = YES"))
    }

    func testInjectScriptIsManualAndNotABuildPhase() throws {
        let script = try XCTUnwrap(repoFile("scripts/inject-google-secrets.sh"))
        XCTAssertTrue(script.contains("Manual/dev helper"))
        XCTAssertTrue(script.contains("Config/Generated/GoogleSecrets.xcconfig"))
        XCTAssertFalse(script.contains("INFOPLIST_PATH"))
        XCTAssertFalse(script.contains("TARGET_BUILD_DIR"))
        XCTAssertFalse(script.contains("Set :GIDClientID"))
        XCTAssertFalse(script.contains("CFBundleURLTypes"))

        let xcconfig = try XCTUnwrap(repoFile("Config/VoiceDesk.xcconfig"))
        XCTAssertTrue(xcconfig.contains("#include? \"Generated/GoogleSecrets.xcconfig\""))
        XCTAssertTrue(xcconfig.contains("INFOPLIST_FILE = Config/Info.plist"))
    }

    func testGoogleSignInPackageIsPinned() throws {
        let pbx = try XCTUnwrap(pbxprojContents(), "VoiceDesk.xcodeproj should sit next to VoiceDeskLogic")
        XCTAssertTrue(pbx.contains("XCRemoteSwiftPackageReference \"GoogleSignIn-iOS\""))
        XCTAssertTrue(pbx.contains("https://github.com/google/GoogleSignIn-iOS"))
        XCTAssertTrue(pbx.contains("minimumVersion = 9.0.0"))
        XCTAssertTrue(pbx.contains("productName = GoogleSignIn"))
        XCTAssertFalse(pbx.contains("productName = GoogleSignInSwift"))

        let resolved = try XCTUnwrap(
            repoFile("VoiceDesk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
            "Package.resolved must be committed so Xcode can find GoogleSignIn"
        )
        XCTAssertTrue(resolved.contains("\"identity\" : \"googlesignin-ios\""))
        XCTAssertTrue(resolved.contains("\"version\" : \"9.2.0\""))
        XCTAssertTrue(resolved.contains("appauth-ios"))
        XCTAssertTrue(resolved.contains("gtmappauth"))
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
