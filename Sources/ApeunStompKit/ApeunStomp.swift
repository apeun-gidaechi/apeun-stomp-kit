import SocketRocket

@objc
public protocol ApeunStompDelegate {
    func stompClient(client: ApeunStomp!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, akaStringBody stringBody: String?, withHeader header: ApeunStomp.StompHeaders?, withDestination destination: String)
    
    func stompClientDidDisconnect(client: ApeunStomp!)
    func stompClientDidConnect(client: ApeunStomp!)
    func serverDidSendReceipt(client: ApeunStomp!, withReceiptId receiptId: String)
    func serverDidSendError(client: ApeunStomp!, withErrorMessage description: String, detailedErrorMessage message: String?)
    func serverDidSendPing()
}

@objcMembers
public class ApeunStomp: NSObject {
    
    public typealias StompHeaders = [String: String]
    
    var socket: SRWebSocket?
    var sessionId: String?
    weak var delegate: ApeunStompDelegate?
    private var connectionHeaders: StompHeaders?
    private(set) var connection: Bool = false
    private var urlRequest: URLRequest?
    private var reconnectTimer : Timer?
    
    // MARK: - Start / End
    public func openSocketWithURLRequest(request: URLRequest, delegate: ApeunStompDelegate, connectionHeaders: StompHeaders? = nil) {
        self.connectionHeaders = connectionHeaders
        self.delegate = delegate
        self.urlRequest = request
        
        // Opening the socket
        openSocket()
        self.connection = true
    }
    
    private func openSocket() {
        if socket == nil || socket?.readyState == .CLOSED {
            socket = SRWebSocket(urlRequest: urlRequest!)
            socket!.delegate = self
            socket!.open()
        }
    }
    
    private func closeSocket(){
        guard let delegate else {
            return
        }
        DispatchQueue.main.async(execute: {
            delegate.stompClientDidDisconnect(client: self)
            if self.socket != nil {
                // Close the socket
                self.socket!.close()
                self.socket!.delegate = nil
                self.socket = nil
            }
        })
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
        self.sendFrame(command: StompCommands.commandConnect, header: connectionHeaders, body: nil)
    }
    
    // MARK: - Send
    public func sendJSONForDict(dict: AnyObject, toDestination destination: String) {
        do {
            let theJSONData = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions())
            let theJSONText = String(data: theJSONData, encoding: String.Encoding.utf8)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(message: theJSONText!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
        }
    }
    
