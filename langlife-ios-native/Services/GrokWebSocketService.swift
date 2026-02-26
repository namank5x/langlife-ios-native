import Foundation

final class GrokWebSocketService: NSObject, URLSessionWebSocketDelegate {
    private struct OutboundEnvelope {
        let text: String
        let eventType: String?
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var continuation: AsyncStream<GrokServerMessage>.Continuation?
    private let sendQueue = DispatchQueue(label: "GrokWebSocketService.sendQueue")
    private var pendingOutboundMessages: [OutboundEnvelope] = []
    private var isSendInFlight = false
    private var activeTaskIdentifier: Int?
    private(set) var isConnected = false
    private var outboundAppendQueuedCount = 0
    private var outboundAppendSentCount = 0
    private var outboundClearSentCount = 0
    private var outboundCommitSentCount = 0
    private var outboundResponseCreateSentCount = 0
    private var outboundSessionUpdateSentCount = 0

    private static let maxPendingOutboundMessages = 160

    var messages: AsyncStream<GrokServerMessage> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func connect(token: String) {
        guard let url = URL(string: "wss://api.x.ai/v1/realtime") else { return }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sendQueue.sync {
            pendingOutboundMessages.removeAll()
            isSendInFlight = false
            isConnected = false
            activeTaskIdentifier = nil
            outboundAppendQueuedCount = 0
            outboundAppendSentCount = 0
            outboundClearSentCount = 0
            outboundCommitSentCount = 0
            outboundResponseCreateSentCount = 0
            outboundSessionUpdateSentCount = 0
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        sendQueue.sync {
            self.activeTaskIdentifier = task.taskIdentifier
            self.isConnected = false
        }
        task.resume()
        print("[GrokWS] Connecting to \(url)")
        receiveNext(for: task)
    }

    func send(_ message: GrokClientMessage) {
        do {
            let data = try message.toData()
            guard let text = String(data: data, encoding: .utf8) else {
                print("[GrokWS] Serialization error: produced non-utf8 payload")
                return
            }
            let eventType = eventType(for: message)
            sendQueue.async { [weak self] in
                self?.enqueueOutbound(text: text, eventType: eventType)
            }
        } catch {
            print("[GrokWS] Serialization error: \(error.localizedDescription)")
        }
    }

    private func enqueueOutbound(text: String, eventType: String?) {
        guard webSocketTask != nil else { return }

        if pendingOutboundMessages.count >= Self.maxPendingOutboundMessages {
            let overflow = pendingOutboundMessages.count - Self.maxPendingOutboundMessages + 1
            pendingOutboundMessages.removeFirst(overflow)
            print("[GrokWS] Dropped \(overflow) queued messages before send")
        }

        pendingOutboundMessages.append(OutboundEnvelope(text: text, eventType: eventType))
        if eventType == "input_audio_buffer.append" {
            outboundAppendQueuedCount += 1
            if outboundAppendQueuedCount == 1 || outboundAppendQueuedCount % 25 == 0 {
                print("[GrokWS] Queued audio append count=\(outboundAppendQueuedCount) pending=\(pendingOutboundMessages.count)")
            }
        }

        drainOutboundQueueLocked()
    }

    private func drainOutboundQueueLocked() {
        guard isConnected else { return }
        guard !isSendInFlight else { return }
        guard let task = webSocketTask else { return }
        guard let envelope = pendingOutboundMessages.first else { return }

        isSendInFlight = true
        pendingOutboundMessages.removeFirst()
        let taskIdentifier = task.taskIdentifier
        task.send(.string(envelope.text)) { [weak self] error in
            guard let self else { return }
            self.sendQueue.async {
                guard self.activeTaskIdentifier == taskIdentifier else {
                    self.isSendInFlight = false
                    return
                }

                if let error {
                    self.isSendInFlight = false
                    print("[GrokWS] Send error: \(error.localizedDescription)")
                    self.handleDisconnect(reason: "Send error: \(error.localizedDescription)")
                    return
                }

                self.logSentEnvelope(envelope)
                self.isSendInFlight = false
                self.drainOutboundQueueLocked()
            }
        }
    }

    private func logSentEnvelope(_ envelope: OutboundEnvelope) {
        let eventType = envelope.eventType
        if eventType == "input_audio_buffer.append" {
            outboundAppendSentCount += 1
            if outboundAppendSentCount == 1 || outboundAppendSentCount % 40 == 0 {
                print("[GrokWS] Sent audio append count=\(outboundAppendSentCount) payload_bytes=\(envelope.text.utf8.count)")
            }
        } else if eventType == "input_audio_buffer.clear" {
            outboundClearSentCount += 1
            print("[GrokWS] Sent clear count=\(outboundClearSentCount)")
        } else if eventType == "input_audio_buffer.commit" {
            outboundCommitSentCount += 1
            print("[GrokWS] Sent commit count=\(outboundCommitSentCount)")
        } else if eventType == "response.create" {
            outboundResponseCreateSentCount += 1
            print("[GrokWS] Sent response.create count=\(outboundResponseCreateSentCount)")
        } else if eventType == "session.update" {
            outboundSessionUpdateSentCount += 1
            print("[GrokWS] Sent session.update count=\(outboundSessionUpdateSentCount)")
        } else if let eventType, eventType != "pong" {
            print("[GrokWS] Sent event type=\(eventType)")
        }
    }

    func disconnect() {
        sendQueue.sync {
            isConnected = false
            activeTaskIdentifier = nil
            isSendInFlight = false
            pendingOutboundMessages.removeAll()
            outboundAppendQueuedCount = 0
            outboundAppendSentCount = 0
            outboundClearSentCount = 0
            outboundCommitSentCount = 0
            outboundResponseCreateSentCount = 0
            outboundSessionUpdateSentCount = 0
        }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        continuation?.finish()
        continuation = nil
    }

    private func receiveNext(for task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            guard self.webSocketTask?.taskIdentifier == task.taskIdentifier else { return }
            switch result {
            case .success(let wsMessage):
                let data: Data?
                switch wsMessage {
                case .data(let d):
                    data = d
                case .string(let text):
                    data = text.data(using: .utf8)
                @unknown default:
                    data = nil
                }

                if let data {
                    if let message = GrokServerMessage.parse(data) {
                        if case .unknown(let type) = message {
                            let payload = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                            print("[GrokWS] Unknown event: \(type) payload=\(payload)")
                        } else if case .error(let msg) = message {
                            print("[GrokWS] Server error: \(msg)")
                        }
                        self.continuation?.yield(message)
                    } else {
                        let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "nil"
                        print("[GrokWS] Unparseable message: \(preview)")
                    }
                }
                self.receiveNext(for: task)
            case .failure(let error):
                print("[GrokWS] Receive error: \(error.localizedDescription)")
                self.handleDisconnect(reason: "Receive error: \(error.localizedDescription)")
            }
        }
    }

