import ApeunStompKit
import Foundation
import SwiftUI
import Combine

private var subscriptions = Set<AnyCancellable>()

struct Res: Decodable {
    let id: String
    let chatRoomId: String
    let type: String
    let userId: Int
    let message: String?
    let emoticon: String?
    let eventList: [Int]?
}

struct Req: Encodable {
    let roomId: String = "6683baa5c10b712fbd2ed9d8" //보내는 방 주소
    let type: String =  "MESSAGE" // 형식 MESSAGE, IMG, FILE
    let message: String = "wow 성공" // 채팅
}

private let url = URL(string: "wss://hoolc.me/stomp/chat")!

private var header: [String: String] {
    [
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJpZCI6MTksImVtYWlsIjoiaGhoZWxsbzA1MDdAZ21haWwuY29tIiwicm9sZSI6IlJPTEVfVVNFUiIsImlhdCI6MTcyMDQwMTYyNiwiZXhwIjoxNzIwNDA3NjI2fQ.HuX6yDMOATeNnzgIgS1T0xNeytmufqT5R50SPq5qm_c",
        StompCommands.commandHeaderHeartBeat.rawValue: "0,10000"
    ]
}

let payloadObject: [String: Any] = [
    "roomId" : "6683baa5c10b712fbd2ed9d8", //보내는 방 주소
    "type" : "MESSAGE", // 형식 MESSAGE, IMG, FILE
    "message" : "ho", // 채팅
]
let s = ApeunStomp(request: .init(url: url), connectionHeaders: header)

let subUrl = "/exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8"

s.openSocket()

s.subConnect()
    .sink { _ in
        print("connected")
        s.sendJSONForDict(
            dict: Req(),
            to: "/pub/chat.message"
        )
        
        s.subBody(destination: subUrl, res: Res.self)
            .sink {
                switch $0 {
                case .finished:
                    break
                case .failure(let error):
                    print(error)
                }
            } receiveValue: {
                dump($0)
            }
            .store(in: &subscriptions)
        s.subPing()
            .sink { _ in
                print("💎 ping")
            }
            .store(in: &subscriptions)
    }
    .store(in: &subscriptions)
//
//s.subscribe { event in
//    switch event {
//    case .stompClient(let jsonBody, let stringBody, let header, let destination):
//        print("💎 didReceived")
//        print("\(jsonBody), \(stringBody), \(header), \(destination)")
//    case .stompClientDidDisconnect:
//        print("💎 didDisconnect")
//    case .stompClientDidConnect:
//        print("💎 didConnect")
//        s.subscribe(destination: subUrl) // MARK: - Sub
//        s.sendJSONForDict(
//            dict: Req(),
//            to: "/pub/chat.message"
//        )
//    case .serverDidSendReceipt(let receiptId):
//        print("💎 didSendReceipt - receiptId: \(receiptId)")
//    case .serverDidSendError(let description, let message):
//        print("💎 didSendError - description: \(description), message: \(message)")
//    case .serverDidSendPing:
//        print("💎 didSendPing")
//    }
//}

print("running...")

RunLoop.main.run()
/*
 "{
     "id":"668b20e8235cf34a020fc6d8",
     "chatRoomId":"6683baa5c10b712fbd2ed9d8",
     "type":"MESSAGE",
     "userId":19,
     "message":"asdasd 성공",
     "eventList":null,"emoticon":null,
     "emojiList":[],"mention":[],
     "mentionAll":false,
     "timestamp":"2024-07-07T23:12:40.411326096",
     "read":[19],
     "messageStatus":"ALIVE"
 }"
), Optional(["redelivered": "false", "content-encoding": "UTF-8", "content-type": "application/json", "content-length": "288", "__TypeId__": "com.seugi.api.domain.chat.domain.chat.model.Message", "message-id": "T_/exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8@@session-OB1xQ2Izce5uXFgLJmqYHw@@1", "priority": "0", "persistent": "true", "destination": "/exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8", "subscription": "/exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8"]), /exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8
*/
