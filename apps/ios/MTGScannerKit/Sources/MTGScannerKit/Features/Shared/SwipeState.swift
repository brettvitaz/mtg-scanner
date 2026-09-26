import CoreGraphics

enum SwipeDirection: Equatable {
    case none
    case leading
    case trailing
}

enum SwipeOutcome: Equatable {
    case close
    case open(SwipeDirection)
    case commit(SwipeDirection)
}

enum SwipeState {
    static let openDistance: CGFloat = 80
    static let commitRatio: CGFloat = 0.55
    static let flingVelocity: CGFloat = 1200

    static func direction(for offset: CGFloat) -> SwipeDirection {
        if offset > 0.5 { return .leading }
        if offset < -0.5 { return .trailing }
        return .none
    }

    static func commitThreshold(rowWidth: CGFloat) -> CGFloat {
        max(rowWidth * commitRatio, openDistance + 1)
    }

    static func hasCrossedCommit(offset: CGFloat, rowWidth: CGFloat) -> Bool {
        abs(offset) >= commitThreshold(rowWidth: rowWidth)
    }

    static func resolve(offset: CGFloat, rowWidth: CGFloat, velocity: CGFloat) -> SwipeOutcome {
        let traveled = abs(offset)
        guard traveled > 0 else { return .close }
        let direction: SwipeDirection = offset > 0 ? .leading : .trailing
        let sameDirectionFling = (velocity > 0 && offset > 0) || (velocity < 0 && offset < 0)
        let flingCommits = sameDirectionFling && abs(velocity) > flingVelocity && traveled > openDistance
        if traveled >= commitThreshold(rowWidth: rowWidth) || flingCommits {
            return .commit(direction)
        }
        if traveled >= openDistance {
            return .open(direction)
        }
        return .close
    }
}
