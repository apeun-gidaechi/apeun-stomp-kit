
let a = StompClientLib()

class ViewModel: StompClientLibDelegate {
    func stompClient(client: StompClientLib!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, akaStringBody stringBody: String?, withHeader header: [String : String]?, withDestination destination: String) {
        <#code#>
    }
    
    func stompClientDidDisconnect(client: StompClientLib!) {
        <#code#>
    }
    
    func stompClientDidConnect(client: StompClientLib!) {
        <#code#>
    }
    
    func serverDidSendReceipt(client: StompClientLib!, withReceiptId receiptId: String) {
        <#code#>
    }
    
    func serverDidSendError(client: StompClientLib!, withErrorMessage description: String, detailedErrorMessage message: String?) {
        <#code#>
    }
    
    func serverDidSendPing() {
        <#code#>
    }
    
    
}
