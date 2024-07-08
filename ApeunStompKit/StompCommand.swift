public enum StompCommands: String, RawRepresentable {

    // Basic Commands
    case commandConnect = "CONNECT"
    case commandSend = "SEND"
    case commandSubscribe = "SUBSCRIBE"
    case commandUnsubscribe = "UNSUBSCRIBE"
    case commandBegin = "BEGIN"
    case commandCommit = "COMMIT"
    case commandAbort = "ABORT"
    case commandAck = "ACK"
    case commandDisconnect = "DISCONNECT"
    case commandPing = "\n"
    
    case controlChar = ""
    
    // Ack Mode
    case ackClientIndividual = "client-individual"
    case ackClient = "client"
    case ackAuto = "auto"
    // Header Commands
    case commandHeaderReceipt = "receipt"
    case commandHeaderDestination = "destination"
    case commandHeaderId = "id"
    case commandHeaderContentLength = "content-length"
    case commandHeaderContentType = "content-type"
    case commandHeaderAck = "ack"
    case commandHeaderTransaction = "transaction"
    case commandHeaderSubscription = "subscription"
    case commandHeaderDisconnected = "disconnected"
    case commandHeaderHeartBeat = "heart-beat"
    case commandHeaderAcceptVersion = "accept-version"
    // Header Response Keys
    case responseHeaderSession = "session"
    case responseHeaderReceiptId = "receipt-id"
    case responseHeaderErrorMessage = "message"
    // Frame Response Keys
    case responseFrameConnected = "CONNECTED"
    case responseFrameMessage = "MESSAGE"
    case responseFrameReceipt = "RECEIPT"
    case responseFrameError = "ERROR"
}
