import Foundation

struct CommentaryDeliveryPolicy {
    enum Decision {
        case emit
        case cooldown
        case limitReached
    }

    static let maximumPerTurn = 3
    static let minimumInterval: TimeInterval = 12

    private var emittedCount = 0
    private var lastEmissionAt: Date?

    mutating func reset() {
        emittedCount = 0
        lastEmissionAt = nil
    }

    mutating func decision(at date: Date = Date()) -> Decision {
        guard emittedCount < Self.maximumPerTurn else { return .limitReached }
        if let lastEmissionAt, date.timeIntervalSince(lastEmissionAt) < Self.minimumInterval {
            return .cooldown
        }
        emittedCount += 1
        lastEmissionAt = date
        return .emit
    }
}
