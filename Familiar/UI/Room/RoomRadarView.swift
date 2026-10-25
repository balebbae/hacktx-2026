import SwiftUI

/// The room as a half-disc: you stand at the bottom centre, ahead is up. Five bearing sectors (far left · left · ahead
/// · right · far right) and three distance rings (close · medium · far) hold the people in view. Known people are
/// filled mint dots with a name; everyone else is a hollow ink dot with no label, because strangers are "a person".
/// VoiceOver gets one element whose label is the roll-call sentence, so the map says exactly what Familiar would say.
struct RoomRadarView: View {
    let tracks: [TrackSnapshot]
    var horizontalFOV: Double = 53

    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 12) {
            Canvas { context, size in
                let painter = RadarPainter(tracks: tracks, horizontalFOV: horizontalFOV, scale: scale)
                painter.draw(in: &context, size: size)
            }
            .aspectRatio(1.7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            RadarLegend()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RollCall.phrase(tracks: tracks))
        .accessibilityHint("Map of the room. Ahead is at the top; you are at the bottom edge.")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Pure geometry and drawing for the radar. Deterministic: same tracks, same picture. Every colour goes through the
/// scale-aware palette helpers so the severe profile gets the high-contrast ink.
struct RadarPainter {
    let tracks: [TrackSnapshot]
    let horizontalFOV: Double
    let scale: VisionScale

    private var hairline: CGFloat { scale.highContrast ? 2 : 1 }
    private var dotStroke: CGFloat { scale.highContrast ? 2.5 : 1.5 }
    private var textScale: CGFloat { scale.textScale }
    private var iconScale: CGFloat { scale.iconScale }
    private var ink: Color { FamiliarPalette.ink(scale) }
    private var inkSecondary: Color { FamiliarPalette.inkSecondary(scale) }
    private var line: Color { scale.highContrast ? FamiliarPalette.ink(scale) : FamiliarPalette.stroke(scale) }

    private static let sectorCentersDegrees: [Double] = [-72, -36, 0, 36, 72]
    private static let sectorEdgesDegrees: [Double] = [-54, -18, 18, 54]
    /// The "Left" / "Right" labels hang off the arc at ±36°.
    private static let sideLabelDegrees: Double = 36

    func draw(in context: inout GraphicsContext, size: CGSize) {
        // Measure the labels first so the disc leaves room for them at every text size instead of being clipped.
        let font = FamiliarType.micro(scale)
        let probe = CGSize(width: 240, height: 120)
        let sideLabel = context.resolve(Text("Right").font(font)).measure(in: probe)
        let aheadLabel = context.resolve(Text("Ahead").font(font)).measure(in: probe)
        let topPad: CGFloat = max(24 * textScale, aheadLabel.height + 8)
        let bottomPad: CGFloat = max(26 * textScale, 7 * iconScale + 5 + sideLabel.height + 4)
        let center = CGPoint(x: size.width / 2, y: size.height - bottomPad)
        let sideSin: CGFloat = CGFloat(sin(Self.sideLabelDegrees * Double.pi / 180))
        let sideRoom: CGFloat = (size.width / 2 - sideLabel.width - 4) / sideSin - 8
        let radius: CGFloat = max(24, min(size.width / 2 - 6, sideRoom, size.height - bottomPad - topPad))

        drawDisc(in: &context, center: center, radius: radius)
        drawRings(in: &context, center: center, radius: radius)
        drawSectors(in: &context, center: center, radius: radius)
        drawRingLabels(in: &context, center: center, radius: radius)
        drawSectorLabels(in: &context, center: center, radius: radius)
        drawPeople(in: &context, center: center, radius: radius, bounds: size)
        drawWearer(in: &context, center: center)
    }

    // MARK: Scaffold

    private func arcPath(center: CGPoint, radius: CGFloat, closed: Bool) -> Path {
        var path = Path()
        let steps = 72
        for i in 0...steps {
            let angle = Double.pi + Double(i) / Double(steps) * Double.pi
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed { path.closeSubpath() }
        return path
    }

    private func drawDisc(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let disc = arcPath(center: center, radius: radius, closed: true)
        let fill: Color = scale.highContrast ? FamiliarPalette.surface(scale) : FamiliarPalette.canvasSecondary
        context.fill(disc, with: .color(fill))
        context.stroke(disc, with: .color(line), lineWidth: hairline + 0.5)
    }

    private func drawRings(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for fraction in [Self.ringFraction(.close), Self.ringFraction(.medium)] {
            let ring = arcPath(center: center, radius: radius * fraction, closed: false)
            context.stroke(ring, with: .color(line),
                           style: StrokeStyle(lineWidth: hairline, dash: scale.highContrast ? [] : [4, 5]))
        }
    }

    private func drawSectors(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        var path = Path()
        for degrees in Self.sectorEdgesDegrees {
            let point = Self.point(center: center, radius: radius, degreesFromUp: degrees)
            path.move(to: center)
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(line), lineWidth: hairline)
    }

    private func drawRingLabels(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let labels: [(Distance, String)] = [(.close, "close"), (.medium, "medium"), (.far, "far")]
        for (distance, word) in labels {
            let y = center.y - radius * Self.ringFraction(distance) + 9 * textScale
            let text = Text(word).font(FamiliarType.micro(scale)).foregroundStyle(inkSecondary)
            context.draw(text, at: CGPoint(x: center.x + 7, y: y), anchor: .leading)
        }
    }

    private func drawSectorLabels(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let font = FamiliarType.micro(scale)
        // Ahead: above the top of the disc.
        context.draw(Text("Ahead").font(font).foregroundStyle(inkSecondary),
                     at: CGPoint(x: center.x, y: center.y - radius - 6), anchor: .bottom)
        // Left / right: just outside the arc, hanging off their sector centre.
        let leftPoint = Self.point(center: center, radius: radius + 8, degreesFromUp: -Self.sideLabelDegrees)
        context.draw(Text("Left").font(font).foregroundStyle(inkSecondary), at: leftPoint, anchor: .trailing)
        let rightPoint = Self.point(center: center, radius: radius + 8, degreesFromUp: Self.sideLabelDegrees)
        context.draw(Text("Right").font(font).foregroundStyle(inkSecondary), at: rightPoint, anchor: .leading)
        // Far left / far right: at the ends of the baseline, where the disc meets the floor.
        context.draw(Text("Far left").font(font).foregroundStyle(inkSecondary),
                     at: CGPoint(x: center.x - radius, y: center.y + 7), anchor: .topLeading)
        context.draw(Text("Far right").font(font).foregroundStyle(inkSecondary),
                     at: CGPoint(x: center.x + radius, y: center.y + 7), anchor: .topTrailing)
    }

    private func drawWearer(in context: inout GraphicsContext, center: CGPoint) {
        let r: CGFloat = 7 * iconScale
        let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.fill(dot, with: .color(ink))
        context.stroke(dot, with: .color(FamiliarPalette.surface(scale)), lineWidth: hairline + 1)
        let label = Text("You").font(FamiliarType.micro(scale)).foregroundStyle(ink)
        context.draw(label, at: CGPoint(x: center.x, y: center.y + r + 5), anchor: .top)
    }

    // MARK: People

    private func drawPeople(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, bounds: CGSize) {
        let placed = placements(center: center, radius: radius)
        for placement in placed where !placement.track.identity.isKnown {
            let r: CGFloat = 7 * iconScale
            let dot = Path(ellipseIn: CGRect(x: placement.point.x - r, y: placement.point.y - r, width: r * 2, height: r * 2))
            context.fill(dot, with: .color(FamiliarPalette.surface(scale)))
            context.stroke(dot, with: .color(ink), lineWidth: dotStroke)
        }
        for placement in placed where placement.track.identity.isKnown {
            let r: CGFloat = 9 * iconScale
            let rect = CGRect(x: placement.point.x - r, y: placement.point.y - r, width: r * 2, height: r * 2)
            if !scale.highContrast {
                let halo = Path(ellipseIn: rect.insetBy(dx: -7, dy: -7))
                context.fill(halo, with: .color(FamiliarPalette.mint.opacity(0.28)))
            }
            let dot = Path(ellipseIn: rect)
            context.fill(dot, with: .color(FamiliarPalette.mint))
            context.stroke(dot, with: .color(ink), lineWidth: dotStroke)
            drawName(placement.track.identity.name ?? "", below: placement.point, dotRadius: r, in: &context, bounds: bounds)
        }
    }

    private func drawName(_ name: String, below point: CGPoint, dotRadius: CGFloat, in context: inout GraphicsContext, bounds: CGSize) {
        let text = Text(name).font(FamiliarType.micro(scale)).foregroundStyle(ink)
        let resolved = context.resolve(text)
        let measured = resolved.measure(in: CGSize(width: 180, height: 80))
        let padX: CGFloat = 8
        let padY: CGFloat = 4
        let width = measured.width + padX * 2
        let height = measured.height + padY * 2
        var x = point.x - width / 2
        x = min(max(2, x), bounds.width - width - 2)
        let rect = CGRect(x: x, y: point.y + dotRadius + 5, width: width, height: height)
        let pill = Path(roundedRect: rect, cornerRadius: height / 2)
        context.fill(pill, with: .color(FamiliarPalette.surface(scale)))
        context.stroke(pill, with: .color(line), lineWidth: hairline)
        context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    // MARK: Geometry

    struct Placement {
        let track: TrackSnapshot
        let point: CGPoint
    }

    /// Where each track sits: its band chooses the sector, its degrees nudge it inside the sector, and tracks sharing
    /// a sector and ring are fanned out so no two dots land on top of each other.
    func placements(center: CGPoint, radius: CGFloat) -> [Placement] {
        var groups: [String: [TrackSnapshot]] = [:]
        var order: [String] = []
        for track in tracks.sorted(by: { $0.trackID < $1.trackID }) {
            let key = "\(track.bearing.band)-\(track.distance)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(track)
        }
        var result: [Placement] = []
        for key in order {
            let members = groups[key] ?? []
            let count = members.count
            for (index, track) in members.enumerated() {
                let fan: Double = count > 1 ? (Double(index) - Double(count - 1) / 2) * 9 : 0
                let degrees = displayDegrees(for: track) + fan
                let point = Self.point(center: center, radius: radius * Self.ringFraction(track.distance), degreesFromUp: degrees)
                result.append(Placement(track: track, point: point))
            }
        }
        return result
    }

    /// Display angle from straight ahead (+ = right). The spoken band wins; the raw bearing only moves the dot a little
    /// within its 36° sector so two people in the same band still read left-to-right.
    func displayDegrees(for track: TrackSnapshot) -> Double {
        let sectorCenter: Double
        switch track.bearing.band {
        case .farLeft: sectorCenter = Self.sectorCentersDegrees[0]
        case .left: sectorCenter = Self.sectorCentersDegrees[1]
        case .ahead: sectorCenter = Self.sectorCentersDegrees[2]
        case .right: sectorCenter = Self.sectorCentersDegrees[3]
        case .farRight: sectorCenter = Self.sectorCentersDegrees[4]
        }
        let bandWidth = max(1, horizontalFOV * 0.125)
        let offset = (track.bearing.degrees - track.bearing.band.centerDegrees(hFOV: horizontalFOV)) / bandWidth
        let clamped = max(-1, min(1, offset))
        return sectorCenter + clamped * 12
    }

    static func ringFraction(_ distance: Distance) -> CGFloat {
        switch distance {
        case .close: return 0.32
        case .medium: return 0.62
        case .far: return 0.88
        }
    }

    static func point(center: CGPoint, radius: CGFloat, degreesFromUp: Double) -> CGPoint {
        let angle = degreesFromUp * Double.pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
    }
}

/// Filled mint dot = someone you know; hollow dot = someone. Shape and label carry the meaning, not colour.
private struct RadarLegend: View {
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(spacing: 18) {
            item(filled: true, text: "Someone you know")
            item(filled: false, text: "Someone")
        }
        .font(FamiliarType.micro(scale))
        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
    }

    private func item(filled: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(filled ? FamiliarPalette.mint : Color.clear)
                .overlay(Circle().strokeBorder(FamiliarPalette.ink(scale), lineWidth: scale.highContrast ? 2 : 1.5))
                .frame(width: 12 * scale.iconScale, height: 12 * scale.iconScale)
            Text(text)
        }
    }
}

// MARK: - Samples for previews (fixed ids so renders are stable)

extension RoomRadarView {
    static let sampleTracks: [TrackSnapshot] = [
        TrackSnapshot(trackID: 1,
                      identity: .known(personID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Marcus", score: 0.71),
                      bearing: Bearing(degrees: -4, band: .ahead), distance: .close,
                      faceBox: CGRect(x: 0.36, y: 0.22, width: 0.28, height: 0.26), faceHeightPx: 230,
                      yawDegrees: 3, isFacingUser: true, mouthOpenness: 0.1, quality: 0.8, timestamp: 0),
        TrackSnapshot(trackID: 2,
                      identity: .known(personID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Maya", score: 0.66),
                      bearing: Bearing(degrees: 12, band: .right), distance: .medium,
                      faceBox: CGRect(x: 0.66, y: 0.30, width: 0.16, height: 0.15), faceHeightPx: 120,
                      yawDegrees: -8, isFacingUser: true, mouthOpenness: 0.0, quality: 0.6, timestamp: 0),
        TrackSnapshot(trackID: 3,
                      identity: .unknown(bestScore: 0.21),
                      bearing: Bearing(degrees: -21, band: .farLeft), distance: .far,
                      faceBox: CGRect(x: 0.04, y: 0.34, width: 0.08, height: 0.07), faceHeightPx: 60,
                      yawDegrees: nil, isFacingUser: false, mouthOpenness: nil, quality: 0.4, timestamp: 0),
        TrackSnapshot(trackID: 4,
                      identity: .unknown(bestScore: nil),
                      bearing: Bearing(degrees: 16, band: .right), distance: .medium,
                      faceBox: CGRect(x: 0.74, y: 0.36, width: 0.14, height: 0.13), faceHeightPx: 110,
                      yawDegrees: nil, isFacingUser: false, mouthOpenness: nil, quality: 0.5, timestamp: 0),
    ]
}

#Preview("Room radar") {
    VStack(spacing: 16) {
        RoomRadarView(tracks: RoomRadarView.sampleTracks)
            .surfaceCard(padding: 16)
        RoomRadarView(tracks: [])
            .surfaceCard(padding: 16)
    }
    .padding(FamiliarPalette.margin)
    .familiarCanvas()
}

#Preview("Room radar, high contrast") {
    RoomRadarView(tracks: RoomRadarView.sampleTracks)
        .surfaceCard(padding: 16)
        .padding(FamiliarPalette.margin)
        .familiarCanvas()
        .environment(\.visionScale, VisionScale.make(.severe))
}
