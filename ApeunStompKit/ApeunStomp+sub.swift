import Combine
import Foundation

public extension ApeunStomp {
    func subBody<D: Decodable>(
        destination: String,
        log: Bool = true,
        res: D.Type
    ) -> AnyPublisher<D, Never> {
        self.connection = true
        subscribeToDestination(destination: destination, ackMode: .AutoMode)
        return subject
            .compactMap { (e: ApeunStompEvent) -> D? in
                guard case .stompClient(let jsonBody, _, _, let d) = e,
                      d == destination,
                      let json = jsonBody.data(using: .utf8) else {
                    return nil
                }
                if log {
                    print(json.toPrettyPrintedString)
                }
                do {
                    let res = try self.jsonDecoder.decode(D.self, from: json)
                    print(res)
                    return res
                } catch {
                    print("ApeunStomp.subBody - descoding failure")
                    print(error)
                    return nil
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func subConnect() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .stompClientDidConnect = e else {
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
    func subPing() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendPing = e else {
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
    
    func subSendError() -> AnyPublisher<SendStompError, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendError(let description, let message) = e else {
                    return nil
                }
                return SendStompError(description: description, message: message)
            }
            .eraseToAnyPublisher()
    }
    
    func subDisconnect() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { e in
                guard case .stompClientDidDisconnect = e else {
                    return nil
                }
                return
            }
            .eraseToAnyPublisher()
    }
    
    func subSendReceipt() -> AnyPublisher<String, Never> {
        subject
            .compactMap { e in
                guard case .serverDidSendReceipt(let receiptId) = e else {
                    return nil
                }
                return receiptId
            }
            .eraseToAnyPublisher()
    }
}
