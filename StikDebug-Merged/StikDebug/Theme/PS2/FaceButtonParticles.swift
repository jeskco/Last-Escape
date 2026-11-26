//
//  FaceButtonParticles.swift
//  Floating PlayStation face-button symbols (cross, circle, triangle, square) drifting over the wallpaper,
//  like ARMSX2's "face buttons" particles.
//

import SwiftUI

struct FaceButtonParticles: View {
    private let count = 46

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let a = DynamicBackgroundMath.seededUnit(index: i, salt: 12.9898)
                    let b = DynamicBackgroundMath.seededUnit(index: i, salt: 78.233)
                    let c = DynamicBackgroundMath.seededUnit(index: i, salt: 37.719)
                    let speed = 0.012 + c * 0.03
                    // drift upward and wrap, with a gentle sideways sway
                    let y = (1.1 - ((b + t * speed).truncatingRemainder(dividingBy: 1.2))) * size.height
                    let x = (a + sin(t * 0.2 + c * 6.28) * 0.03) * size.width
                    let s = CGFloat(9 + c * 15)
                    let spin = t * (0.2 + a * 0.5) * (i.isMultiple(of: 2) ? 1 : -1) + b * 6.28
                    let twinkle = 0.5 + 0.5 * sin(t * (0.6 + b) + a * 9)
                    let alpha = 0.18 + 0.42 * twinkle

                    var layer = context
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(spin))
                    let r = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
                    let path: Path
                    switch i % 4 {
                    case 0:
                        var p = Path()
                        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                        p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                        path = p
                    case 1:
                        path = Path(ellipseIn: r)
                    case 2:
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: r.minY))
                        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                        p.closeSubpath()
                        path = p
                    default:
                        path = Path(roundedRect: r, cornerRadius: 1.5)
                    }
                    layer.stroke(path, with: .color(Color(red: 0.7, green: 0.88, blue: 1).opacity(alpha)),
                                 style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
