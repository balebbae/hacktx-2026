import SwiftUI

/// Everything in the design system on one scrolling page, for one profile. Open the four previews side by side
/// to check that each size, weight, icon and hit target moves with the profile. Also handy as a settings preview.
struct DesignSystemGallery: View {
    var profile: VisionProfile = .balanced

    var body: some View {
        ScrollView {
            DesignSystemGalleryContent(profile: profile)
                .padding(FamiliarPalette.margin)
                .padding(.bottom, 40)
        }
        .familiarCanvas()
        .visionProfile(profile)
    }
}

private struct DesignSystemGalleryContent: View {
    let profile: VisionProfile
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(24)) {
            hero
            GallerySection(title: "Type") { typeRamp }
            GallerySection(title: "Pills") { pills }
            GallerySection(title: "Components") { components }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AuroraBackground(intensity: 1, mood: .calm)
            VStack(alignment: .leading, spacing: scale.spacing(6)) {
                Eyebrow(text: profile.title)
                Text("The finer things in life are felt, not seen.")
                    .font(FamiliarType.display(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
            }
            .padding(scale.spacing(20))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FamiliarPalette.surface(scale), in: RoundedRectangle(cornerRadius: FamiliarPalette.cardRadius, style: .continuous))
            .padding(scale.spacing(12))
        }
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarPalette.heroRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var typeRamp: some View {
        VStack(alignment: .leading, spacing: scale.spacing(8)) {
            Text("Feel at home in every room.").font(FamiliarType.display(scale))
            Text("In the room").font(FamiliarType.titleXL(scale))
            Text("Marcus").font(FamiliarType.title(scale))
            Text("Marcus, ahead, close.").font(FamiliarType.companion(scale))
            Text("Only people who agreed are ever recognized.").font(FamiliarType.body(scale))
            Text("Met at HackTX · Saturday").font(FamiliarType.supporting(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("Opted in").font(FamiliarType.micro(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale))
            Text("14:32:08").font(FamiliarType.mono(scale)).foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .foregroundStyle(FamiliarPalette.ink(scale))
    }

    private var pills: some View {
        VStack(spacing: scale.spacing(10)) {
            Button("Who's here?") {}.buttonStyle(PrimaryPillStyle())
            Button("Yes, remember me") {}.buttonStyle(AccentPillStyle())
            Button("Pause") {}.buttonStyle(GhostPillStyle())
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: scale.spacing(14)) {
            HStack(spacing: scale.spacing(8)) {
                StatusChip(text: "Glasses connected", systemImage: "eyeglasses", tint: FamiliarPalette.ink)
                StatusChip(text: "Normal cues", systemImage: "waveform")
            }
            MicMeter(level: 0.6)
            CueTicker(cues: ["Normal mode.", "Three people.", "Marcus, ahead, close."])
            NearbyPersonCard(name: "Marcus", direction: "ahead", distance: "close", score: 0.71,
                             actionTitle: "Call", action: {})
            HStack(spacing: scale.spacing(12)) {
                Monogram(name: "Marcus")
                Monogram(name: "Ana", size: 56)
                Spacer()
            }
            PrivacyBanner(text: "Only people who agreed are ever recognized. Faces stay on this phone.")
        }
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: scale.spacing(12)) {
            Text(title)
                .font(FamiliarType.titleXL(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

#Preview("Gallery · balanced") { DesignSystemGallery(profile: .balanced) }
#Preview("Gallery · low vision") { DesignSystemGallery(profile: .lowVision) }
#Preview("Gallery · severe") { DesignSystemGallery(profile: .severe) }
#Preview("Gallery · non-visual") { DesignSystemGallery(profile: .nonVisual) }
