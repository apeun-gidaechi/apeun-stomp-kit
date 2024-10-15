import SocketRocket
import Combine

public enum ApeunStompEvent {
    case stompClient(body: String?, header: StompHeaders?, destination: String)
    case stompClientDidDisconnect
    case stompClientDidConnect
    case serverDidSendReceipt(receiptId: String)
    case serverDidSendError(description: String, message: String?)
    case serverDidSendPing
}

public class ApeunStomp: NSObject {
    // MARK: - Parameters
    private var request: URLRequest
    public var connectionHeaders: StompHeaders?
    private let log: Bool
    
    var socket: SRWebSocket?
    var sessionId: String?
    
    var connection: Bool = false
    private var reconnectTimer : Timer?
    
    public let subject = PassthroughSubject<ApeunStompEvent, Never>()
    public var jsonDecoder = JSONDecoder()
    
    public init(
        request: URLRequest,
        connectionHeaders: StompHeaders? = nil,
        log: Bool = true
    ) {
        self.request = request
        self.connectionHeaders = connectionHeaders
        self.log = log
    }
    
    // MARK: - Start / End
    
    public func openSocket() {
        if socket == nil || socket?.readyState == .CLOSED {
            self.connection = true
            socket = SRWebSocket(urlRequest: request)
            socket!.delegate = self
            socket!.open()
        }
    }
    
    private func closeSocket() {
        subject.send(.stompClientDidDisconnect)
        connection = false
        if socket != nil {
            // Close the socket
            socket!.close()
            socket!.delegate = nil
            socket = nil
        }
    }
    
    private func connect() {
        guard socket?.readyState == .OPEN else {
            openSocket()
            return
        }
        // Support for Spring Boot 2.1.x
        if connectionHeaders == nil {
            connectionHeaders = [StompCommands.commandHeaderAcceptVersion.rawValue:"1.1,1.2"]
        } else {
            connectionHeaders?[StompCommands.commandHeaderAcceptVersion.rawValue] = "1.1,1.2"
        }
        // at the moment only anonymous logins
        self.sendFrame(command: .commandConnect, header: connectionHeaders)
    }
    