    private func handleDisconnect(reason: String) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.activeTaskIdentifier = nil
            self.isSendInFlight = false
            self.pendingOutboundMessages.removeAll()
            self.outboundAppendQueuedCount = 0
            self.outboundAppendSentCount = 0
            self.outboundClearSentCount = 0
            self.outboundCommitSentCount = 0
            self.outboundResponseCreateSentCount = 0
            self.outboundSessionUpdateSentCount = 0
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        guard let continuation else { return }
        continuation.yield(.transportDisconnected(reason: reason))
        continuation.finish()
        self.continuation = nil
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let activeIdentifier = sendQueue.sync { activeTaskIdentifier }
        guard webSocketTask.taskIdentifier == activeIdentifier else { return }
        print("[GrokWS] Connected")
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.drainOutboundQueueLocked()
        }
        continuation?.yield(.transportConnected)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let activeIdentifier = sendQueue.sync { activeTaskIdentifier }
        guard webSocketTask.taskIdentifier == activeIdentifier else { return }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        let description: String
        if let reasonText, !reasonText.isEmpty {
            description = "Connection closed (\(closeCode.rawValue)): \(reasonText)"
        } else {
            description = "Connection closed (\(closeCode.rawValue))"
        }
        handleDisconnect(reason: description)
    }

    private func eventType(for message: GrokClientMessage) -> String {
        switch message {
        case .sessionUpdate:
            return "session.update"
        case .inputAudioBufferAppend:
            return "input_audio_buffer.append"
        case .inputAudioBufferClear:
            return "input_audio_buffer.clear"
        case .inputAudioBufferCommit:
            return "input_audio_buffer.commit"
        case .conversationItemCreate, .conversationUserMessageCreate:
            return "conversation.item.create"
        case .responseCreate:
            return "response.create"
        case .pong:
            return "pong"
        }
    }

}
