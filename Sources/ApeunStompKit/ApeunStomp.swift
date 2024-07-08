import SocketRocket
import Combine

public enum ApeunStompEvent {
    case stompClient(jsonBody: String, stringBody: String?, header: ApeunStomp.StompHeaders?, destination: String)
    case stompClientDidDisconnect
    case stompClientDidConnect
    case serverDidSendReceipt(receiptId: String)
    case serverDidSendError(description: String, message: String?)
    case serverDidSendPing
}

public class ApeunStomp: NSObject {
    
    public typealias StompHeaders = [String: String]
    // MARK: - Parameters
    private var request: URLRequest
    private var connectionHeaders: StompHeaders?
    
    var socket: SRWebSocket?
    var sessionId: String?
    
    private(set) var connection: Bool = false
    private var reconnectTimer : Timer?
    
    public let subject = PassthroughSubject<ApeunStompEvent, Never>()
    private let jsonDecoder = JSONDecoder()
    
    public init(
        request: URLRequest,
        connectionHeaders: StompHeaders? = nil
    ) {
        self.request = request
        self.connectionHeaders = connectionHeaders
    }
    
    // MARK: - Start / End
    
    public func openSocket() {
        self.connection = true
        if socket == nil || socket?.readyState == .CLOSED {
            socket = SRWebSocket(urlRequest: request)
            socket!.delegate = self
            socket!.open()
        }
    }
    
    private func closeSocket() {
        subject.send(.stompClientDidDisconnect)
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
            let header = [StompCommands.commandHeaderContentType.rawValue:"application/json;charset=UTF-8"]
            sendMessage(message: json, to: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
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
    
    private func dictForJSONString(jsonStr: String?) -> AnyObject? {
        guard let jsonStr else {
            return nil
        }
        do {
            if let data = jsonStr.data(using: String.Encoding.utf8) {
                let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                return json as AnyObject
            }
        } catch {
            print("error serializing JSON: \(error)")
        }
        return nil
    }
    
    // MARK: - Receive
    private func receiveFrame(command: StompCommands, headers: StompHeaders, body: String?) {
        if command == .responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession.rawValue] {
                sessionId = sessId
            }
            subject.send(.stompClientDidConnect)
        } else if command == .responseFrameMessage {   // Message comes to this part
            // Response
            subject.send(.stompClient(jsonBody:/* self.dictForJSONString(jsonStr: body)*/body ?? "", stringBody: body, header: headers, destination: self.destinationFromHeader(header: headers)))
        } else if command == .responseFrameReceipt {   //
            // Receipt
            if let receiptId = headers[StompCommands.responseHeaderReceiptId.rawValue] {
                subject.send(.serverDidSendReceipt(receiptId: receiptId))
            }
        } else if command.rawValue.count == 0 {
            // Pong from the server
            try? socket?.send(string: StompCommands.commandPing.rawValue)
            subject.send(.serverDidSendPing)
        } else if command == .responseFrameError {
            // Error
            if let msg = headers[StompCommands.responseHeaderErrorMessage.rawValue] {
                subject.send(.serverDidSendError(description: msg, message: body))
            }
        }
    }
    
    // MARK: - Subscribe
    public func subBody<D: Decodable>(
        destination: String,
        res: D.Type
    ) -> AnyPublisher<D, StompError> {
        connection = true
        subscribeToDestination(destination: destination, ackMode: .AutoMode)
        return subject
            .tryMap { (e: ApeunStompEvent) -> D in
                guard case .stompClient(let jsonBody, _, _, let d) = e,
                      d == destination,
                      let json = jsonBody.data(using: .utf8) else {
                    if case .serverDidSendError(let description, let message) = e {
                        print("\(description), \(message)")
                    }
                    throw StompError.unknown
                }
                do {
                    let res = try self.jsonDecoder.decode(D.self, from: json)
                    print(res)
                    return res
                } catch {
                    print(error)
                    throw StompError.decodingFailure
                }
            }
            .mapError { (error: Error) -> StompError in
                guard let error = error as? StompError else {
                    return StompError.unknown
                }
                return error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    public func subConnect() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .stompClientDidConnect = e else {
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
    public func subPing() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendPing = e else {
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
    public func subSendError() -> AnyPublisher<SendStompError, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendError(let description, let message) = e else {
                    return nil
                }
                return SendStompError(description: description, message: message)
            }
            .eraseToAnyPublisher()
    }
    
    public func subDisconnect() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .stompClientDidDisconnect = e else {
                    return nil
                }
                return
            }
            .eraseToAnyPublisher()
    }
    
    public func subSendReceipt() -> AnyPublisher<String, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendReceipt(let receiptId) = e else {
                    return nil
                }
                return receiptId
            }
            .eraseToAnyPublisher()
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
    
    // Reconnect after one sec or arg, if reconnect is available
    // TODO: MAKE A VARIABLE TO CHECK RECONNECT OPTION IS AVAILABLE OR NOT
//    public func reconnect(request: URLRequest, delegate: ApeunStompDelegate, connectionHeaders: StompHeaders = [:], time: Double = 1.0, exponentialBackoff: Bool = true){
//        reconnectTimer = Timer.scheduledTimer(withTimeInterval: time, repeats: true, block: { _ in
//            self.reconnectLogic(request: request, delegate: delegate
//                                , connectionHeaders: connectionHeaders)
//        })
//    }
    
//    private func reconnectLogic(request: URLRequest, delegate: ApeunStompDelegate, connectionHeaders: StompHeaders = [:]){
//        // Check if connection is alive or dead
//        if (!self.connection) {
//            if !connectionHeaders.isEmpty {
//                self.openSocket(request: request, delegate: delegate, connectionHeaders: connectionHeaders)
//            } else {
//                self.openSocket(request: request, delegate: delegate)
//            }
//        }
//    }
    
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
    private func processString(string: String) {
        var contents = string.components(separatedBy: "\n")
        if contents.first == "" {
            contents.removeFirst()
        }
        
        if let command = contents.first {
            var headers: StompHeaders = [:]
            var body = ""
            var hasHeaders  = false
            
            contents.removeFirst()
            for line in contents {
                if hasHeaders == true {
                    body += line
                } else {
                    if line == "" {
                        hasHeaders = true
                    } else {
                        let parts = line.components(separatedBy: ":")
                        if let key = parts.first {
                            headers[key] = parts.dropFirst().joined(separator: ":")
                        }
                    }
                }
            }
            
            // Remove the garbage from body
            if body.hasSuffix("\0") {
                body = body.replacingOccurrences(of: "\0", with: "")
            }
            
            receiveFrame(command: StompCommands(rawValue: command) ?? .ackAuto, headers: headers, body: body)
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceiveMessage message: Any) {
        if let strData = message as? NSData {
            if let msg = String(data: strData as Data, encoding: String.Encoding.utf8) {
                processString(string: msg)
            }
        } else if let str = message as? String {
            processString(string: str)
        }
    }
    
    public func webSocketDidOpen(_ webSocket: SRWebSocket) {
        //        print("WebSocket is connected")
        connect()
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        //        print("didFailWithError: \(String(describing: error))")
        subject.send(.serverDidSendError(description: error.localizedDescription, message: nil))
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        //        print("didCloseWithCode \(code), reason: \(String(describing: reason))")
        subject.send(.stompClientDidDisconnect)
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceivePong pongPayload: Data?) {
        //        print("didReceivePong")
    }
}
