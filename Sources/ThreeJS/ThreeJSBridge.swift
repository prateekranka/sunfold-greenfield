import Combine
import Foundation
import WebKit

enum ThreeJSBridgeCommand: String, CaseIterable, Codable, Sendable {
    case startGame
    case pauseGame
    case resumeGame
    case saveGame
    case loadGame
    case returnToMenu
}

struct ThreeJSBridgeEnvelope: Codable, Equatable, Sendable {
    static let currentProtocolVersion = 1
    /// Moved from 1 with #22, when the placeholder snapshot became the real
    /// serialised simulation state. A mismatch fails closed rather than
    /// loading a world this build cannot reproduce.
    static let currentSaveSchemaVersion = 2

    let protocolVersion: Int
    let type: String
    let name: String
    let saveSchemaVersion: Int?
    let payload: [String: String]

    init(
        protocolVersion: Int = ThreeJSBridgeEnvelope.currentProtocolVersion,
        type: String,
        name: String,
        saveSchemaVersion: Int? = nil,
        payload: [String: String] = [:]
    ) {
        self.protocolVersion = protocolVersion
        self.type = type
        self.name = name
        self.saveSchemaVersion = saveSchemaVersion
        self.payload = payload
    }
}

enum ThreeJSBridgeProtocol {
    static let commandNames: Set<String> = Set(ThreeJSBridgeCommand.allCases.map(\.rawValue))
    /// The two messages that carry a save document and must state its schema version.
    static let saveBearingNames: Set<String> = ["saveReady", "loadGame"]

    static let eventNames: Set<String> = [
        "runtimeLoaded",
        "runtimeReady",
        "runtimePaused",
        "runtimeResumed",
        "saveReady",
        "battleFinished",
        "returnedToMenu",
        "fatalError",
        "pauseRequested",
        "resumeRequested",
        "saveRequested",
        "returnToMenuRequested"
    ]

    static func validationError(for envelope: ThreeJSBridgeEnvelope) -> String? {
        guard envelope.protocolVersion == ThreeJSBridgeEnvelope.currentProtocolVersion else {
            return envelope.protocolVersion < ThreeJSBridgeEnvelope.currentProtocolVersion
                ? "The JavaScript bridge protocol version is stale."
                : "The JavaScript bridge protocol version is from the future."
        }
        guard envelope.type == "command" || envelope.type == "event" else {
            return "The JavaScript bridge message type is invalid."
        }

        let knownNames = envelope.type == "command" ? commandNames : eventNames
        guard knownNames.contains(envelope.name) else {
            return "The JavaScript bridge message name is invalid."
        }

        let allowedPayloadKeys: Set<String>
        switch envelope.name {
        case "startGame": allowedPayloadKeys = ["faction", "seed", "mapID"]
        case "runtimeLoaded": allowedPayloadKeys = ["offline", "renderer"]
        case "runtimeReady": allowedPayloadKeys = ["offline", "renderer", "faction"]
        case "saveReady": allowedPayloadKeys = ["snapshotID", "snapshot"]
        // A save document is lifecycle traffic, which #19 permits. It crosses
        // once, at a player-driven moment, never per frame.
        case "loadGame": allowedPayloadKeys = ["snapshot"]
        case "battleFinished": allowedPayloadKeys = ["winner", "reason"]
        case "fatalError": allowedPayloadKeys = ["code", "message"]
        default: allowedPayloadKeys = []
        }
        guard Set(envelope.payload.keys).isSubset(of: allowedPayloadKeys) else {
            return "The JavaScript bridge payload contains an unsupported field."
        }

        if saveBearingNames.contains(envelope.name) {
            guard envelope.saveSchemaVersion == ThreeJSBridgeEnvelope.currentSaveSchemaVersion else {
                if let saveSchemaVersion = envelope.saveSchemaVersion,
                   saveSchemaVersion > ThreeJSBridgeEnvelope.currentSaveSchemaVersion {
                    return "The save schema version is from the future."
                }
                return "The save schema version is missing or stale."
            }
        } else if envelope.saveSchemaVersion != nil {
            return "The save schema version is only valid on save-bearing messages."
        }

        return nil
    }
}

struct ThreeJSBridgeTrace: Identifiable, Equatable, Sendable {
    let id = UUID()
    let direction: String
    let name: String
    let protocolVersion: Int
    let saveSchemaVersion: Int?
    let payloadKeys: [String]
}

