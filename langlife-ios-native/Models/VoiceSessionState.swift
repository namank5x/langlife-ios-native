import Foundation

enum VoiceSessionState: Equatable {
    case idle
    case connecting(ConnectionStage)
    case conversationActive(ConversationSubstate)
    case endingSession
    case showingResults
    case error(message: String)

    enum ConnectionStage: Equatable {
        case openingSocket
        case configuringSession
        case startingAudio
        case retrying(attempt: Int)

        var statusText: String {
            switch self {
            case .openingSocket:
                return "Connecting to voice service..."
            case .configuringSession:
                return "Preparing session..."
            case .startingAudio:
                return "Starting audio..."
            case .retrying(let attempt):
                return "Reconnecting (\(attempt)/2)..."
            }
        }
    }

    enum ConversationSubstate: Equatable {
        case readyToSpeak
        case recording
        case agentSpeaking
        case processing
    }

    var isActive: Bool {
        switch self {
        case .connecting, .conversationActive:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return ""
        case .connecting(let stage):
            return stage.statusText
        case .conversationActive(.readyToSpeak):
            return "Hold to speak"
        case .conversationActive(.recording):
            return "Recording..."
        case .conversationActive(.agentSpeaking):
            return "Speaking..."
        case .conversationActive(.processing):
            return "Thinking..."
        case .endingSession:
            return "Saving session..."
        case .showingResults:
            return ""
        case .error(let message):
            return message
        }
    }
}
