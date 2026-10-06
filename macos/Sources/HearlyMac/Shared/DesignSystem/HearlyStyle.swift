import SwiftUI

enum HearlyColor {
    static let canvas = Color(red: 0.022, green: 0.038, blue: 0.040)
    static let sidebar = Color.white.opacity(0.025)
    static let surface = Color.white.opacity(0.025)
    static let stroke = Color.white.opacity(0.13)
    static let lime = Color(red: 0.69, green: 0.95, blue: 0.23)
    static let purple = lime
    static let muted = Color(red: 0.65, green: 0.69, blue: 0.73)
}

/// Drawn in points, not placed over a screenshot: every control remains native.
struct AmbientBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                HearlyColor.canvas
                RadialGradient(colors: [Color(red: 0.25, green: 0.38, blue: 0.16).opacity(0.52), .clear], center: UnitPoint(x: 0.24, y: 0.17), startRadius: 0, endRadius: geo.size.width * 0.16)
                RadialGradient(colors: [Color(red: 0.29, green: 0.47, blue: 0.24).opacity(0.38), .clear], center: UnitPoint(x: 0.85, y: 0.43), startRadius: 0, endRadius: geo.size.width * 0.17)
                RadialGradient(colors: [Color(red: 0.36, green: 0.48, blue: 0.29).opacity(0.43), .clear], center: UnitPoint(x: 0.29, y: 0.92), startRadius: 0, endRadius: geo.size.width * 0.19)
                RadialGradient(colors: [Color(red: 0.25, green: 0.40, blue: 0.17).opacity(0.35), .clear], center: UnitPoint(x: 0.80, y: 0.97), startRadius: 0, endRadius: geo.size.width * 0.14)
                LinearGradient(colors: [.white.opacity(0.035), .clear, .black.opacity(0.26), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea()
    }
}

