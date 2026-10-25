import SwiftUI

// MARK: - Mood

/// Shifts the aurora's palette with what Familiar is doing. Decorative: the mood is always mirrored by text.
enum AuroraMood: Equatable {
    /// Blue → orange → purple → sky, the wallet reference.
    case calm
    /// Cooler, more sky and blue: Familiar is listening.
    case listening
    /// Warmer, orange and peach forward: a known person is near.
    case cue
    /// Silver-lilac, desaturated and still: awareness paused.
    case paused
}

// MARK: - Background

/// The shifting hero gradient: a 3×3 `MeshGradient` whose inner points drift and whose stops slide between two
/// arrangements of blue #2779E7, orange #F5A66B, purple #A08EF4 and sky #79C9F7 over a slow 9 s cycle (and 11, 13
/// and 17 s harmonics so the loop never visibly repeats). Still under `simplifyMotion`, Reduce Motion and the
/// `.paused` mood; the clock also stops while the scene is not active. Quieter in high contrast, under Reduce
/// Transparency and in dark mode. Sits behind Mimo or a hero headline, never behind body text.
struct AuroraBackground: View {
    var intensity: Double = 1
    var mood: AuroraMood = .calm
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// A deterministic frame (t = 0) instead of drift.
    private var frozen: Bool { reduceMotion || scale.simplifyMotion || mood == .paused }

    /// The timeline stops ticking: frozen, or the app is not in the foreground.
    private var paused: Bool { frozen || scenePhase != .active }

    private var strength: Double {
        var value = intensity
        if scale.highContrast || reduceTransparency { value *= 0.55 }
        if colorScheme == .dark { value *= 0.7 }
        return value
    }

    var body: some View {
        AuroraMeshLayer(palette: AuroraPalette.make(mood), frozen: frozen, paused: paused)
            .saturation(mood == .paused ? 0.3 : 1)
            .opacity(strength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Layers

/// Drives the mesh from one 30 fps clock.
private struct AuroraMeshLayer: View {
    let palette: AuroraPalette
    let frozen: Bool
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t: Double = frozen ? 0 : context.date.timeIntervalSinceReferenceDate
            AuroraMesh(points: AuroraMath.points(at: t), colors: palette.colors(at: t))
        }
        .clipped()
    }
}

/// The mesh itself. `smoothsColors` and the perceptual colour space already give soft transitions; a light blur
/// only hides the seams near the control points, and the slight overscale hides the blurred edge.
private struct AuroraMesh: View {
    let points: [SIMD2<Float>]
    let colors: [Color]

    var body: some View {
        MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true, colorSpace: .perceptual)
            .blur(radius: 6)
            .scaleEffect(1.08)
    }
}

// MARK: - Palette

/// Two arrangements of the four aurora stops per mood; the mesh slides between them over time.
struct AuroraPalette: Equatable {
    let from: [Color]
    let to: [Color]

    private static let blue = FamiliarPalette.auroraBlue
    private static let orange = FamiliarPalette.auroraOrange
    private static let purple = FamiliarPalette.auroraPurple
    private static let sky = FamiliarPalette.auroraSky
    private static let peach = Color(familiarHex: "#F7C4A0")
    private static let silver = Color(familiarHex: "#CBCFDA")
    private static let silverLilac = Color(familiarHex: "#D9D4EA")
    private static let mist = Color(familiarHex: "#E6E9F0")

    static func make(_ mood: AuroraMood) -> AuroraPalette {
        switch mood {
        case .calm:
            return AuroraPalette(
                from: [blue, sky, purple,
                       purple, orange, blue,
                       orange, purple, sky],
                to: [sky, purple, blue,
                     blue, purple, orange,
                     purple, sky, orange])
        case .listening:
            return AuroraPalette(
                from: [blue, sky, blue,
                       sky, purple, sky,
                       blue, sky, purple],
                to: [sky, blue, sky,
                     purple, sky, blue,
                     sky, purple, blue])
        case .cue:
            return AuroraPalette(
                from: [orange, peach, sky,
                       sky, orange, purple,
                       peach, sky, orange],
                to: [peach, orange, purple,
                     orange, peach, sky,
                     sky, orange, peach])
        case .paused:
            return AuroraPalette(
                from: [silver, mist, silverLilac,
                       silverLilac, silver, mist,
                       mist, silverLilac, silver],
                to: [mist, silverLilac, silver,
                     silver, mist, silverLilac,
                     silverLilac, silver, mist])
        }
    }

    /// Nine mesh colours at time `t`: `from` blended toward `to` by a slow cosine.
    func colors(at t: Double) -> [Color] {
        let k: Double = AuroraMath.blend(at: t)
        var result: [Color] = []
        result.reserveCapacity(from.count)
        for index in 0..<min(from.count, to.count) {
            result.append(from[index].mix(with: to[index], by: k, in: .perceptual))
        }
        return result
    }
}

// MARK: - Math

/// One clock for every aurora: a 9 s base period with 11, 13 and 17 s harmonics so points and colours never line up.
enum AuroraMath {
    static let period: Double = 9

    private static func wave(_ t: Double, period p: Double, phase: Double, amplitude: Double) -> Double {
        amplitude * sin(2 * Double.pi * t / p + phase)
    }

    /// 0…1, how far the palette has slid from `from` toward `to`.
    static func blend(at t: Double) -> Double {
        (1 - cos(2 * Double.pi * t / (period * 2))) / 2
    }

    /// 3×3 control points, row-major. Corners stay put, edge midpoints slide along their edge, the centre wanders.
    static func points(at t: Double) -> [SIMD2<Float>] {
        let top = Float(0.5 + wave(t, period: period, phase: 0.0, amplitude: 0.09))
        let left = Float(0.5 + wave(t, period: 13, phase: 1.3, amplitude: 0.09))
        let right = Float(0.5 + wave(t, period: 17, phase: 2.6, amplitude: 0.09))
        let bottom = Float(0.5 + wave(t, period: 11, phase: 3.9, amplitude: 0.09))
        let centerX = Float(0.5 + wave(t, period: period, phase: 0.4, amplitude: 0.16))
        let centerY = Float(0.5 + wave(t, period: 13, phase: 2.1, amplitude: 0.16))
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(top, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, left), SIMD2<Float>(centerX, centerY), SIMD2<Float>(1, right),
            SIMD2<Float>(0, 1), SIMD2<Float>(bottom, 1), SIMD2<Float>(1, 1)
        ]
    }
}

// MARK: - Preview

private struct AuroraMoodPreview: View {
    let mood: AuroraMood
    let title: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AuroraBackground(intensity: 1, mood: mood)
            Text(title)
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink)
                .padding(16)
                .background(FamiliarPalette.surface, in: Capsule())
                .padding(16)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.heroRadius, style: .continuous))
    }
}

#Preview("Aurora moods") {
    ScrollView {
        VStack(spacing: 16) {
            AuroraMoodPreview(mood: .calm, title: "Calm")
            AuroraMoodPreview(mood: .listening, title: "Listening")
            AuroraMoodPreview(mood: .cue, title: "Cue")
            AuroraMoodPreview(mood: .paused, title: "Paused")
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}

#Preview("Aurora · frozen (severe)") {
    AuroraMoodPreview(mood: .calm, title: "Frozen")
        .visionScale(VisionScale.make(.severe))
        .padding(FamiliarPalette.margin)
        .familiarCanvas()
}
