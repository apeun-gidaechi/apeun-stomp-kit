import ApeunStompKit
import Foundation
import SwiftUI

struct Req: Encodable {
    let roomId: String = "6683baa5c10b712fbd2ed9d8" //보내는 방 주소
    let type: String =  "MESSAGE" // 형식 MESSAGE, IMG, FILE
    let message: String = "asdasd 성공" // 채팅
}

private let url = URL(string: "wss://hoolc.me/stomp/chat")!

private var header: [String: String] {
    [
        "Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJpZCI6MywiZW1haWwiOiJ0ZXN0QHRlc3QiLCJyb2xlIjoiUk9MRV9VU0VSIiwiaWF0IjoxNzIwMzU2NTUxLCJleHAiOjE3MjAzNjI1NTF9.jgLIplC6AGWvcAnwUb0mpl57fQjYXbWT5HRfNNrvLKg",
        StompCommands.commandHeaderHeartBeat.rawValue: "0,10000"
    ]
}

let payloadObject: [String: Any] = [
    "roomId" : "6683baa5c10b712fbd2ed9d8", //보내는 방 주소
    "type" : "MESSAGE", // 형식 MESSAGE, IMG, FILE
    "message" : "ho", // 채팅
]
let s = ApeunStomp(request: .init(url: url), connectionHeaders: header)

s.openSocket()

s.subscribe { event in
    switch event {
    case .stompClient(let jsonBody, let stringBody, let header, let destination):
        print("💎 didReceived")
        print("\(jsonBody), \(stringBody), \(header), \(destination)")
    case .stompClientDidDisconnect:
        print("💎 didDisconnect")
    case .stompClientDidConnect:
        print("💎 didConnect")
        s.subscribe(destination: "/exchange/chat.exchange/room.6683baa5c10b712fbd2ed9d8")
        s.sendJSONForDict(
            dict: Req(),
            to: "/pub/chat.message"
        )
    case .serverDidSendReceipt(let receiptId):
        print("💎 didSendReceipt - receiptId: \(receiptId)")
    case .serverDidSendError(let description, let message):
        print("💎 didSendError - description: \(description), message: \(message)")
    case .serverDidSendPing:
        print("💎 didSendPing")
    }
}

print("running...")

RunLoop.main.run()