@MainActor
final class ThreeJSBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published private(set) var bridgeReady = false
    @Published private(set) var runtimeReady = false
    @Published private(set) var lastEvent: String?
    @Published private(set) var fatalErrorMessage: String?
    /// The most recent save document the runtime produced. Opaque to Swift.
    @Published private(set) var lastSnapshot: String?
    @Published private(set) var trace: [ThreeJSBridgeTrace] = []

    private weak var webView: WKWebView?
    private var pendingCommands: [(ThreeJSBridgeCommand, [String: String]?)] = []

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func reportLocalFailure(_ message: String) {
        fatalErrorMessage = message
    }

    func resetForNewDocument() {
        bridgeReady = false
        runtimeReady = false
        lastEvent = nil
        fatalErrorMessage = nil
        lastSnapshot = nil
        pendingCommands.removeAll()
        trace.removeAll()
        webView = nil
    }

    func send(_ command: ThreeJSBridgeCommand, payload: [String: String]? = nil) {
        guard bridgeReady else {
            pendingCommands.append((command, payload))
            return
        }
        sendNow(command, payload: payload)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "sunfold",
              let dictionary = message.body as? [String: Any],
              JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let envelope = try? JSONDecoder().decode(ThreeJSBridgeEnvelope.self, from: data)
        else {
            failClosed("The JavaScript bridge sent an invalid message.")
            return
        }

        guard let validationError = ThreeJSBridgeProtocol.validationError(for: envelope) else {
            record(direction: "JS→Swift", envelope: envelope)
            handle(envelope)
            return
        }
        failClosed(validationError)
    }

    private func handle(_ envelope: ThreeJSBridgeEnvelope) {
        lastEvent = envelope.name
        switch envelope.name {
        case "runtimeLoaded":
            bridgeReady = true
            let queued = pendingCommands
            pendingCommands.removeAll()
            queued.forEach { sendNow($0.0, payload: $0.1) }
        case "runtimeReady":
            runtimeReady = true
        case "saveReady":
            lastSnapshot = envelope.payload["snapshot"]
        case "runtimePaused":
            runtimeReady = true
        case "runtimeResumed":
            runtimeReady = true
        case "pauseRequested":
            send(.pauseGame)
        case "resumeRequested":
            send(.resumeGame)
        case "saveRequested":
            send(.saveGame)
        case "returnToMenuRequested":
            send(.returnToMenu)
        case "returnedToMenu":
            runtimeReady = false
        case "fatalError":
            failClosed(envelope.payload["message"] ?? "The runtime reported a fatal error.")
        default:
            break
        }
    }

    private func sendNow(_ command: ThreeJSBridgeCommand, payload: [String: String]?) {
        let envelope = ThreeJSBridgeEnvelope(
            type: "command",
            name: command.rawValue,
            saveSchemaVersion: ThreeJSBridgeProtocol.saveBearingNames.contains(command.rawValue)
                ? ThreeJSBridgeEnvelope.currentSaveSchemaVersion
                : nil,
            payload: payload ?? [:]
        )
        guard ThreeJSBridgeProtocol.validationError(for: envelope) == nil,
              let data = try? JSONEncoder().encode(envelope),
              let json = String(data: data, encoding: .utf8),
              let webView
        else {
            failClosed("The native bridge refused an invalid command envelope.")
            return
        }

        record(direction: "Swift→JS", envelope: envelope)
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.sunfoldBridge.receive(JSON.parse('\(escaped)'))")
    }

    private func failClosed(_ message: String) {
        bridgeReady = false
        runtimeReady = false
        fatalErrorMessage = message
    }

    private func record(direction: String, envelope: ThreeJSBridgeEnvelope) {
        let payloadKeys = envelope.payload.keys.sorted()
        trace.append(
            ThreeJSBridgeTrace(
                direction: direction,
                name: envelope.name,
                protocolVersion: envelope.protocolVersion,
                saveSchemaVersion: envelope.saveSchemaVersion,
                payloadKeys: payloadKeys
            )
        )
        if trace.count > 64 { trace.removeFirst(trace.count - 64) }
#if DEBUG
        print(
            "[ThreeJSBridge] direction=\(direction) name=\(envelope.name) " +
            "protocolVersion=\(envelope.protocolVersion) payloadKeys=\(payloadKeys.joined(separator: ","))"
        )
#endif
    }
}