    // MARK: - Send
    public func sendJSONForDict(dict: Encodable, to destination: String) {
        do {
            let json = try String(decoding: JSONEncoder().encode(dict), as: UTF8.self)
            if log {
                var encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let json = try String(decoding: encoder.encode(dict), as: UTF8.self)
                print(json)
            }
            let header = [StompCommands.commandHeaderContentType.rawValue:"application/json;charset=UTF-8"]
            sendMessage(message: json, to: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("😱 STOMP error serializing JSON: \(error)")
        }
    }
    
    public func sendMessage(
        message: String,
        to destination: String,
        withHeaders headers: StompHeaders?,
        withReceipt receipt: String?
    ) {
        var headers = headers ?? [:]
        
        // Setting up the receipt.
        if let receipt = receipt {
            headers[StompCommands.commandHeaderReceipt.rawValue] = receipt
        }
        
        // Setting up header destination.
        headers[StompCommands.commandHeaderDestination.rawValue] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headers[StompCommands.commandHeaderContentLength.rawValue] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headers[StompCommands.commandHeaderContentType.rawValue] == nil {
            headers[StompCommands.commandHeaderContentType.rawValue] = "text/plain"
        }
        sendFrame(
            body: message,
            command: .commandSend,
            header: headers
        )
    }
    
    
    private func sendFrame(
        body: String? = nil,
        command: StompCommands?,
        header: StompHeaders?
    ) {
        guard socket?.readyState == .OPEN else {
            subject.send(.stompClientDidDisconnect)
            connection = false
            return
        }
        var frameString = ""
        if let command {
            frameString = "\(command.rawValue)\n"
        }
        
        header?.forEach{ key, value in
            frameString += "\(key):\(value)\n"
        }
        
        if let body {
            frameString += "\n\(body)"
        }
        
        if body == nil {
            frameString += "\n"
        }
        
//        frameString += StompCommands.controlChar.rawValue
        frameString += String(format: "%C", arguments: [0x00])
        
        print(frameString)
        
        try! socket?.send(string: frameString)
    }
    
    // MARK: - Utils
    private func destinationFromHeader(header: StompHeaders) -> String {
        for key in header.keys {
            if key == "destination" {
                let destination = header[key]!
                return destination
            }
        }
        return ""
    }
    
    // MARK: - Receive
    private func receiveFrame(frame: Frame) {
        switch frame.command {
        case .responseFrameConnected:
            if let sessId = frame.headers[StompCommands.responseHeaderSession.rawValue] {
                sessionId = sessId
            }
            subject.send(.stompClientDidConnect)
        case .responseFrameMessage:
            subject.send(.stompClient(body: frame.body, header: frame.headers, destination: self.destinationFromHeader(header: frame.headers)))
        case .responseFrameReceipt:
            if let receiptId = frame.headers[StompCommands.responseHeaderReceiptId.rawValue] {
                subject.send(.serverDidSendReceipt(receiptId: receiptId))
            }
        case .responseFrameError:
            if let msg = frame.headers[StompCommands.responseHeaderErrorMessage.rawValue] {
                subject.send(.serverDidSendError(description: msg, message: frame.body))
            }
        default:
            break
        }
    }
    
    public func subscribeToDestination(destination: String, ackMode: StompAckMode) {
        let ack = switch ackMode {
        case StompAckMode.ClientMode:
            StompCommands.ackClient
        case StompAckMode.ClientIndividualMode:
            StompCommands.ackClientIndividual
        default:
            StompCommands.ackAuto
        }
        var headers = [
            StompCommands.commandHeaderDestination.rawValue: destination,
            StompCommands.commandHeaderAck.rawValue: ack.rawValue,
            StompCommands.commandHeaderId.rawValue: ""
        ]
        if destination != "" {
            headers = [
                StompCommands.commandHeaderDestination.rawValue: destination,
                StompCommands.commandHeaderAck.rawValue: ack.rawValue,
                StompCommands.commandHeaderId.rawValue: destination
            ]
        }
        self.sendFrame(body: nil, command: StompCommands.commandSubscribe, header: headers)
    }
    
    public func subscribeWithHeader(destination: String, withHeader header: StompHeaders) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination.rawValue] = destination
        sendFrame(body: nil, command: .commandSubscribe, header: headerToSend)
    }
    
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderId.rawValue] = destination
        sendFrame(body: nil, command: .commandUnsubscribe, header: headerToSend)
    }
    
    public func begin(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction.rawValue] = transactionId
        sendFrame(command: .commandBegin, header: headerToSend)
    }
    
    public func commit(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction.rawValue] = transactionId
        sendFrame(command: .commandCommit, header: headerToSend)
    }
    
    public func abort(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction.rawValue] = transactionId
        sendFrame(command: .commandAbort, header: headerToSend)
    }
    
    public func ack(messageId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderId.rawValue] = messageId
        sendFrame(command: .commandAck, header: headerToSend)
    }
    
    public func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderId.rawValue] = messageId
        headerToSend[StompCommands.commandHeaderSubscription.rawValue] = subscription
        sendFrame(command: .commandAck, header: headerToSend)
    }
    
    // MARK: - Disconnect
    public func disconnect() {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandDisconnect.rawValue] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: .commandDisconnect, header: headerToSend)
        // Close the socket to allow recreation
        self.closeSocket()
    }
    
    // MARK: - Reconnect
    public func reconnect(time: Double = 1.0) {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: time, repeats: true) { _ in
            self.reconnectLogic()
        }
    }
    
    private func reconnectLogic() {
        if !self.connection {
            self.openSocket()
        }
    }
    
    public func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // Autodisconnect with a given time
    public func autoDisconnect(time: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            // Disconnect the socket
            self.disconnect()
        }
    }
}


// MARK: - SRWebSocketDelegate
extension ApeunStomp: SRWebSocketDelegate {
    public func webSocket(_ webSocket: SRWebSocket, didReceiveMessage message: Any) {
        var frame: Frame?
        if let strData = message as? NSData,
           let msg = String(data: strData as Data, encoding: String.Encoding.utf8) {
            frame = .from(message: msg)
        } else if let str = message as? String {
            frame = .from(message: str)
        }
        if let frame {
            receiveFrame(frame: frame)
        }
    }
    
    public func webSocketDidOpen(_ webSocket: SRWebSocket) {
        connect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        subject.send(.serverDidSendError(description: error.localizedDescription, message: nil))
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        subject.send(.stompClientDidDisconnect)
        connection = false
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceivePong pongPayload: Data?) {
        try? socket?.send(string: StompCommands.commandPing.rawValue)
        subject.send(.serverDidSendPing)
    }
}
