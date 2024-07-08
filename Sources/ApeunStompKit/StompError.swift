public enum StompError: Error, Equatable {
    case decodingFailure
    case connectFailure
    case unknown
}
