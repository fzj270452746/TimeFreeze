import CoreGraphics
import Foundation

enum ScalarMath {
    static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }

    static func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * t
    }

    static func inverseLerp(_ start: CGFloat, _ end: CGFloat, _ value: CGFloat) -> CGFloat {
        guard start != end else { return 0 }
        return (value - start) / (end - start)
    }

    static func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = clamp(value, 0, 1)
        return t * t * (3 - 2 * t)
    }

    static func smootherStep(_ value: CGFloat) -> CGFloat {
        let t = clamp(value, 0, 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    static func pingPong(_ time: CGFloat, length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let wrapped = time.truncatingRemainder(dividingBy: length * 2)
        return length - abs(wrapped - length)
    }

    static func wrapAngle(_ radians: CGFloat) -> CGFloat {
        var value = radians.truncatingRemainder(dividingBy: .pi * 2)
        if value > .pi { value -= .pi * 2 }
        if value < -.pi { value += .pi * 2 }
        return value
    }

    static func shortestAngle(from start: CGFloat, to end: CGFloat) -> CGFloat {
        wrapAngle(end - start)
    }

    static func ease(_ curve: MotionCurve, _ value: CGFloat) -> CGFloat {
        let t = clamp(value, 0, 1)
        switch curve {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - pow(1 - t, 2)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .sine:
            return -(cos(.pi * t) - 1) / 2
        case .bounce:
            let n: CGFloat = 7.5625
            let d: CGFloat = 2.75
            if t < 1 / d { return n * t * t }
            if t < 2 / d {
                let p = t - 1.5 / d
                return n * p * p + 0.75
            }
            if t < 2.5 / d {
                let p = t - 2.25 / d
                return n * p * p + 0.9375
            }
            let p = t - 2.625 / d
            return n * p * p + 0.984375
        case .elastic:
            guard t != 0, t != 1 else { return t }
            return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * .pi / 3)) + 1
        }
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    var length: CGFloat { hypot(x, y) }
    var lengthSquared: CGFloat { x * x + y * y }
    var normalized: CGPoint { length > 0.0001 ? self / length : .zero }
    var angle: CGFloat { atan2(y, x) }

    func distance(to other: CGPoint) -> CGFloat {
        (self - other).length
    }

    func dot(_ other: CGPoint) -> CGFloat {
        x * other.x + y * other.y
    }

    func rotated(by radians: CGFloat) -> CGPoint {
        CGPoint(
            x: x * cos(radians) - y * sin(radians),
            y: x * sin(radians) + y * cos(radians)
        )
    }

    func lerped(to other: CGPoint, t: CGFloat) -> CGPoint {
        self + (other - self) * t
    }
}

struct SeededRandom: RandomNumberGenerator, Codable {
    private(set) var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func float(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(Double(next()) / Double(UInt64.max))
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func bool(chance: CGFloat = 0.5) -> Bool {
        float(in: 0...1) < chance
    }

    mutating func choose<T>(_ values: [T]) -> T {
        values[int(in: 0...(values.count - 1))]
    }

    mutating func shuffled<T>(_ values: [T]) -> [T] {
        var copy = values
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, through: 1, by: -1) {
            copy.swapAt(index, int(in: 0...index))
        }
        return copy
    }
}
