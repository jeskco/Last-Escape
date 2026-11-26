//
//  PS2Shims.swift
//  Small stand-ins for the ARMSX2 services that PlayStation2MenuBackground.swift expects
//  (theme palette, frame-rate settings, canvas wrapper). The wallpaper code itself is ARMSX2's, unchanged.
//

import SwiftUI

// MARK: - Settings

struct PS2BackgroundSettings {
    var playStation2MenuSceneSpeed = 1.0
    var playStation2MenuFramesPerSecond = 15.0
    var playStation2MenuYawSpeed = 2.0
    var playStation2MenuRollSpeed = 6.0
    var playStation2MenuOrbitDegrees = 25.0
    var playStation2MenuColorsTowers = false
}

struct PS2ParticleSettings {
    var backgrounds = PS2BackgroundSettings()
}

/// Fixed "blue" palette in the style of ARMSX2's default PlayStation 2 menu theme.
struct DynamicBackgroundTheme {
    var particleSettings = PS2ParticleSettings()
    var sharedPaletteGradientCurvature: Double { 0 }

    static let blue = DynamicBackgroundTheme()

    func sharedColor(index: Int, time: TimeInterval) -> Color {
        let palette: [Color] = [
            Color(red: 0.020, green: 0.075, blue: 0.340),
            Color(red: 0.120, green: 0.380, blue: 0.960),
            Color(red: 0.300, green: 0.600, blue: 1.000),
        ]
        return palette[abs(index) % palette.count]
    }

    func ribbonColor(index: Int, time: TimeInterval) -> Color {
        let palette: [Color] = [
            Color(red: 0.55, green: 0.82, blue: 1.00),
            Color(red: 0.35, green: 0.65, blue: 1.00),
            Color(red: 0.75, green: 0.92, blue: 1.00),
        ]
        return palette[abs(index) % palette.count]
    }

    func sharedGradientPoints(from start: UnitPoint, to end: UnitPoint) -> (start: UnitPoint, end: UnitPoint) {
        (start, end)
    }

    func paletteBackgroundColor(_ color: Color, darkness: Double) -> Color { color }

    func paletteDarkOverlay(opacity: Double) -> Color { Color.black.opacity(opacity * 0.55) }
}

// MARK: - Frame-rate configuration

enum UIFrameRateDomain { case dynamicBackground }

struct UIFrameRateConfiguration: Sendable {
    var dynamicGeometryDetailScale = 0.8
    var dynamicWallpaperRenderScale = 0.75

    func scaledDynamicGeometryCount(_ count: Double, minimum: Int = 1) -> Int {
        let scaled = (count * dynamicGeometryDetailScale).rounded()
        return max(minimum, Int(DynamicBackgroundMath.clamp(scaled, to: 0...256)))
    }

    func reducedDynamicGeometry<Element>(_ elements: [Element], minimum: Int = 1) -> [Element] {
        guard !elements.isEmpty else { return [] }
        let target = min(elements.count, scaledDynamicGeometryCount(Double(elements.count), minimum: minimum))
        guard target < elements.count else { return elements }
        guard target > 1 else { return [elements[elements.count / 2]] }
        return (0..<target).map { index in
            let progress = Double(index) / Double(target - 1)
            return elements[Int((progress * Double(elements.count - 1)).rounded())]
        }
    }
}

private struct UIFrameRateKey: EnvironmentKey {
    static let defaultValue = UIFrameRateConfiguration()
}

private struct MenuSessionStartKey: EnvironmentKey {
    static let defaultValue = Date()
}

extension EnvironmentValues {
    var uiFrameRateConfiguration: UIFrameRateConfiguration {
        get { self[UIFrameRateKey.self] }
        set { self[UIFrameRateKey.self] = newValue }
    }
    var menuBackgroundSessionStart: Date {
        get { self[MenuSessionStartKey.self] }
        set { self[MenuSessionStartKey.self] = newValue }
    }
}

// MARK: - View helpers

struct AdaptiveAnimationTimelineContext { let date: Date }

struct AdaptiveAnimationTimeline<Content: View>: View {
    let domain: UIFrameRateDomain
    var maximumFramesPerSecond: Double?
    @ViewBuilder let content: (AdaptiveAnimationTimelineContext) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / max(1, maximumFramesPerSecond ?? 30))) { timeline in
            content(AdaptiveAnimationTimelineContext(date: timeline.date))
        }
    }
}

struct PaletteGradientField: View {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    let curvature: Double

    var body: some View {
        LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
}

/// Canvas whose logical size stays screen-sized while it rasterises at a reduced scale (cheaper, and the scene is soft anyway).
struct DynamicWallpaperCanvas: View {
    var opaque = false
    var colorMode: ColorRenderingMode = .nonLinear
    var rendersAsynchronously = true
    let renderer: (inout GraphicsContext, CGSize) -> Void

    @Environment(\.uiFrameRateConfiguration) private var frameRates

    var body: some View {
        GeometryReader { geometry in
            let scale = CGFloat(frameRates.dynamicWallpaperRenderScale)
            let full = CGSize(width: max(1, geometry.size.width), height: max(1, geometry.size.height))
            let raster = CGSize(width: max(1, (full.width * scale).rounded(.up)),
                                height: max(1, (full.height * scale).rounded(.up)))
            Canvas(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously) { context, _ in
                context.scaleBy(x: scale, y: scale)
                renderer(&context, full)
            }
            .frame(width: raster.width, height: raster.height)
            .scaleEffect(1 / scale, anchor: .topLeading)
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
    }
}
