import SocketRocket
import Combine

//@objc
//public protocol ApeunStompDelegate {
//    func stompClient(client: ApeunStomp!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, akaStringBody stringBody: String?, withHeader header: ApeunStomp.StompHeaders?, withDestination destination: String)
//    
//    func stompClientDidDisconnect(client: ApeunStomp!)
//    func stompClientDidConnect(client: ApeunStomp!)
//    func serverDidSendReceipt(client: ApeunStomp!, withReceiptId receiptId: String)
//    func serverDidSendError(client: ApeunStomp!, withErrorMessage description: String, detailedErrorMessage message: String?)
//    func serverDidSendPing()
//}

public enum ApeunStompEvent {
    case stompClient(jsonBody: AnyObject?, stringBody: String?, header: ApeunStomp.StompHeaders?, destination: String)
    case stompClientDidDisconnect
    case stompClientDidConnect
    case serverDidSendReceipt(receiptId: String)
    case serverDidSendError(description: String, message: String?)
    case serverDidSendPing
}

@objcMembers
public class ApeunStomp: NSObject {
    
    public typealias StompHeaders = [String: String]
    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Parameters
    private var request: URLRequest
//    weak var delegate: ApeunStompDelegate?
    private var connectionHeaders: StompHeaders?
    
    var socket: SRWebSocket?
    var sessionId: String?
    
    private(set) var connection: Bool = false
    private var reconnectTimer : Timer?
    
    private let subject = PassthroughSubject<ApeunStompEvent, Never>()
    
    public init(
        request: URLRequest,
//        delegate: ApeunStompDelegate,
        connectionHeaders: StompHeaders? = nil
    ) {
        self.request = request
//        self.delegate = delegate
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
    
    private func closeSocket(){
//        guard let delegate else {
//            return
//        }
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
            connectionHeaders = [StompCommands.commandHeaderAcceptVersion:"1.1,1.2"]
        } else {
            connectionHeaders?[StompCommands.commandHeaderAcceptVersion] = "1.1,1.2"
        }
        // at the moment only anonymous logins
        self.sendFrame(command: StompCommands.commandConnect, header: connectionHeaders)
    }
    
    // MARK: - Send
    public func sendJSONForDict(dict: Encodable, to destination: String) {
        do {
            let json = try String(decoding: JSONEncoder().encode(dict), as: UTF8.self)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
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
            headers[StompCommands.commandHeaderReceipt] = receipt
        }
        
        // Setting up header destination.
        headers[StompCommands.commandHeaderDestination] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headers[StompCommands.commandHeaderContentLength] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headers[StompCommands.commandHeaderContentType] == nil {
            headers[StompCommands.commandHeaderContentType] = "text/plain"
        }
        sendFrame(
            body: message,
            command: StompCommands.commandSend,
            header: headers
        )
    }
    
    
    private func sendFrame(
        body: String? = nil,
        command: String?,
        header: StompHeaders?
    ) {
        guard socket?.readyState == .OPEN else {
            subject.send(.stompClientDidDisconnect)
            return
        }
        var frameString = ""
        if let command {
            frameString = "\(command)\n"
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
        
        frameString += StompCommands.controlChar
        
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
    private func receiveFrame(command: String, headers: StompHeaders, body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession] {
                sessionId = sessId
            }
            subject.send(.stompClientDidConnect)
        } else if command == StompCommands.responseFrameMessage {   // Message comes to this part
            // Response
            subject.send(.stompClient(jsonBody: self.dictForJSONString(jsonStr: body), stringBody: body, header: headers, destination: self.destinationFromHeader(header: headers)))
        } else if command == StompCommands.responseFrameReceipt {   //
            // Receipt
            if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                subject.send(.serverDidSendReceipt(receiptId: receiptId))
            }
        } else if command.count == 0 {
            // Pong from the server
            try? socket?.send(string: StompCommands.commandPing)
            subject.send(.serverDidSendPing)
        } else if command == StompCommands.responseFrameError {
            // Error
            if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                subject.send(.serverDidSendError(description: msg, message: body))
            }
        }
    }
    
    // MARK: - Subscribe
    public func subscribe(destination: String) {
        connection = true
        subscribeToDestination(destination: destination, ackMode: .AutoMode)
    }
    
    public func subscribeToDestination(destination: String, ackMode: StompAckMode) {
        var ack = ""
        switch ackMode {
        case StompAckMode.ClientMode:
            ack = StompCommands.ackClient
            break
        case StompAckMode.ClientIndividualMode:
            ack = StompCommands.ackClientIndividual
            break
        default:
            ack = StompCommands.ackAuto
            break
        }
        var headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: ""]
        if destination != "" {
            headers = [StompCommands.commandHeaderDestination: destination, StompCommands.commandHeaderAck: ack, StompCommands.commandHeaderDestinationId: destination]
        }
        self.sendFrame(body: nil, command: StompCommands.commandSubscribe, header: headers)
    }
    
    public func subscribeWithHeader(destination: String, withHeader header: StompHeaders) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        sendFrame(body: nil, command: StompCommands.commandSubscribe, header: headerToSend)
    }
    
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(body: nil, command: StompCommands.commandUnsubscribe, header: headerToSend)
    }
    
    public func begin(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandBegin, header: headerToSend)
    }
    
    public func commit(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandCommit, header: headerToSend)
    }
    
    public func abort(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandAbort, header: headerToSend)
    }
    
    public func ack(messageId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(command: StompCommands.commandAck, header: headerToSend)
    }
    
    public func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(command: StompCommands.commandAck, header: headerToSend)
    }
    
    // MARK: - Disconnect
    public func disconnect() {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandDisconnect] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: StompCommands.commandDisconnect, header: headerToSend)
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
    
    public func subscribe(_ subscriber: @escaping (ApeunStompEvent) -> Void) {
        subject
            .sink(receiveValue: subscriber)
            .store(in: &subscriptions)
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
            
            receiveFrame(command: command, headers: headers, body: body)
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
