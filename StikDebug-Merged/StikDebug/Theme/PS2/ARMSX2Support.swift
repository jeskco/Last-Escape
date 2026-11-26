// Pieces of ARMSX2 (GPL-3.0+) DynamicEffects.swift copied verbatim: OrbTrailGeometry and DynamicBackgroundMath.
import SwiftUI

struct OrbTrailBezierSegment {
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
}

enum OrbTrailGeometry {
    static func segment(
        points: [CGPoint],
        index: Int,
        maximumTangentLength: CGFloat
    ) -> OrbTrailBezierSegment {
        let start = points[index]
        let end = points[index + 1]
        let startTangent = tangent(
            points: points,
            index: index,
            maximumLength: maximumTangentLength
        )
        let endTangent = tangent(
            points: points,
            index: index + 1,
            maximumLength: maximumTangentLength
        )

        return OrbTrailBezierSegment(
            end: end,
            control1: CGPoint(
                x: start.x + startTangent.dx / 3,
                y: start.y + startTangent.dy / 3
            ),
            control2: CGPoint(
                x: end.x - endTangent.dx / 3,
                y: end.y - endTangent.dy / 3
            )
        )
    }

    private static func tangent(
        points: [CGPoint],
        index: Int,
        maximumLength: CGFloat
    ) -> CGVector {
        let point = points[index]
        let previous = points[max(0, index - 1)]
        let following = points[min(points.count - 1, index + 1)]
        let raw = CGVector(
            dx: (following.x - previous.x) * 0.5,
            dy: (following.y - previous.y) * 0.5
        )
        let rawLength = hypot(raw.dx, raw.dy)
        guard rawLength > 0 else { return .zero }

        let adjacentLengths = [
            hypot(point.x - previous.x, point.y - previous.y),
            hypot(following.x - point.x, following.y - point.y),
        ].filter { $0 > 0 }
        guard let shortestAdjacent = adjacentLengths.min() else { return .zero }

        let allowedLength = min(maximumLength, shortestAdjacent * 1.25)
        let scale = min(1, allowedLength / rawLength)
        return CGVector(dx: raw.dx * scale, dy: raw.dy * scale)
    }
}

enum DynamicBackgroundMath {
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func unit(_ value: Double) -> Double {
        value - floor(value)
    }

    static func seededUnit(index: Int, salt: Double) -> Double {
        unit(sin((Double(index) + 1) * salt) * 43_758.5453)
    }

    static func smoothstep(
        from lowerBound: Double = 0,
        to upperBound: Double = 1,
        value: Double
    ) -> Double {
        let progress = clamp(
            (value - lowerBound) / (upperBound - lowerBound),
            to: 0...1
        )
        return progress * progress * (3 - 2 * progress)
    }
}
