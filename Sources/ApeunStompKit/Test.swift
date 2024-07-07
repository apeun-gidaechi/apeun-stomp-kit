import Foundation


class ViewModel {

    let a = ApeunStomp(request: .init(url: URL(string:"Hell")!))
    
//    func sub() {
//        a.subscribe { event in
//            switch event {
//            case .stompClient(let jsonBody, let stringBody, let header, let destination):
//                <#code#>
//            case .stompClientDidDisconnect:
//                <#code#>
//            case .stompClientDidConnect:
//                <#code#>
//            case .serverDidSendReceipt(let receiptId):
//                <#code#>
//            case .serverDidSendError(let description, let message):
//                <#code#>
//            case .serverDidSendPing:
//                <#code#>
//            }
//        }
//    }
}