    public func sendMessage(message: String, toDestination destination: String, withHeaders headers: StompHeaders?, withReceipt receipt: String?) {
        var headersToSend: StompHeaders = [:]
        if let headers = headers {
            headersToSend = headers
        }
        
        // Setting up the receipt.
        if let receipt = receipt {
            headersToSend[StompCommands.commandHeaderReceipt] = receipt
        }
        
        headersToSend[StompCommands.commandHeaderDestination] = destination
        
        // Setting up the content length.
        let contentLength = message.utf8.count
        headersToSend[StompCommands.commandHeaderContentLength] = "\(contentLength)"
        
        // Setting up content type as plain text.
        if headersToSend[StompCommands.commandHeaderContentType] == nil {
            headersToSend[StompCommands.commandHeaderContentType] = "text/plain"
        }
        sendFrame(command: StompCommands.commandSend, header: headersToSend, body: message as AnyObject)
    }
    
    
    private func sendFrame(command: String?, header: StompHeaders?, body: AnyObject?) {
        guard socket?.readyState == .OPEN else {
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClientDidDisconnect(client: self)
                })
            }
            return
        }
        var frameString = ""
        if command != nil {
            frameString = command! + "\n"
        }
        
        if let header = header {
            for (key, value) in header {
                frameString += key
                frameString += ":"
                frameString += value
                frameString += "\n"
            }
        }
        
        if let body = body as? String {
            frameString += "\n"
            frameString += body
        } else if let _ = body as? NSData {
            
        }
        
        if body == nil {
            frameString += "\n"
        }
        
        frameString += StompCommands.controlChar
        
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
            
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClientDidConnect(client: self)
                })
            }
        } else if command == StompCommands.responseFrameMessage {   // Message comes to this part
            // Response
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.stompClient(client: self, didReceiveMessageWithJSONBody: self.dictForJSONString(jsonStr: body), akaStringBody: body, withHeader: headers, withDestination: self.destinationFromHeader(header: headers))
                })
            }
        } else if command == StompCommands.responseFrameReceipt {   //
            // Receipt
            if let delegate = delegate {
                if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendReceipt(client: self, withReceiptId: receiptId)
                    })
                }
            }
        } else if command.count == 0 {
            // Pong from the server
            try? socket?.send(string: StompCommands.commandPing)
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.serverDidSendPing()
                })
            }
        } else if command == StompCommands.responseFrameError {
            // Error
            if let delegate = delegate {
                if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendError(client: self, withErrorMessage: msg, detailedErrorMessage: body)
                    })
                }
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
        self.sendFrame(command: StompCommands.commandSubscribe, header: headers, body: nil)
    }
    
    public func subscribeWithHeader(destination: String, withHeader header: StompHeaders) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        sendFrame(command: StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }
    
    /*
     Main Unsubscribe Method with topic name
     */
    public func unsubscribe(destination: String) {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(command: StompCommands.commandUnsubscribe, header: headerToSend, body: nil)
    }
    
    public func begin(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandBegin, header: headerToSend, body: nil)
    }
    
    public func commit(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandCommit, header: headerToSend, body: nil)
    }
    
    public func abort(transactionId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandAbort, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    public func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }
    
    // MARK: - Disconnect
    public func disconnect() {
        connection = false
        var headerToSend: StompHeaders = [:]
        headerToSend[StompCommands.commandDisconnect] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: StompCommands.commandDisconnect, header: headerToSend, body: nil)
        // Close the socket to allow recreation
        self.closeSocket()
    }
    
    // Reconnect after one sec or arg, if reconnect is available
    // TODO: MAKE A VARIABLE TO CHECK RECONNECT OPTION IS AVAILABLE OR NOT
    public func reconnect(request: URLRequest, delegate: ApeunStompDelegate, connectionHeaders: StompHeaders = [:], time: Double = 1.0, exponentialBackoff: Bool = true){
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: time, repeats: true, block: { _ in
            self.reconnectLogic(request: request, delegate: delegate
                                , connectionHeaders: connectionHeaders)
        })
    }
    
    private func reconnectLogic(request: URLRequest, delegate: ApeunStompDelegate, connectionHeaders: StompHeaders = [:]){
        // Check if connection is alive or dead
        if (!self.connection){
            self.checkConnectionHeader(connectionHeaders: connectionHeaders) ? self.openSocketWithURLRequest(request: request, delegate: delegate, connectionHeaders: connectionHeaders) : self.openSocketWithURLRequest(request: request, delegate: delegate)
        }
    }
    
    public func stopReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func checkConnectionHeader(connectionHeaders: StompHeaders = [:]) -> Bool{
        if (connectionHeaders.isEmpty){
            // No connection header
            return false
        } else {
            // There is a connection header
            return true
        }
    }
    
    // Autodisconnect with a given time
    public func autoDisconnect(time: Double){
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
        if let delegate = delegate {
            DispatchQueue.main.async {
                delegate.serverDidSendError(client: self, withErrorMessage: error.localizedDescription, detailedErrorMessage: nil)
            }
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
//        print("didCloseWithCode \(code), reason: \(String(describing: reason))")
        if let delegate = delegate {
            DispatchQueue.main.async {
                delegate.stompClientDidDisconnect(client: self)
            }
        }
    }
    
    public func webSocket(_ webSocket: SRWebSocket, didReceivePong pongPayload: Data?) {
//        print("didReceivePong")
    }
}
