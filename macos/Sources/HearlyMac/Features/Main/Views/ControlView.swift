import AppKit
import SwiftUI

struct ControlView: View {
    @ObservedObject var model: AppViewModel
    @State private var about = false
    @State private var accountMenu = false
    @State private var audioSetup = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(HearlyColor.stroke).frame(width: 1)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch model.page {
                    case .home: HomeView(model: model, about: $about)
                    case .training: TrainingView(model: model)
                    case .history: HistoryView(model: model)
                    case .settings: InAppSettingsView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !(model.page == .training && model.trainingStep == 1) && !(model.page == .home && model.profile == nil) {
                    Button { accountMenu.toggle() } label: {
                        Text(model.initials).font(.system(size: 20)).frame(width: 44, height: 44)
                            .background(GlassSurface(radius: 24))
                    }.buttonStyle(.plain).padding(.trailing, 26).padding(.top, 22)
                        .popover(isPresented: $accountMenu) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(model.signedInEmail ?? "Local workspace").foregroundStyle(HearlyColor.muted)
                                Button("Audio Setup") { accountMenu = false; audioSetup = true }
                                Text("Local-only · no account required").font(.caption)
                            }.padding(22)
                        }.accessibilityLabel("Account")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.notice ?? model.audio.errorMessage {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                    Text(message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if message.contains("driver") || message.contains("Driver") || model.virtualMicrophone.status != .installed {
                        Button("Install Driver", action: model.openDriverInstaller)
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                    Button { model.notice = nil; model.audio.clearError() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }.foregroundStyle(.orange).padding(14).background(.black.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange.opacity(0.3)))
                    .frame(maxWidth: 790).padding(.leading, 260).padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $about) {
            VStack(spacing: 24) {
                BrandHero(small: true)
                Text("A quieter world, a clearer you.").foregroundStyle(HearlyColor.muted)
                Text("Voice enrollment, local speaker recognition, noise reduction, and private transcript history.")
                    .multilineTextAlignment(.center).frame(width: 440)
                Button("Done") { about = false }.buttonStyle(.bordered)
            }.padding(40).background(AmbientBackground())
        }
        .sheet(isPresented: $audioSetup) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Audio Setup").font(.title.bold())
                HStack {
                    Text(model.virtualMicrophone.status.title)
                    Spacer()
                    if model.driverInstallerAvailable {
                        Button("Install or Update Driver", action: model.openDriverInstaller)
                    } else {
                        Text("Installer unavailable in this build").font(.caption).foregroundStyle(HearlyColor.muted)
                    }
                }
                Text("The installer opens separately and macOS will handle administrator approval.")
                    .font(.caption).foregroundStyle(HearlyColor.muted)
                Picker("Microphone", selection: $model.selectedInputDeviceID) {
                    Text("System default").tag(UInt32?.none)
                    ForEach(model.inputDevices) { Text($0.name).tag(UInt32?.some($0.id)) }
                }.disabled(model.audio.isRunning)
                Text("After starting Hearly, select Hearly Microphone as the input in your meeting app.").frame(width: 420)
                HStack {
                    Button("Refresh devices", action: model.refresh)
                    Button("Audio MIDI Setup") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")) }
                    Spacer()
                    Button("Done") { audioSetup = false }
                }
            }.padding(32)
        }
    }
    private var compactHome: Bool { model.page == .home && model.profile == nil }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !(model.page == .home && model.profile != nil) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        VoiceMark(size: compactHome ? 39 : 46)
                        wordmark(size: compactHome ? 25 : 31)
                    }
                    if !compactHome {
                        Text("Cut the Noise,\nKeep the Talk.").font(.system(size: 15)).lineSpacing(5).foregroundStyle(HearlyColor.muted).padding(.leading, 57)
                    }
                }.padding(.leading, 34).padding(.top, compactHome ? 86 : 102).padding(.bottom, compactHome ? 45 : 38)
            } else { Spacer().frame(height: 82) }
            VStack(spacing: 9) {
                ForEach(HearlyPage.allCases.filter { $0 != .training || (model.page == .training && model.trainingStep != 1) }, id: \.self) { page in
                    let selected = model.page == page || (model.page == .training && model.trainingStep == 1 && page == .home)
                    Button {
                        if model.page == .training && page != .training { model.stopAudio() }
                        model.page = page
                    } label: {
                        HStack(spacing: 17) {
                            Image(systemName: page.icon).font(.system(size: 28, weight: .regular)).frame(width: 32)
                                .foregroundStyle(selected ? HearlyColor.lime : HearlyColor.muted)
                            Text(page.rawValue).font(.system(size: 17, weight: selected ? .medium : .regular)).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                        }.foregroundStyle(selected ? .white : HearlyColor.muted).padding(.horizontal, 17).frame(height: 63)
                            .background(LinearGradient(colors: selected ? [HearlyColor.lime.opacity(0.15), .white.opacity(0.065)] : [.clear], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? HearlyColor.lime.opacity(0.12) : .clear))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18)
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                if compactHome {
                    Rectangle().fill(HearlyColor.muted.opacity(0.6)).frame(width: 38, height: 1)
                    Text("Cut the Noise,\nKeep the Talk.").font(.system(size: 18)).lineSpacing(5).foregroundStyle(HearlyColor.muted.opacity(0.8))
                } else {
                    Button { about = true } label: {
                        Text("A quieter world,\na clearer you.").font(.system(size: 16)).lineSpacing(6).foregroundStyle(HearlyColor.muted)
                    }.buttonStyle(.plain)
                }
            }.padding(.leading, 34).padding(.bottom, 43)
        }.frame(width: 259).background(LinearGradient(colors: [.white.opacity(0.035), .white.opacity(0.017), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private struct HomeView: View {
    @ObservedObject var model: AppViewModel
    @Binding var about: Bool
    var body: some View {
        ZStack {
            if model.profile == nil { HomeWaves().frame(height: 450).clipped().offset(y: -85).allowsHitTesting(false) }
            ScrollView {
                VStack(spacing: 0) {
                    BrandHero(small: model.profile != nil).padding(.top, model.profile == nil ? 100 : 60)
                    if let profile = model.profile {
                        enrolled(profile).padding(.top, 32)
                    } else {
                        StatusPill(title: "VOICE NOT ENROLLED", color: Color(red: 1, green: 0.43, blue: 0.43)).padding(.top, 35)
                        enrollmentCard.padding(.top, 18).padding(.bottom, 40)
                    }
                }.frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
        }
    }
    private var enrollmentCard: some View {
        VStack(spacing: 0) {
            MicrophoneOrb().padding(.top, 12)
            Text("Enroll Your Voice").font(.system(size: 31, weight: .semibold)).padding(.top, -1)
            Text("Set up focused listening in three quick steps.").font(.system(size: 21)).foregroundStyle(HearlyColor.muted).padding(.top, 10)
            LimeButton(title: "Start Voice Training", action: model.beginTraining).frame(width: 448).padding(.top, 29).padding(.bottom, 32)
        }.frame(width: 648)
            .background(LinearGradient(colors: [.white.opacity(0.065), .black.opacity(0.17), HearlyColor.lime.opacity(0.085), .white.opacity(0.07)], startPoint: .topTrailing, endPoint: .bottomLeading))
            .clipShape(RoundedRectangle(cornerRadius: 33))
            .overlay(RoundedRectangle(cornerRadius: 33).stroke(LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.14), HearlyColor.lime.opacity(0.50)], startPoint: .topTrailing, endPoint: .bottomLeading)))
    }
    private func enrolled(_ profile: VoiceProfile) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.circle").font(.system(size: 36, weight: .light)).foregroundStyle(HearlyColor.lime).padding(.top, 32)
            (Text("Voice Enrolled for ") + Text(profile.name).foregroundColor(HearlyColor.lime)).font(.system(size: 22, weight: .semibold)).padding(.top, 18)
            if model.meetingDetector.isMeetingActive {
                HStack(spacing: 12) {
                    Circle().fill(HearlyColor.lime).frame(width: 8, height: 8)
                    Text("Meeting Active: \(model.meetingDetector.meetingPlatform ?? "Connected")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HearlyColor.lime)
                    Spacer()
                    Text(model.autoStartInMeetings ? "Auto-Focus Enabled" : "Manual Mode")
                        .font(.system(size: 13))
                        .foregroundStyle(HearlyColor.muted)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(GlassSurface(accent: true, radius: 16))
                .padding(.top, 14)
            }
            VStack(spacing: 18) {
                Toggle(isOn: Binding(get: { model.audio.isRunning && !model.audio.isCapturing }, set: { _ in model.toggleAudio() })) {
                    controlRow("waveform", "Hearly", model.audio.isRunning ? "Hearly is currently active" : "Hearly is currently inactive")
                }.toggleStyle(HearlyToggleStyle()).disabled(model.audio.isStarting).padding(24).background(GlassSurface())

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        IconTile(icon: "headphones")
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Listen to Yourself")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.white)
                                if model.isAuditionActive {
                                    Circle()
                                        .fill(HearlyColor.lime)
                                        .frame(width: 7, height: 7)
                                    Text("LIVE MONITOR")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(HearlyColor.lime)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(HearlyColor.lime.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(model.isAuditionActive
                                 ? (model.auditionFeed == .filtered ? "Listening to real-time voice-isolated audio" : "Listening to raw microphone input (unfiltered)")
                                 : "Monitor your filtered voice in your headphones before meetings")
                                .font(.system(size: 13))
                                .foregroundStyle(HearlyColor.muted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.isAuditionActive },
                            set: { _ in Task { await model.toggleAudition() } }
                        ))
                        .labelsHidden()
                        .toggleStyle(HearlyToggleStyle())
                    }

                    if model.isAuditionActive {
                        HStack(spacing: 12) {
                            Text("Feed:")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HearlyColor.muted)

                            Button(action: { model.setAuditionFeed(.filtered) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Hearly Filtered")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(model.auditionFeed == .filtered ? HearlyColor.lime.opacity(0.2) : Color.white.opacity(0.06))
                                .foregroundStyle(model.auditionFeed == .filtered ? HearlyColor.lime : Color.white.opacity(0.7))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(model.auditionFeed == .filtered ? HearlyColor.lime.opacity(0.6) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button(action: { model.setAuditionFeed(.raw) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "mic")
                                    Text("Raw Mic")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(model.auditionFeed == .raw ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                                .foregroundStyle(model.auditionFeed == .raw ? .white : Color.white.opacity(0.7))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(model.auditionFeed == .raw ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            HStack(spacing: 6) {
                                Image(systemName: model.isHeadphonesConnected ? "airpodspro" : "speaker.wave.2")
                                    .font(.system(size: 12))
                                Text(model.isHeadphonesConnected ? "Headphones" : "Headphones recommended")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(model.isHeadphonesConnected ? HearlyColor.muted : Color.yellow.opacity(0.9))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(24)
                .background(GlassSurface(accent: model.isAuditionActive, radius: 20))

                // Physical Microphone Input Selector
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        IconTile(icon: model.selectedDeviceIcon)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Microphone Input")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(model.selectedInputDeviceID == nil ? "SYSTEM DEFAULT" : "MANUAL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(HearlyColor.lime)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(HearlyColor.lime.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text(model.selectedDeviceName)
                                .font(.system(size: 14))
                                .foregroundStyle(HearlyColor.muted)
                                .lineLimit(1)
                        }
                        Spacer()

                        Menu {
                            Button(action: { model.selectInputDevice(nil) }) {
                                HStack {
                                    Text("System default (\(CoreAudioDeviceManager.defaultInputDeviceName()))")
                                    if model.selectedInputDeviceID == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            ForEach(model.inputDevices) { device in
                                Button(action: { model.selectInputDevice(device.id) }) {
                                    HStack {
                                        Text(device.name)
                                        if model.selectedInputDeviceID == device.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Switch")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(HearlyColor.lime)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(HearlyColor.lime.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(HearlyColor.lime.opacity(0.3), lineWidth: 1))
                        }
                        .menuStyle(.borderlessButton)
                    }

                    if model.audio.isRunning {
                        HStack(spacing: 10) {
                            Text("Input Signal:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HearlyColor.muted)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule()
                                        .fill(LinearGradient(colors: [HearlyColor.lime, Color.yellow], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.02, model.audio.meterLevel))))
                                        .animation(.linear(duration: 0.08), value: model.audio.meterLevel)
                                }
                            }
                            .frame(height: 5)
                            Text(String(format: "%.0f%%", model.audio.meterLevel * 100))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(HearlyColor.lime)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(24)
                .background(GlassSurface(radius: 20))

                // Global Hotkey row
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        IconTile(icon: "keyboard")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Hotkey")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(model.hotkeyManager.isEnabled ? "Toggle Voice Focus system-wide with \(model.hotkeyManager.currentOption.rawValue)" : "Shortcut disabled")
                                .font(.system(size: 14))
                                .foregroundStyle(HearlyColor.muted)
                        }
                        Spacer()

                        if model.hotkeyManager.isEnabled {
                            Menu {
                                ForEach(HotkeyOption.allCases) { option in
                                    Button(action: { model.hotkeyManager.currentOption = option }) {
                                        HStack {
                                            Text(option.rawValue)
                                            if model.hotkeyManager.currentOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(model.hotkeyManager.currentOption.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(HearlyColor.lime)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(HearlyColor.lime.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(HearlyColor.lime.opacity(0.3), lineWidth: 1))
                            }
                            .menuStyle(.borderlessButton)
                        }

                        Toggle("", isOn: Binding(
                            get: { model.hotkeyManager.isEnabled },
                            set: { model.hotkeyManager.isEnabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(HearlyToggleStyle())
                    }
                }
                .padding(24)
                .background(GlassSurface(radius: 20))

                Toggle(isOn: $model.autoStartInMeetings) {
                    controlRow("phone.connection", "Auto-Detect Meetings", model.autoStartInMeetings ? "Voice Focus turns on automatically when Zoom, Meet, or Teams connects" : "Manual meeting control only")
                }.toggleStyle(HearlyToggleStyle()).padding(24).background(GlassSurface())
                Toggle(isOn: Binding(get: { model.transcriptEnabled }, set: model.setTranscript)) {
                    controlRow("doc.text", "Transcript", model.transcriptEnabled ? "Transcript is currently visible" : "Transcript is currently hidden")
                }.toggleStyle(HearlyToggleStyle()).padding(24).background(GlassSurface())
                if model.transcriptEnabled && !model.liveTranscript.isEmpty {
                    Text(model.liveTranscript).font(.system(size: 18)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.frame(width: 735).background(GlassSurface(radius: 32))
    }
}

private struct HomeWaves: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let ridge = Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.2))
                path.addCurve(to: CGPoint(x: width * 0.43, y: height * 0.52), control1: CGPoint(x: width * 0.19, y: -height * 0.23), control2: CGPoint(x: width * 0.26, y: height * 0.38))
                path.addCurve(to: CGPoint(x: width * 0.81, y: height * 0.35), control1: CGPoint(x: width * 0.67, y: height * 0.79), control2: CGPoint(x: width * 0.72, y: height * 0.25))
                path.addCurve(to: CGPoint(x: width, y: height * 0.70), control1: CGPoint(x: width * 0.86, y: height * 0.41), control2: CGPoint(x: width * 0.91, y: height * 0.55))
            }
            var filled = ridge
            let _ = filled.addLine(to: CGPoint(x: width, y: height))
            let _ = filled.addLine(to: CGPoint(x: 0, y: height))
            let _ = filled.closeSubpath()
            filled.fill(LinearGradient(colors: [HearlyColor.lime.opacity(0.11), .black.opacity(0.015), .clear], startPoint: .top, endPoint: .bottom))
            ForEach(0..<20) { band in
                ridge.stroke(HearlyColor.lime.opacity(0.006), lineWidth: CGFloat(8 + band * 4))
            }
            ridge.stroke(HearlyColor.lime.opacity(0.25), lineWidth: 1)
        }
    }
}

private func controlRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
    HStack(spacing: 26) {
        IconTile(icon: icon)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 17)).foregroundStyle(HearlyColor.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrainingView: View {
    @ObservedObject var model: AppViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { step in
                        Capsule().fill(step == model.trainingStep ? HearlyColor.lime : step < model.trainingStep ? HearlyColor.lime.opacity(0.28) : .white.opacity(0.12))
                            .frame(width: step == model.trainingStep ? 42 : 39, height: 6)
                    }
                }.padding(.top, 66)
                if model.trainingStep == 1 { preparation }
                else if model.trainingStep == 2 { recording }
                else { completed }
            }.frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
        .overlay(alignment: .topLeading) {
            if model.trainingStep == 2 {
                Button { model.restartPreparation() } label: { Label("Back", systemImage: "arrow.left").font(.system(size: 17)) }
                    .buttonStyle(.plain).foregroundStyle(HearlyColor.muted).padding(.leading, 38).padding(.top, 45)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.trainingStep == 1 {
                Button { model.stopAudio(); model.page = .home } label: {
                    Image(systemName: "xmark").font(.system(size: 22)).frame(width: 52, height: 52).background(GlassSurface(radius: 28))
                }.buttonStyle(.plain).padding(.trailing, 28).padding(.top, 28)
            }
        }
    }
    private var preparation: some View {
        VStack(spacing: 0) {
            Text("Step 1 of 3").font(.system(size: 16)).foregroundStyle(HearlyColor.muted).padding(.top, 20)
            Text("Before You Start").font(.system(size: 46, weight: .semibold)).padding(.top, 60)
            Text("Set up your voice profile in a quiet moment.\nHearly will use this sample to recognize you\nwith more confidence.")
                .font(.system(size: 22)).foregroundStyle(HearlyColor.muted).lineSpacing(10).multilineTextAlignment(.center).padding(.top, 15)
            HStack(spacing: 34) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Preparation").font(.system(size: 26, weight: .semibold)).padding(.bottom, 30)
                    ForEach(["Choose a quiet place with low\nbackground noise", "Use your normal speaking voice\nand pace", "Keep the sample short, clear, and\nnatural"], id: \.self) { text in
                        HStack(alignment: .top, spacing: 28) {
                            Image(systemName: "checkmark.circle").font(.system(size: 35, weight: .light)).foregroundStyle(HearlyColor.lime)
                            Text(text).font(.system(size: 19)).foregroundStyle(HearlyColor.muted).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
                        }.padding(.bottom, 28)
                    }
                    Spacer(minLength: 0)
                }.padding(38).frame(width: 458, height: 375, alignment: .topLeading).background(GlassSurface())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your Voice Profile").font(.system(size: 26, weight: .semibold))
                    Text("Enter your name and confirm your microphone to begin.").font(.system(size: 19)).foregroundStyle(HearlyColor.muted).lineSpacing(6).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                    HStack(spacing: 20) {
                        Image(systemName: "person").font(.system(size: 24)).foregroundStyle(HearlyColor.muted)
                        TextField("Enter your name", text: $model.profileName).onSubmit(model.prepareTraining)
                    }.hearlyField().padding(.top, 18)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MICROPHONE").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(HearlyColor.muted)
                            Spacer()
                            Button {
                                model.toggleMicrophoneTest()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: model.isTestingMicrophone ? "waveform" : "mic")
                                    Text(model.isTestingMicrophone ? "Stop Test" : "Test Mic")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(model.isTestingMicrophone ? HearlyColor.lime : HearlyColor.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        Picker("", selection: $model.selectedInputDeviceID) {
                            Text("System default").tag(UInt32?.none)
                            ForEach(model.inputDevices) { Text($0.name).tag(UInt32?.some($0.id)) }
                        }.labelsHidden().pickerStyle(.menu)
                        if model.isTestingMicrophone {
                            HStack(spacing: 8) {
                                Circle().fill(model.audio.meterLevel > 0.03 ? HearlyColor.lime : .gray).frame(width: 8, height: 8)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.1))
                                        Capsule().fill(model.audio.meterLevel > 0.85 ? Color.orange : HearlyColor.lime)
                                            .frame(width: geo.size.width * CGFloat(min(1.0, max(0.02, model.audio.meterLevel))))
                                    }
                                }
                                .frame(height: 6)
                                Text(model.audio.meterLevel > 0.85 ? "Loud" : model.audio.meterLevel > 0.05 ? "Good" : "Listening…")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(model.audio.meterLevel > 0.05 ? HearlyColor.lime : HearlyColor.muted)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            .padding(.top, 2)
                        }
                    }.padding(.top, 14)
                    LimeButton(title: "Continue", action: model.prepareTraining).disabled(model.profileName.trimmingCharacters(in: .whitespaces).isEmpty).padding(.top, 22)
                    Spacer(minLength: 0)
                }.padding(38).frame(width: 468, height: 420, alignment: .topLeading).background(GlassSurface())
            }.padding(.top, 44)
        }
    }
    private var recording: some View {
        VStack(spacing: 0) {
            Text("Read the phrase naturally. Keep your pace\nsteady and stay close to your normal speaking\nvoice.")
                .font(.system(size: 22)).foregroundStyle(HearlyColor.muted).lineSpacing(9).multilineTextAlignment(.center).padding(.top, 40)
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECORDING STATE").font(.system(size: 14)).tracking(2).foregroundStyle(HearlyColor.muted.opacity(0.75))
                        Text(model.busy ? "Preparing on-device recognition…" : model.phraseCaptured ? "Phrase captured" : model.audio.isCapturing ? "Listening to your voice" : "Ready to record")
                            .font(.system(size: 23, weight: .semibold))
                    }
                    Spacer()
                    Circle().fill(model.audio.isCapturing || model.phraseCaptured ? HearlyColor.lime : .gray).frame(width: 13, height: 13)
                }
                HearlyWaveform(level: model.audio.meterLevel, isActive: model.audio.isCapturing).background(GlassSurface(radius: 23))
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("PHRASE \(model.phraseIndex + 1) OF 3").font(.system(size: 15)).tracking(1).foregroundStyle(HearlyColor.muted.opacity(0.75))
                        Spacer()
                        Image(systemName: model.phraseCaptured ? "checkmark.circle" : "circle").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(model.phraseCaptured ? HearlyColor.lime : .gray.opacity(0.7))
                    }
                    highlightedPhrase.font(.system(size: 23, weight: .medium)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true).frame(minHeight: 68, alignment: .top)
                    HStack(spacing: 10) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index < model.phraseIndex || (index == model.phraseIndex && model.phraseCaptured) ? HearlyColor.lime : index == model.phraseIndex ? HearlyColor.lime.opacity(0.36) : .white.opacity(0.1)).frame(height: 7)
                        }
                    }
                }.padding(24).background(GlassSurface(radius: 24))
                VStack(spacing: 16) {
                    HStack { Text("PROGRESS").tracking(2); Spacer(); Text("\(Int(model.trainingProgress * 100))%").monospacedDigit().tracking(2) }
                        .font(.system(size: 14)).foregroundStyle(HearlyColor.muted.opacity(0.75))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(HearlyColor.lime).frame(width: geometry.size.width * model.trainingProgress)
                        }
                    }.frame(height: 8)
                }.padding(.top, 4)
            }.padding(26).frame(width: 578).background(GlassSurface(radius: 25)).padding(.top, 29)
            if model.phraseCaptured {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(HearlyColor.lime)
                        Text(String(format: "%.1fs audio captured · Clear voiceprint ready", model.lastCapturedDuration > 0 ? model.lastCapturedDuration : 2.5))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HearlyColor.lime)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(GlassSurface(radius: 12))

                    LimeButton(title: model.phraseIndex == 2 ? "Complete Enrollment" : "Next Phrase", action: model.nextPhrase).frame(width: 360)
                    Button {
                        model.rerecordCurrentPhrase()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Re-record this phrase")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HearlyColor.muted)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.top, 24)
                .padding(.bottom, 36)
            } else {
                VStack(spacing: 14) {
                    if model.audio.isCapturing {
                        HStack(spacing: 16) {
                            Button {
                                model.cancelPhrase()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle")
                                    Text("Cancel")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HearlyColor.muted)
                                .frame(width: 100, height: 44)
                                .background(GlassSurface(radius: 22))
                            }
                            .buttonStyle(.plain)

                            if model.audio.voicedSeconds >= 2.0 {
                                LimeButton(title: "Done Speaking · Capture", action: model.capturePhrase)
                                    .frame(width: 260)
                            } else {
                                Button {
                                    model.capturePhrase()
                                } label: {
                                    MicrophoneOrb(recording: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(model.busy)
                            }
                        }
                        .padding(.top, 4)

                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                Circle().fill(model.audio.voicedSeconds >= 2.0 ? HearlyColor.lime : .orange).frame(width: 8, height: 8)
                                Text(String(format: "%.1fs spoken (min 2.0s)", model.audio.voicedSeconds))
                                    .font(.system(size: 14, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(model.audio.voicedSeconds >= 2.0 ? HearlyColor.lime : HearlyColor.muted)
                                if model.phraseIsRecognized {
                                    Text("· All words detected")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(HearlyColor.lime)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(GlassSurface(radius: 12))

                            if model.audio.meterLevel > 0.9 {
                                Text("Microphone volume is very high — speak softer or step back")
                                    .font(.system(size: 13)).foregroundStyle(.orange)
                            } else if model.audio.voicedSeconds < 1.0 && model.audio.meterLevel < 0.04 {
                                Text("Speak clearly into your microphone")
                                    .font(.system(size: 13)).foregroundStyle(HearlyColor.muted)
                            } else {
                                Text(model.audio.voicedSeconds >= 2.0 ? "Click Done Speaking when finished" : "Read the highlighted phrase aloud")
                                    .font(.system(size: 14)).foregroundStyle(HearlyColor.muted)
                            }
                        }
                    } else {
                        Button {
                            model.recordPhrase()
                        } label: { MicrophoneOrb(recording: false) }
                            .buttonStyle(.plain).disabled(model.busy || model.audio.isStarting).padding(.top, 4)
                            .accessibilityLabel("Record phrase")
                        Text("Click the microphone and read the phrase aloud")
                            .font(.system(size: 16)).foregroundStyle(HearlyColor.muted)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
        }
    }
    private var highlightedPhrase: Text {
        let words = model.currentPhrase.split(separator: " ")
        return words.enumerated().reduce(Text("")) { result, item in
            let highlighted = model.phraseCaptured || item.offset < model.phraseMatchedWords
            return result + Text((item.offset == 0 ? "" : " ") + String(item.element))
                .foregroundColor(highlighted ? HearlyColor.lime : .white)
        }
    }
    private var completed: some View {
        VStack(spacing: 0) {
            Text("STEP 3 OF 3").font(.system(size: 16)).tracking(3).foregroundStyle(HearlyColor.muted).padding(.top, 24)
            VoiceMark(size: 80).frame(width: 120, height: 116).background(GlassSurface(accent: true, radius: 26)).padding(.top, 55)
            Text("Voice Enrolled").font(.system(size: 46, weight: .semibold)).padding(.top, 26)
            Text("Your profile is ready. Hearly can now focus on\nyour voice during listening sessions.")
                .font(.system(size: 22)).foregroundStyle(HearlyColor.muted).multilineTextAlignment(.center).lineSpacing(9).padding(.top, 16)
            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle").font(.system(size: 82, weight: .ultraLight)).foregroundStyle(HearlyColor.lime).padding(.top, 33)
                Text("Enrollment Complete").font(.system(size: 25, weight: .semibold)).padding(.top, 22)
                Text("Your voice sample has been captured\nand your profile is ready to use.").font(.system(size: 21)).foregroundStyle(HearlyColor.muted).multilineTextAlignment(.center).lineSpacing(9).fixedSize(horizontal: false, vertical: true).padding(.top, 14).padding(.bottom, 34)
            }.frame(width: 600).background(GlassSurface(accent: true, radius: 23)).padding(.top, 30)

            VStack(spacing: 14) {
                Text("VERIFY YOUR VOICEPRINT").font(.system(size: 13, weight: .semibold)).tracking(2).foregroundStyle(HearlyColor.muted)
                if model.testing {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().fill(HearlyColor.lime).frame(width: 8, height: 8)
                            Text("Speak a sentence into your microphone…").font(.system(size: 16, weight: .medium))
                        }
                        HearlyWaveform(level: model.audio.meterLevel, isActive: true).frame(height: 52).background(GlassSurface(radius: 16))
                        Button("Stop & Check Score") { model.toggleVerification() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HearlyColor.lime)
                            .padding(.top, 4)
                    }
                } else if let score = model.verificationScore {
                    HStack(spacing: 12) {
                        Image(systemName: score >= model.threshold ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(score >= model.threshold ? HearlyColor.lime : Color.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(score >= model.threshold ? "Voice Verified · \(Int(score * 100))% Match" : "Score \(Int(score * 100))% (Threshold \(Int(model.threshold * 100))%)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(score >= model.threshold ? HearlyColor.lime : Color.orange)
                            Text(score >= model.threshold ? "Your voiceprint recognized you with high confidence." : "Speak a little louder or re-enroll for closer match.")
                                .font(.system(size: 13)).foregroundStyle(HearlyColor.muted)
                        }
                        Spacer()
                        Button("Test Again") { model.toggleVerification() }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HearlyColor.muted)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(GlassSurface(accent: score >= model.threshold, radius: 18))
                } else {
                    Button {
                        model.toggleVerification()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mic.fill").font(.system(size: 15))
                            Text("Test Voice Match").font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(HearlyColor.lime)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(GlassSurface(accent: true, radius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            }
            .frame(width: 600)
            .padding(.top, 24)

            LimeButton(title: "Start Using Hearly", solid: true) {
                if model.testing { model.stopAudio() }
                model.page = .home
            }.frame(width: 450).padding(.top, 28).padding(.bottom, 40)
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppViewModel
    @State private var search = ""
    @State private var filter = "All"
    @State private var newest = true
    private var records: [TranscriptRecord] {
        let calendar = Calendar.current
        return model.transcripts.filter { record in
            let searchMatches = search.isEmpty || record.text.localizedCaseInsensitiveContains(search)
            let dateMatches: Bool
            switch filter {
            case "Today": dateMatches = calendar.isDateInToday(record.date)
            case "This Week": dateMatches = calendar.isDate(record.date, equalTo: Date(), toGranularity: .weekOfYear)
            case "This Month": dateMatches = calendar.isDate(record.date, equalTo: Date(), toGranularity: .month)
            default: dateMatches = true
            }
            return searchMatches && dateMatches
        }.sorted { newest ? $0.date > $1.date : $0.date < $1.date }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 26) {
                    Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(HearlyColor.lime).frame(width: 67, height: 67).background(GlassSurface(accent: true, radius: 25))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("History").font(.system(size: 42, weight: .bold))
                        Text("All your filtered conversations in English.").font(.system(size: 20)).foregroundStyle(HearlyColor.muted)
                    }
                    Spacer()
                    HStack(spacing: 20) { Image(systemName: "magnifyingglass").font(.system(size: 24)); TextField("Search transcripts...", text: $search) }
                        .foregroundStyle(HearlyColor.muted).textFieldStyle(.plain).font(.system(size: 18)).padding(.horizontal, 24).frame(width: 384, height: 58).background(GlassSurface(radius: 31))
                }
                HStack(spacing: 18) {
                    ForEach(["All", "Today", "This Week", "This Month"], id: \.self) { value in
                        Button(value) { filter = value }.font(.system(size: 18)).buttonStyle(.plain).padding(.horizontal, 28).frame(height: 49)
                            .foregroundStyle(filter == value ? .white : HearlyColor.muted).background(GlassSurface(accent: filter == value, radius: 26))
                    }
                    Spacer()
                    Button { newest.toggle() } label: {
                        HStack(spacing: 15) { Image(systemName: "arrow.up.arrow.down"); Text(newest ? "Newest" : "Oldest"); Image(systemName: "chevron.down") }
                            .font(.system(size: 18)).padding(.horizontal, 20).frame(height: 49).background(GlassSurface(radius: 19))
                    }.buttonStyle(.plain).foregroundStyle(HearlyColor.muted)
                }.padding(.top, 45).padding(.bottom, 18)
                if !records.isEmpty {
                    LazyVStack(spacing: 16) {
                        ForEach(records) { record in
                            HearlyCard {
                                HStack {
                                    Label(record.date.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.text").foregroundStyle(HearlyColor.muted)
                                    Spacer()
                                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string) }.buttonStyle(.plain)
                                }.font(.system(size: 16))
                                Text(record.text).font(.system(size: 20)).lineSpacing(7).textSelection(.enabled)
                            }
                        }
                    }
                }
            }.padding(.leading, 54).padding(.trailing, 28).padding(.top, 91).padding(.bottom, 35)
        }.scrollIndicators(.hidden)
    }
}
