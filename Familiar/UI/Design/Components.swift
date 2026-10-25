import SwiftUI

/// The two things the wearer does most, big enough to hit without looking.
struct BigActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.familiarTitle)
                    Text(subtitle).font(.familiarBody).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.headline).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: FamiliarTheme.minTarget, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: FamiliarTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
        .glassCard(tint: tint.opacity(0.35))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct StatusPill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text).lineLimit(1)
        }
        .font(.familiarCaption)
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCard(radius: 14)
    }
}

/// Five bars that follow the microphone level: the on-table proof that the mic is alive.
struct MicMeter: View {
    let level: Float
    var bars: Int = 5
    var color: Color = FamiliarTheme.consent

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let threshold = Float(i + 1) / Float(bars)
                Capsule()
                    .fill(level >= threshold ? color : Color.white.opacity(0.18))
                    .frame(width: 5, height: 8 + CGFloat(i) * 4)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityLabel("Microphone level \(Int((level * 100).rounded())) percent")
    }
}

/// The last thing the glasses said, large, with the two before it underneath.
struct CueTicker: View {
    let cues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = cues.last {
                Text(last)
                    .font(.familiarTitle)
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)
                    .id(last)
            } else {
                Text("Listening…").font(.familiarTitle).foregroundStyle(.secondary)
            }
            ForEach(Array(cues.dropLast().suffix(2).reversed().enumerated()), id: \.offset) { _, cue in
                Text(cue).font(.familiarBody).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last cue: \(cues.last ?? "none yet")")
    }
}

struct PrivacyBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.title3).foregroundStyle(FamiliarTheme.consent).accessibilityHidden(true)
            Text(text).font(.familiarCaption).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18, tint: FamiliarTheme.consent.opacity(0.25))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Square glass tile for the navigation grid on Home.
struct GlassTile<Destination: View>: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    var hint: String = ""
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage).font(.title).foregroundStyle(FamiliarTheme.consent).accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(title).font(.familiarBody.weight(.semibold))
                if let detail { Text(detail).font(.familiarCaption).foregroundStyle(.secondary) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: FamiliarTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
        .glassCard()
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityHint(hint)
    }
}
