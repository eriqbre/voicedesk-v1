import Foundation
import VoiceDeskLogic

/// Same EchoBargeIn / intent / stayLive gates the phone uses.
/// Invoked by `scripts/replay-voice-tape.py`. Never prints secrets.
@main
enum VoiceTapeGate {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "decide"
        switch command {
        case "decide":
            decide()
        case "session-update":
            sessionUpdate(contextName: value(args, "--context") ?? "connected")
        case "catalog":
            catalog()
        case "stay-live":
            stayLive(userOff: args.contains("--user-stop"), audioStarted: !args.contains("--no-audio"))
        default:
            fail("unknown command")
        }
    }

    private static func decide() {
        let input = readStdinJSON()
        let text = string(input["text"]) ?? ""
        let lastSpoken = string(input["lastSpokenLine"]) ?? ""
        let contextName = string(input["context"]) ?? "connected"
        let voiceState = VoiceState(rawValue: string(input["voiceState"]) ?? "speaking") ?? .speaking
        let decision = VoiceTape.evaluate(
            text: text,
            voiceState: voiceState,
            lastSpokenLine: lastSpoken,
            contextName: contextName
        )
        emit(decision)
    }

    private static func sessionUpdate(contextName: String) {
        let object = VoiceTape.sessionUpdateObject(contextName: contextName)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { fail("session.update") }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func catalog() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(VoiceTape.catalog) else { fail("catalog") }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func stayLive(userOff: Bool, audioStarted: Bool) {
        let decision = VoiceTape.stayLiveAfterClose1000(
            userWantsVoiceOff: userOff,
            audioStarted: audioStarted
        )
        let name: String
        switch decision {
        case .reconnect: name = "reconnect"
        case .stayIdle: name = "stayIdle"
        case .keepListening: name = "keepListening"
        }
        emit([
            "decision": name,
            "reconnect": decision == .reconnect
        ])
    }

    private static func emit(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { fail("encode") }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { fail("encode") }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func readStdinJSON() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("stdin json")
        }
        return object
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func value(_ args: [String], _ flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("VoiceTapeGate: \(message)\n".utf8))
        exit(2)
    }
}
