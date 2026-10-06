import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppViewModel
    var body: some View {
        GeometryReader { geometry in
            // AppKit can propose a zero-sized hosting view during window creation.
            // A zero scale makes NSScrollView's inverse transform singular.
            let scale = max(0.01, min(geometry.size.width / 1440, geometry.size.height / 960))
            ZStack {
                AmbientBackground()
                if model.isSignedIn { ControlView(model: model) } else { SignInView(model: model) }
            }
            .frame(width: 1440, height: 960)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea().preferredColorScheme(.dark).tint(HearlyColor.lime)
    }
}

struct SignInView: View {
    @ObservedObject var model: AppViewModel
    @State private var legal: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VoiceMark(size: 114).padding(.top, 106)
                wordmark(size: 58).padding(.top, 22)
                (Text("Cut the Noise, ").foregroundColor(HearlyColor.muted) + Text("Keep the Talk.").foregroundColor(HearlyColor.lime))
                    .font(.system(size: 20)).padding(.top, 18).padding(.bottom, 50)
                provider("Continue with Apple", apple: true) { model.oauth("apple") }
                provider("Continue with Google", apple: false) { model.oauth("google") }.padding(.top, 20)
                HStack(spacing: 32) {
                    Rectangle().fill(HearlyColor.stroke).frame(height: 1)
                    Text("or").font(.system(size: 18)).foregroundStyle(HearlyColor.muted)
                    Rectangle().fill(HearlyColor.stroke).frame(height: 1)
                }.padding(.vertical, 28)
                HStack(spacing: 18) {
                    Image(systemName: "envelope").font(.system(size: 24)).foregroundStyle(HearlyColor.muted)
                    TextField("Email address", text: $model.authEmail).textContentType(.username)
                        .onSubmit(model.emailContinue)
                }.hearlyField()
                if model.codeSent {
                    Text("Enter the code sent to your email.").font(.system(size: 15)).foregroundStyle(HearlyColor.muted).padding(.top, 14)
                    TextField("Email verification code", text: $model.authCode).hearlyField().padding(.top, 10)
                        .onSubmit(model.emailContinue)
                }
                LimeButton(title: model.busy ? "Connecting…" : model.codeSent ? "Verify & Continue" : "Continue", height: 70, action: model.emailContinue)
                    .disabled(model.busy).padding(.top, 26)
                if let error = model.authErrorMessage {
                    Text(error).font(.system(size: 14)).foregroundStyle(.orange).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                }
                VStack(spacing: 5) {
                    Text("By continuing, you agree to our").foregroundStyle(HearlyColor.muted)
                    HStack(spacing: 4) {
                        Button("Terms of Service") { legal = "Voice filtering isolates your speech and suppresses background noise. Test your setup before important calls." }
                        Text("and").foregroundStyle(HearlyColor.muted)
                        Button("Privacy Policy.") { legal = "Voiceprints and transcripts are encrypted on this Mac. Raw audio is processed locally. No audio leaves your device." }
                    }.buttonStyle(.plain).foregroundStyle(HearlyColor.lime)
                }.font(.system(size: 15)).padding(.top, 40).padding(.bottom, 60)
            }.frame(width: 520).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
        .alert("Hearly", isPresented: Binding(get: { legal != nil }, set: { if !$0 { legal = nil } })) {
            Button("Done") { legal = nil }
        } message: { Text(legal ?? "") }
    }
    private func provider(_ title: String, apple: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).font(.system(size: 21, weight: .medium))
                HStack {
                    if apple { Image(systemName: "apple.logo").font(.system(size: 34)).frame(width: 36) }
                    else { GoogleMark().frame(width: 34, height: 34) }
                    Spacer()
                }.padding(.leading, 54)
            }.frame(maxWidth: .infinity).frame(height: 70).background(GlassSurface(radius: 21))
        }.buttonStyle(.plain).disabled(model.busy)
    }
}

/// Vector mark keeps the four-color provider identity sharp at Retina scale.
private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 48
            context.scaleBy(x: scale, y: scale)
            func shape(_ points: [(CGFloat, CGFloat)], color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: points[0].0, y: points[0].1))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            var ring = Path()
            ring.addArc(center: CGPoint(x: 24, y: 24), radius: 18, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: true)
            context.stroke(ring, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), style: StrokeStyle(lineWidth: 9))
            var upper = Path()
            upper.addArc(center: CGPoint(x: 24, y: 24), radius: 18, startAngle: .degrees(220), endAngle: .degrees(315), clockwise: false)
            context.stroke(upper, with: .color(Color(red: 0.92, green: 0.26, blue: 0.21)), style: StrokeStyle(lineWidth: 9))
            var left = Path()
            left.addArc(center: CGPoint(x: 24, y: 24), radius: 18, startAngle: .degrees(145), endAngle: .degrees(220), clockwise: false)
            context.stroke(left, with: .color(Color(red: 0.98, green: 0.74, blue: 0.02)), style: StrokeStyle(lineWidth: 9))
            var lower = Path()
            lower.addArc(center: CGPoint(x: 24, y: 24), radius: 18, startAngle: .degrees(42), endAngle: .degrees(145), clockwise: false)
            context.stroke(lower, with: .color(Color(red: 0.20, green: 0.66, blue: 0.33)), style: StrokeStyle(lineWidth: 9))
            shape([(24,20), (45,20), (45,28), (24,28)], color: Color(red: 0.26, green: 0.52, blue: 0.96))
        }.accessibilityHidden(true)
    }
}
