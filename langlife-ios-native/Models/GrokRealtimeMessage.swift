import Foundation

// MARK: - Client → Server Messages

enum GrokClientMessage {
    enum TurnDetection {
        case serverVAD
        case none
    }

    case sessionUpdate(instructions: String, tools: [[String: Any]], turnDetection: TurnDetection)
    case inputAudioBufferAppend(audio: String)
    case inputAudioBufferClear
    case inputAudioBufferCommit
    case conversationItemCreate(callId: String, output: String)
    case conversationUserMessageCreate(text: String)
    case responseCreate(modalities: [String])
    case pong(eventID: String?)

    func toJSON() -> [String: Any] {
        switch self {
        case .sessionUpdate(let instructions, let tools, let turnDetection):
            let turnDetectionValue: Any
            switch turnDetection {
            case .serverVAD:
                turnDetectionValue = ["type": "server_vad"]
            case .none:
                turnDetectionValue = NSNull()
            }
            return [
                "type": "session.update",
                "session": [
                    "instructions": instructions,
                    "voice": "Ara",
                    "turn_detection": turnDetectionValue,
                    "audio": [
                        "input": ["format": ["type": "audio/pcm", "rate": 24000]],
                        "output": ["format": ["type": "audio/pcm", "rate": 24000]]
                    ],
                    "tools": tools
                ] as [String: Any]
            ]
        case .inputAudioBufferAppend(let audio):
            return [
                "type": "input_audio_buffer.append",
                "audio": audio
            ]
        case .inputAudioBufferClear:
            return [
                "type": "input_audio_buffer.clear"
            ]
        case .inputAudioBufferCommit:
            return [
                "type": "input_audio_buffer.commit"
            ]
        case .conversationItemCreate(let callId, let output):
            return [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": output
                ] as [String: Any]
            ]
        case .conversationUserMessageCreate(let text):
            return [
                "type": "conversation.item.create",
                "item": [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": text
                        ]
                    ]
                ] as [String: Any]
            ]
        case .responseCreate(let modalities):
            return [
                "type": "response.create",
                "response": [
                    "modalities": modalities
                ]
            ]
        case .pong(let eventID):
            var json: [String: Any] = ["type": "pong"]
            if let eventID, !eventID.isEmpty {
                json["event_id"] = eventID
            }
            return json
        }
    }

    func toData() throws -> Data {
        try JSONSerialization.data(withJSONObject: toJSON())
    }
}

// MARK: - Server → Client Messages

enum GrokServerMessage {
    case transportConnected
    case transportDisconnected(reason: String)
    case sessionCreated(turnDetectionType: String?)
    case sessionUpdated(turnDetectionType: String?, inputRate: Int?, outputRate: Int?)
    case conversationCreated
    case ping(eventID: String?)
    case inputAudioBufferSpeechStarted
    case inputAudioBufferSpeechStopped
    case inputAudioBufferCommitted
    case inputAudioBufferCleared
    case conversationItemAdded(role: String?, transcript: String?)
    case inputAudioTranscriptionCompleted(transcript: String)
    case responseCreated
    case responseOutputItemAdded
    case responseOutputItemDone
    case responseContentPartAdded
    case responseContentPartDone
    case responseAudioDelta(delta: String)
    case responseAudioDone
    case responseAudioTranscriptDelta(delta: String)
    case responseAudioTranscriptDone(transcript: String)
    case responseFunctionCallArgumentsDone(callId: String, name: String, arguments: String)
    case responseDone
    case error(message: String)
    case unknown(type: String)

    static func parse(_ data: Data) -> GrokServerMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "session.created":
            let session = json["session"] as? [String: Any]
            let turnDetectionType = parseTurnDetectionType(fromSession: session)
            return .sessionCreated(turnDetectionType: turnDetectionType)
        case "session.updated":
            let session = json["session"] as? [String: Any]
            let turnDetectionType = parseTurnDetectionType(fromSession: session)
            let (inputRate, outputRate) = parseAudioRates(fromSession: session)
            return .sessionUpdated(
                turnDetectionType: turnDetectionType,
                inputRate: inputRate,
                outputRate: outputRate
            )
        case "conversation.created":
            return .conversationCreated
        case "ping":
            return .ping(eventID: json["event_id"] as? String)
        case "input_audio_buffer.speech_started":
            return .inputAudioBufferSpeechStarted
        case "input_audio_buffer.speech_stopped":
            return .inputAudioBufferSpeechStopped
        case "input_audio_buffer.committed":
            return .inputAudioBufferCommitted
        case "input_audio_buffer.cleared":
            return .inputAudioBufferCleared
        case "conversation.item.added":
            let item = json["item"] as? [String: Any]
            let role = item?["role"] as? String
            let content = item?["content"] as? [[String: Any]]
            let transcript = content?.compactMap { part -> String? in
                if let transcript = part["transcript"] as? String, !transcript.isEmpty {
                    return transcript
                }
                if let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
                return nil
            }.joined(separator: " ")
            return .conversationItemAdded(role: role, transcript: transcript)
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (json["transcript"] as? String) ?? ""
            return .inputAudioTranscriptionCompleted(transcript: transcript)
        case "response.created":
            return .responseCreated
        case "response.output_item.added":
            return .responseOutputItemAdded
        case "response.output_item.done":
            return .responseOutputItemDone
        case "response.content_part.added":
            return .responseContentPartAdded
        case "response.content_part.done":
            return .responseContentPartDone
        case "response.output_audio.delta":
            let delta = (json["delta"] as? String) ?? ""
            return .responseAudioDelta(delta: delta)
        case "response.output_audio.done":
            return .responseAudioDone
        case "response.output_audio_transcript.delta":
            let delta = (json["delta"] as? String) ?? ""
            return .responseAudioTranscriptDelta(delta: delta)
        case "response.output_audio_transcript.done":
            let transcript = (json["transcript"] as? String) ?? ""
            return .responseAudioTranscriptDone(transcript: transcript)
        case "response.function_call_arguments.done":
            let callId = (json["call_id"] as? String) ?? ""
            let name = (json["name"] as? String) ?? ""
            let arguments = (json["arguments"] as? String) ?? ""
            return .responseFunctionCallArgumentsDone(callId: callId, name: name, arguments: arguments)
        case "response.done":
            return .responseDone
        case "error":
            let errorObj = json["error"] as? [String: Any]
            let message = (errorObj?["message"] as? String) ?? "Unknown error"
            return .error(message: message)
        default:
            return .unknown(type: type)
        }
    }

    private static func parseTurnDetectionType(fromSession session: [String: Any]?) -> String? {
        guard let session else { return nil }
        let turnDetection = session["turn_detection"]
        if turnDetection is NSNull {
            return nil
        }
        if let turnDetection = turnDetection as? [String: Any] {
            return turnDetection["type"] as? String
        }
        return nil
    }

    private static func parseAudioRates(fromSession session: [String: Any]?) -> (Int?, Int?) {
        guard let session,
              let audio = session["audio"] as? [String: Any] else {
            return (nil, nil)
        }
        let inputRate = (((audio["input"] as? [String: Any])?["format"] as? [String: Any])?["rate"] as? Int)
        let outputRate = (((audio["output"] as? [String: Any])?["format"] as? [String: Any])?["rate"] as? Int)
        return (inputRate, outputRate)
    }
}