struct VoiceMark: View {
    var size: CGFloat = 48
    var body: some View {
        Canvas { context, canvas in
            let bars: [(CGFloat, CGFloat, CGFloat)] = [
                (0.02, 0.79, 0.09), (0.15, 0.77, 0.14), (0.28, 0.59, 0.31),
                (0.41, 0.38, 0.48), (0.54, 0.19, 0.58), (0.67, 0.06, 0.48),
                (0.80, 0.16, 0.25), (0.93, 0.30, 0.10)
            ]
            for (index, bar) in bars.enumerated() {
                let rect = CGRect(x: bar.0 * canvas.width, y: bar.1 * canvas.height, width: canvas.width * 0.071, height: bar.2 * canvas.height)
                let alpha: Double = [0.26, 0.48, 0.88, 1, 1, 1, 0.52, 0.30][index]
                context.fill(Path(roundedRect: rect, cornerRadius: canvas.width * 0.04), with: .linearGradient(Gradient(colors: [HearlyColor.lime.opacity(alpha), Color(red: 0.56, green: 0.87, blue: 0.37).opacity(alpha)]), startPoint: rect.origin, endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }.frame(width: size, height: size * 0.72)
            .shadow(color: HearlyColor.lime.opacity(0.16), radius: 8).accessibilityHidden(true)
    }
}

struct HearlyLogo: View {
    var compact = false
    var body: some View {
        HStack(spacing: 12) { VoiceMark(size: 43); if !compact { wordmark(size: 31) } }
    }
}

func wordmark(size: CGFloat) -> some View {
    (Text("Hearl").foregroundColor(.white) + Text("y").foregroundColor(HearlyColor.lime))
        .font(.system(size: size, weight: .bold)).tracking(-size * 0.035)
}

struct BrandHero: View {
    var small = false
    var body: some View {
        VStack(spacing: 17) {
            VoiceMark(size: small ? 108 : 140)
            wordmark(size: small ? 45 : 66)
            Text("VERSION 1").font(.system(size: 14, weight: .medium)).tracking(4).foregroundStyle(HearlyColor.muted)
            (Text("Cut the Noise, ").foregroundColor(HearlyColor.muted) + Text("Keep the Talk.").foregroundColor(HearlyColor.lime))
                .font(.system(size: small ? 22 : 26, weight: small ? .medium : .regular)).padding(.top, 1)
        }
    }
}

struct HearlyCard<Content: View>: View {
    let content: Content
    var accent: Bool
    init(accent: Bool = false, @ViewBuilder content: () -> Content) { self.accent = accent; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }.padding(24).frame(maxWidth: .infinity).background(GlassSurface(accent: accent))
    }
}

struct GlassSurface: View {
    var accent = false
    var radius: CGFloat = 22
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(colors: [.white.opacity(0.032), .black.opacity(0.11), accent ? HearlyColor.lime.opacity(0.065) : .white.opacity(0.017)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(accent ? HearlyColor.lime.opacity(0.32) : HearlyColor.stroke, lineWidth: 1))
    }
}

struct LimeButton: View {
    let title: String
    var solid = false
    var icon = "arrow.right"
    var height: CGFloat = 66
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Text(title).font(.system(size: height <= 54 ? 19 : 21, weight: .medium))
                if !icon.isEmpty { Image(systemName: icon).font(.system(size: height <= 54 ? 20 : 23)) }
            }.padding(.horizontal, 24)
            .foregroundStyle(solid ? Color.black : .white).frame(maxWidth: .infinity).frame(height: height)
            .background(LinearGradient(colors: solid ? [HearlyColor.lime, Color(red: 0.60, green: 0.85, blue: 0.22)] : [HearlyColor.lime.opacity(0.13), .white.opacity(0.025), HearlyColor.lime.opacity(0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule()).overlay(Capsule().stroke(HearlyColor.lime.opacity(0.78), lineWidth: 1))
            .shadow(color: HearlyColor.lime.opacity(0.10), radius: 22).opacity(enabled ? 1 : 0.32)
        }.buttonStyle(.plain)
    }
}

struct IconTile: View {
    let icon: String
    var accent = false
    var body: some View {
        Image(systemName: icon).font(.system(size: 28, weight: .regular))
            .foregroundStyle(accent ? HearlyColor.lime : HearlyColor.muted).frame(width: 56, height: 56)
            .background(LinearGradient(colors: [.white.opacity(0.065), .white.opacity(0.018)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(HearlyColor.stroke.opacity(0.5)))
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 15) { Circle().fill(color).frame(width: 13, height: 13); Text(title).font(.system(size: 14, weight: .medium)).tracking(2) }
            .foregroundStyle(color).padding(.horizontal, 24).frame(height: 47)
            .background(LinearGradient(colors: [color.opacity(0.12), .black.opacity(0.1), color.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            .clipShape(Capsule()).overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

struct HearlyWaveform: View {
    let level: Float
    let isActive: Bool
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<19) { index in
                let shape = max(0.12, 1 - abs(Double(index) - 9) / 10)
                Capsule().fill(HearlyColor.lime.opacity(isActive ? 0.9 : 0.25))
                    .frame(width: 4, height: CGFloat(5 + shape * Double(isActive ? level : 0) * 68))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }.frame(maxWidth: .infinity).frame(height: 88)
    }
}

struct HearlyToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? HearlyColor.lime : .white.opacity(0.07)).overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1.5))
                    Circle().fill(configuration.isOn ? .white : HearlyColor.muted).padding(3).shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }.frame(width: 74, height: 41)
            }.buttonStyle(.plain).accessibilityLabel(Text("Toggle")).accessibilityValue(configuration.isOn ? "On" : "Off")
        }.accessibilityElement(children: .combine)
    }
}

struct MicrophoneOrb: View {
    var recording = false
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle().fill(HearlyColor.lime.opacity(0.015)).overlay(Circle().stroke(HearlyColor.lime.opacity(0.025))).padding(CGFloat(index) * 15)
            }
            Circle().fill(RadialGradient(colors: [.black.opacity(0.1), HearlyColor.lime.opacity(recording ? 0.15 : 0.08)], center: .center, startRadius: 28, endRadius: 59))
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.35), HearlyColor.lime], startPoint: .top, endPoint: .bottom), lineWidth: 1.4)).padding(31)
            Image(systemName: "mic").font(.system(size: 44, weight: .light)).foregroundStyle(recording ? .white : Color(red: 0.77, green: 0.94, blue: 0.58))
        }.frame(width: 174, height: 174)
    }
}

extension View {
    func hearlyField() -> some View {
        self.textFieldStyle(.plain).font(.system(size: 20)).padding(.horizontal, 26).frame(height: 68).background(GlassSurface(radius: 21))
    }
}
