struct Frame {
    let command: StompCommands
    let headers: StompHeaders
    let body: String?
    
    static func from(message: String) -> Frame? {
        var contents = message.components(separatedBy: "\n")
        if contents.first == "" {
            contents.removeFirst()
        }
        
        guard let command = contents.first else {
            return nil
        }
        
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
        
        return Frame(
            command: StompCommands(rawValue: command) ?? .ackAuto,
            headers: headers,
            body: body
        )
    }
}
