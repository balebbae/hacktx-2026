import SwiftUI

/// UserDefaults keys the You screens own. `UserSettings` (FlowRuntime.swift) holds the older ones; these are the
/// accessibility and speech preferences added by the You hub. Other modules read them by key.
enum YouSettings {
    /// Bool, default true. `FamiliarHaptics` is a no-op when false.
    static let hapticsEnabled = "hapticsEnabled"
    /// Double 0.8…1.3, default 1. Speech rate multiplier for the voice (`SpeechPreferences.rateMultiplier`).
    static let speechRate = "speechRate"
    /// Double 0.3…1, default 1. Speech volume for the voice, a gain inside the phone volume (`SpeechPreferences.volume`).
    static let speechVolume = "speechVolume"
    /// Bool, default false. When true the cue toast stays until the next cue instead of fading after five seconds.
    static let cueTextStaysOnScreen = "cueTextStaysOnScreen"
    /// `MimoPresence.rawValue`, default "full". How much of Mimo the Today and Room screens show.
    static let mimoPresence = "mimoPresence"
}

/// How much of Mimo is on screen (spec 19.6 Settings: full, compact, hidden). Mimo is the face of the app, never its
/// voice: cues are spoken and shown as text whatever is chosen here.
enum MimoPresence: String, CaseIterable, Identifiable {
    case full, compact, hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full"
        case .compact: return "Compact"
        case .hidden: return "Hidden"
        }
    }

    /// The stored choice, or `.full` for a fresh install.
    static func stored(_ rawValue: String) -> MimoPresence { MimoPresence(rawValue: rawValue) ?? .full }
}

/// Copy helpers shared by the You screens.
enum YouCopy {
    static func people(_ n: Int) -> String { n == 1 ? "1 person" : "\(n) people" }

    static func peopleChoseToConnect(_ n: Int) -> String {
        switch n {
        case 0: return "No one has chosen to connect yet"
        case 1: return "1 person chose to connect"
        default: return "\(n) people chose to connect"
        }
    }

    /// The one confirmation every "remove everyone" path uses, so the target is named wherever it is asked.
    static func removeEveryoneTitle(_ n: Int) -> String { "Remove \(people(n))? This deletes everything about them." }
}

/// Widths shared by the rows so icons, dividers and text line up.
enum YouMetrics {
    static func iconColumn(_ scale: VisionScale) -> CGFloat { 36 * scale.iconScale }
    static func dividerInset(_ scale: VisionScale) -> CGFloat { iconColumn(scale) + 12 + 14 }
    /// Divider inset for rows that carry no icon: the row's own horizontal padding.
    static let plainInset: CGFloat = 12
}

// MARK: - Section

/// A section on the ivory canvas: an eyebrow title, one white card holding rows, an optional footer line.
/// Callers place `YouDivider()` between rows.
struct YouSection<Content: View>: View {
    let title: String?
    let footer: String?
    private let content: () -> Content
    @Environment(\.visionScale) private var scale

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Eyebrow(text: title)
                    .padding(.horizontal, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content()
            }
            .surfaceCard(padding: 6)
            if let footer {
                Text(footer)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .padding(.horizontal, 8)
            }
        }
    }
}

/// Hairline between two rows. By default it is inset past the icon column; pass `inset: YouMetrics.plainInset`
/// between rows that carry no icon so the line starts under their text. Two points wide in high contrast.
struct YouDivider: View {
    var inset: CGFloat? = nil
    @Environment(\.visionScale) private var scale

    init(inset: CGFloat? = nil) {
        self.inset = inset
    }

    var body: some View {
        Rectangle()
            .fill(FamiliarPalette.stroke(scale))
            .frame(height: scale.strokeWidth)
            .padding(.leading, inset ?? YouMetrics.dividerInset(scale))
            .accessibilityHidden(true)
    }
}

// MARK: - Navigation title

/// The inline navigation title in Plus Jakarta Sans, so pushed You screens do not fall back to the system font.
struct YouNavigationTitle: View {
    let text: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        Text(text)
            .font(FamiliarType.body(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Keeps `navigationTitle` (so a child's back button still reads this title) and draws the visible title in Jakarta.
    func youNavigationTitle(_ title: String) -> some View {
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    YouNavigationTitle(text: title)
                }
            }
    }
}

// MARK: - Rows

/// Icon · title · detail · chevron. The label of a `NavigationLink` or `Button`, or a plain row.
struct YouRow: View {
    let title: String
    var systemImage: String? = nil
    var detail: String? = nil
    var showsChevron: Bool = true
    var tint: Color? = nil
    var titleColor: Color? = nil
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .visionIcon(scale, base: 20)
                    .foregroundStyle(tint ?? FamiliarPalette.ocean(scale))
                    .frame(width: YouMetrics.iconColumn(scale))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(titleColor ?? FamiliarPalette.ink(scale))
                if let detail {
                    Text(detail)
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .visionIcon(scale, base: 13)
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: scale.hitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let detail { return "\(title). \(detail)" }
        return title
    }
}

/// Press feedback for a whole row: a faint canvas tint and the 0.97 tap scale for 100 ms (no scale under simplified
/// motion). A disabled row dims like the pills do, so the state is visible, not only spoken.
struct YouRowButtonStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? FamiliarPalette.canvasSecondary : Color.clear,
                        in: RoundedRectangle(cornerRadius: FamiliarPalette.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !scale.simplifyMotion ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

/// A full-width tappable row. Destructive rows draw in the danger colour and say so to VoiceOver.
struct YouActionRow: View {
    let title: String
    var systemImage: String? = nil
    var detail: String? = nil
    var role: ButtonRole? = nil
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            YouRow(title: title,
                   systemImage: systemImage,
                   detail: detail,
                   showsChevron: false,
                   tint: isDestructive ? FamiliarPalette.danger : nil,
                   titleColor: isDestructive ? FamiliarPalette.danger : nil)
        }
        .buttonStyle(YouRowButtonStyle())
        .youHint(hint)
    }

