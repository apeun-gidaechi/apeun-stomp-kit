
let a = ApeunStomp()

class ViewModel: ApeunStompDelegate {
    func stompClient(client: ApeunStomp!, didReceiveMessageWithJSONBody jsonBody: AnyObject?, akaStringBody stringBody: String?, withHeader header: [String : String]?, withDestination destination: String) {
        <#code#>
    }
    
    func stompClientDidDisconnect(client: ApeunStomp!) {
        <#code#>
    }
    
    func stompClientDidConnect(client: ApeunStomp!) {
        <#code#>
    }
    
    func serverDidSendReceipt(client: ApeunStomp!, withReceiptId receiptId: String) {
        <#code#>
    }
    
    func serverDidSendError(client: ApeunStomp!, withErrorMessage description: String, detailedErrorMessage message: String?) {
        <#code#>
    }
    
    func serverDidSendPing() {
        <#code#>
    }
    
    
}
