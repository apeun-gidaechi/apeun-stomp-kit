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
                guard case .stompClient(let body, _, let d) = e,
                      d == destination,
                      let json = body?.data(using: .utf8) else {
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
}