    private var isDestructive: Bool { role == .destructive }
}

/// Title and detail on the left, a switch on the right.
struct YouToggleRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    @Binding var isOn: Bool
    var hint: String? = nil
    @Environment(\.visionScale) private var scale

    var body: some View {
        Toggle(isOn: $isOn) {
            YouRow(title: title, systemImage: systemImage, detail: detail, showsChevron: false)
        }
        .toggleStyle(.switch)
        .tint(FamiliarPalette.ocean(scale))
        .padding(.trailing, 12)
        .youHint(hint)
    }
}

/// Title with the current value on the right, a slider underneath, small words at both ends.
/// The title and value stack at accessibility text sizes and from the severe profile on.
struct YouSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var format: (Double) -> String = { (v: Double) -> String in String(format: "%.2f", v) }
    var minimumLabel: String? = nil
    var maximumLabel: String? = nil
    var hint: String? = nil
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .accessibilityHidden(true)
            Slider(value: $value, in: range, step: step) {
                Text(title)
            } minimumValueLabel: {
                Text(minimumLabel ?? "")
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            } maximumValueLabel: {
                Text(maximumLabel ?? "")
                    .font(FamiliarType.micro(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
            .tint(FamiliarPalette.ocean(scale))
            .accessibilityValue(format(value))
            .youHint(hint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: scale.hitTarget)
    }

    private var header: some View {
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(title)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
            if !stacked { Spacer(minLength: 8) }
            Text(format(value))
                .font(FamiliarType.mono(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title and value on the left, plus and minus on the right.
struct YouStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = ""
    var hint: String? = nil
    @Environment(\.visionScale) private var scale

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                Text(valueText)
                    .font(FamiliarType.mono(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .contentTransition(.numericText())
            }
        }
        .tint(FamiliarPalette.ink(scale))
        .accessibilityValue(valueText)
        .youHint(hint)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: scale.hitTarget)
    }

    private var valueText: String { unit.isEmpty ? "\(value)" : "\(value) \(unit)" }
}

/// A fact: title on the left, value on the right. One VoiceOver element. Title and value stack at accessibility
/// text sizes and from the severe profile on, so neither is forced into a one-word-per-line column.
struct YouValueRow: View {
    let title: String
    let value: String
    var systemImage: String? = nil
    var tint: Color? = nil
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize || scale.prefersStackedLayout }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .visionIcon(scale, base: 18)
                    .foregroundStyle(tint ?? FamiliarPalette.inkSecondary(scale))
                    .frame(width: YouMetrics.iconColumn(scale))
                    .accessibilityHidden(true)
            }
            pair
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: scale.hitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var pair: some View {
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(title)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
            if !stacked { Spacer(minLength: 12) }
            Text(value)
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small caption above a plain text field. The caption is the label; the placeholder, when given, is a different
/// short invitation so the row never reads "Your name / Your name".
struct YouTextFieldRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String? = nil
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .textFieldStyle(.plain)
                .accessibilityLabel(title)
                .youHint(hint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: scale.hitTarget)
    }
}

/// Title and detail above a control that needs the full width (a sliding pill segment or a menu picker).
struct YouChoiceRow<Control: View>: View {
    let title: String
    let detail: String?
    private let control: () -> Control
    @Environment(\.visionScale) private var scale

    init(title: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(FamiliarType.body(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                if let detail {
                    Text(detail)
                        .font(FamiliarType.supporting(scale))
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
            }
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

extension View {
    /// Adds an accessibility hint only when there is one.
    @ViewBuilder func youHint(_ hint: String?) -> some View {
        if let hint {
            self.accessibilityHint(hint)
        } else {
            self
        }
    }
}

#Preview("You rows") {
    ScrollView {
        VStack(spacing: 20) {
            YouSection(title: "Preferences", footer: "Rows scale with the vision profile.") {
                YouRow(title: "Voice and cues", systemImage: "speaker.wave.2", detail: "Quiet, normal or chatty")
                YouDivider()
                YouToggleRow(title: "Haptics", detail: "A soft tap with each cue", systemImage: "hand.tap", isOn: .constant(true))
                YouDivider()
                YouValueRow(title: "ElevenLabs key", value: "present", systemImage: "checkmark.circle", tint: FamiliarPalette.success)
                YouDivider()
                YouActionRow(title: "Remove everyone", systemImage: "trash", role: .destructive) {}
            }
            YouSection(title: "Plain rows", footer: "Dividers start under the text when rows carry no icon.") {
                YouSliderRow(title: "Speech rate", value: .constant(1), range: 0.8...1.3, step: 0.05, minimumLabel: "Slower", maximumLabel: "Faster")
                YouDivider(inset: YouMetrics.plainInset)
                YouStepperRow(title: "Minimum face size", value: .constant(40), range: 24...120, step: 4, unit: "px")
                YouDivider(inset: YouMetrics.plainInset)
                YouTextFieldRow(title: "Your name", text: .constant(""), placeholder: "Add your name")
            }
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}
