import SwiftUI

/// Small uppercase label above a headline ("AWARENESS IS ON").
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(FamiliarType.micro)
            .tracking(1.4)
            .foregroundStyle(FamiliarPalette.inkSecondary)
    }
}

/// Compact pill with an icon and a word or two: device state, cue level, consent state.
struct StatusChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = FamiliarPalette.inkSecondary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.footnote.weight(.semibold)).accessibilityHidden(true) }
            Text(text).font(FamiliarType.micro).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(FamiliarPalette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(FamiliarPalette.stroke, lineWidth: 1))
    }
}

/// Five bars that follow the microphone level.
struct MicMeter: View {
    let level: Float
    var bars: Int = 5
    var color: Color = FamiliarPalette.ocean

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let threshold = Float(i + 1) / Float(bars)
                Capsule()
                    .fill(level >= threshold ? color : FamiliarPalette.stroke)
                    .frame(width: 5, height: 8 + CGFloat(i) * 4)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityLabel("Microphone level \(Int((level * 100).rounded())) percent")
    }
}

/// The last thing Familiar said, large, with the two before it underneath.
struct CueTicker: View {
    let cues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = cues.last {
                Text(last)
                    .font(FamiliarType.companion)
                    .foregroundStyle(FamiliarPalette.ink)
                    .contentTransition(.opacity)
                    .id(last)
            } else {
                Text("We'll speak when something matters.")
                    .font(FamiliarType.companion)
                    .foregroundStyle(FamiliarPalette.inkSecondary)
            }
            ForEach(Array(cues.dropLast().suffix(2).reversed().enumerated()), id: \.offset) { _, cue in
                Text(cue).font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last cue: \(cues.last ?? "none yet")")
    }
}

/// The trust line that is on every judge-facing screen.
struct PrivacyBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(FamiliarPalette.ocean).accessibilityHidden(true)
            Text(text).font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(radius: FamiliarPalette.controlRadius, padding: 14)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Soft two-colour monogram for a person without a photo.
struct Monogram: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [FamiliarPalette.mint, FamiliarPalette.lilac], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(FamiliarPalette.ink)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One known person in the room: name, direction, distance, one action.
struct NearbyPersonCard: View {
    let name: String
    let direction: String
    let distance: String
    var score: Float? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Monogram(name: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(FamiliarType.title).foregroundStyle(FamiliarPalette.ink)
                Text("\(direction) · \(distance)").font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GhostPillStyle())
                    .frame(width: 96)
            }
        }
        .surfaceCard(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(direction), \(distance). Known person\(score.map { String(format: ", match %.0f percent", $0 * 100) } ?? "").")
    }
}
