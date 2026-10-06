import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        InAppSettingsView(model: model)
            .background(HearlyColor.canvas)
            .preferredColorScheme(.dark)
            .frame(width: 1100, height: 900)
    }
}

struct InAppSettingsView: View {
    @ObservedObject var model: AppViewModel
    @State private var removeVoice = false
    @State private var showPrivacy = false
    @State private var showLogs = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .padding(.bottom, 6)

                voiceProfileCard
                verificationCard
                audioDeviceCard
                preferencesCard
                privacyCard
                diagnosticsCard
            }
            .padding(.horizontal, 58)
            .padding(.top, 44)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(.white)
        .alert("Remove your voice profile?", isPresented: $removeVoice) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Voice", role: .destructive, action: model.removeVoice)
        } message: {
            Text("This deletes your enrolled voiceprint from this Mac. You will need to record the calibration phrases again to use Voice Focus.")
        }
        .alert("Local Privacy Guarantee", isPresented: $showPrivacy) {
            Button("Done") {}
        } message: {
            Text("Your voiceprint and transcripts are stored locally with Apple Keychain encryption. Audio is processed entirely on your Mac's Neural Engine / CPU and never leaves this computer. Hearly operates with zero network dependencies.")
        }
        .onDisappear {
            if model.testing { model.stopAudio() }
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 38, weight: .bold))
                .tracking(-0.8)
            Text("Manage your voice profile, audio input, and app preferences.")
                .font(.system(size: 18))
                .foregroundStyle(HearlyColor.muted)
        }
        .frame(height: 64, alignment: .topLeading)
    }

    // MARK: - Voice Profile & Management
    private var voiceProfileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "person", size: 50)
                SettingsRowText(title: "Voice Profile", subtitle: "Your enrolled voice identity")
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(model.profile == nil ? Color.orange : HearlyColor.lime).frame(width: 9, height: 9)
                    Text(model.profile == nil ? "NOT ENROLLED" : "ACTIVE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.profile == nil ? Color.orange : HearlyColor.lime)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background((model.profile == nil ? Color.orange : HearlyColor.lime).opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke((model.profile == nil ? Color.orange : HearlyColor.lime).opacity(0.3), lineWidth: 1))
            }

            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(model.profile == nil ? HearlyColor.muted : HearlyColor.lime)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Profile Name")
                        .font(.system(size: 13))
                        .foregroundStyle(HearlyColor.muted)
                    Text(model.profile?.name ?? "No voice enrolled yet")
                        .font(.system(size: 19, weight: .semibold))
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: model.beginTraining) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(model.profile == nil ? "Enroll Voice" : "Re-train Voice")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HearlyColor.lime)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(HearlyColor.lime.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HearlyColor.lime.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if model.profile != nil {
                        Button { removeVoice = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Remove")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.45))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .settingsSurface(radius: 16)
        }
        .padding(20)
        .settingsSurface()
    }

    // MARK: - Speaker Verification & Threshold
    private var verificationCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "waveform.badge.magnifyingglass", size: 50)
                SettingsRowText(title: "Voice Verification & Matching", subtitle: "Test voice recognition and fine-tune isolation sensitivity")
                Spacer()
                Text(model.testing ? "TESTING" : "READY")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.testing ? HearlyColor.lime : HearlyColor.muted)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(HearlyColor.lime.opacity(model.testing ? 0.15 : 0.05), in: Capsule())
            }

            VStack(spacing: 16) {
                // Threshold Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SIMILARITY THRESHOLD")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(HearlyColor.muted)
                        Spacer()
                        Text(String(format: "%.0f%% Match Required (%.2f)", model.threshold * 100, model.threshold))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(HearlyColor.lime)
                    }
                    Slider(value: $model.threshold, in: 0.35...0.85)
                        .tint(HearlyColor.lime)
                        .disabled(model.audio.isRunning)
                        .accessibilityLabel("Speaker match threshold")
                    Text("Higher values require closer voice match before audio passes. 55–70% recommended.")
                        .font(.system(size: 12))
                        .foregroundStyle(HearlyColor.muted)
                }
                .padding(16)
                .settingsSurface(radius: 16)

                // Live Test Section
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LIVE VOICE TEST")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(HearlyColor.muted)
                        if let score = model.verificationScore {
                            HStack(spacing: 8) {
                                Image(systemName: score >= model.threshold ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(score >= model.threshold ? HearlyColor.lime : Color.orange)
                                Text(score >= model.threshold
                                     ? "Verified · \(Int(score * 100))% Match"
                                     : "Score \(Int(score * 100))% — below threshold")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(score >= model.threshold ? HearlyColor.lime : Color.orange)
                            }
                        } else {
                            Text(model.testing ? "Listening… speak for 2–3 seconds" : "Test how accurately Hearly recognizes your voice")
                                .font(.system(size: 14))
                                .foregroundStyle(HearlyColor.muted)
                        }
                    }

                    Spacer()

                    if model.testing {
                        HearlyWaveform(level: model.audio.meterLevel, isActive: true)
                            .frame(width: 140, height: 38)
                            .background(GlassSurface(radius: 12))
                    }

                    Button(action: model.toggleVerification) {
                        HStack(spacing: 8) {
                            Image(systemName: model.testing ? "stop.fill" : "mic.fill")
                            Text(model.testing ? "Stop & Compare" : "Test Match")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.testing ? .white : HearlyColor.lime)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(model.testing ? Color.red.opacity(0.8) : HearlyColor.lime.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(model.testing ? Color.red : HearlyColor.lime.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy || model.profile == nil)
                }
                .padding(16)
                .settingsSurface(radius: 16)
            }
        }
        .padding(20)
        .settingsSurface()
    }

    // MARK: - Audio & Devices
    private var audioDeviceCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "mic", size: 50)
                SettingsRowText(title: "Audio & Input Devices", subtitle: "Configure microphone input and Hearly virtual driver")
                Spacer()
            }

            VStack(spacing: 12) {
                // Physical Microphone Picker Row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Microphone Input")
                            .font(.system(size: 16, weight: .semibold))
                        Text(model.selectedDeviceName)
                            .font(.system(size: 13))
                            .foregroundStyle(HearlyColor.muted)
                    }
                    Spacer()

                    Picker("", selection: $model.selectedInputDeviceID) {
                        Text("System default (\(CoreAudioDeviceManager.defaultInputDeviceName()))").tag(UInt32?.none)
                        ForEach(model.inputDevices) { device in
                            Text(device.name).tag(UInt32?.some(device.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280)
                    .disabled(model.audio.isRunning)

                    Button(action: model.refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(HearlyColor.muted)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh connected devices")
                }
                .padding(16)
                .settingsSurface(radius: 16)

                // Virtual Driver Status Row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Virtual Microphone Driver")
                            .font(.system(size: 16, weight: .semibold))
                        Text(model.virtualMicrophone.status.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(HearlyColor.muted)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: model.virtualMicrophone.status == .installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.virtualMicrophone.status == .installed ? HearlyColor.lime : Color.orange)
                        Text(model.virtualMicrophone.status.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(model.virtualMicrophone.status == .installed ? HearlyColor.lime : Color.orange)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.05), in: Capsule())

                    Button("Audio MIDI Setup") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.link)
                }
                .padding(16)
                .settingsSurface(radius: 16)
            }
        }
        .padding(20)
        .settingsSurface()
    }

    // MARK: - App Preferences
    private var preferencesCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "slider.horizontal.3", size: 50)
                SettingsRowText(title: "App Preferences", subtitle: "Meeting detection, transcripts, and global shortcuts")
                Spacer()
            }

            VStack(spacing: 0) {
                // Auto Detect Meetings
                HStack(spacing: 20) {
                    SettingsIcon(icon: "phone.connection", size: 44)
                    SettingsRowText(title: "Auto-Detect Meetings", subtitle: "Activate Voice Focus automatically when Zoom, Meet, or Teams connects", small: true)
                    Spacer()
                    SettingsSwitch(isOn: $model.autoStartInMeetings, label: "Auto-detect meetings")
                }
                .padding(.vertical, 14)

                Divider().background(Color.white.opacity(0.06))

                // Transcript
                HStack(spacing: 20) {
                    SettingsIcon(icon: "doc.text", size: 44)
                    SettingsRowText(title: "Live Transcripts", subtitle: "Save private transcript history locally on this Mac", small: true)
                    Spacer()
                    SettingsSwitch(isOn: Binding(get: { model.transcriptEnabled }, set: model.setTranscript), label: "Live transcripts")
                }
                .padding(.vertical, 14)

                Divider().background(Color.white.opacity(0.06))

                // Global Hotkey
                HStack(spacing: 20) {
                    SettingsIcon(icon: "keyboard", size: 44)
                    SettingsRowText(title: "Global System Hotkey", subtitle: "Toggle Voice Focus from any application with visual HUD", small: true)
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

                    SettingsSwitch(isOn: $model.hotkeyManager.isEnabled, label: "Global Hotkey")
                }
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 18)
            .settingsSurface(radius: 16)
        }
        .padding(20)
        .settingsSurface()
    }

    // MARK: - Privacy & Security
    private var privacyCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "lock.shield", size: 50, tint: HearlyColor.lime)
                SettingsRowText(title: "Privacy & Local Processing", subtitle: "All speech recognition runs 100% on your Mac")
                Spacer()
                Button { showPrivacy = true } label: {
                    Text("Details")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HearlyColor.lime)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(HearlyColor.lime.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Text("Hearly processes all microphone audio locally using on-device models. Voiceprints and transcripts are encrypted in local storage with Keychain-protected keys. No voice data or recordings are uploaded to the cloud.")
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(HearlyColor.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        .padding(20)
        .settingsSurface()
    }

    // MARK: - Diagnostics & Logs
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                SettingsIcon(icon: "terminal", size: 50)
                SettingsRowText(title: "Diagnostics & Activity", subtitle: "Recent system events and audio status")
                Spacer()
                Button { showLogs.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(showLogs ? "Hide Logs" : "Show Logs")
                        Image(systemName: showLogs ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HearlyColor.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if showLogs {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if model.logs.isEmpty {
                                Text("No activity logs recorded yet.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HearlyColor.muted)
                            } else {
                                ForEach(Array(model.logs.suffix(20).enumerated()), id: \.offset) { _, entry in
                                    Text(entry)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.85))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(height: 120)
                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    HStack {
                        Spacer()
                        Button("Clear Logs") { model.logs.removeAll() }
                            .font(.system(size: 12))
                            .foregroundStyle(HearlyColor.muted)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .settingsSurface()
    }
}

// MARK: - Reusable Settings Components
private struct SettingsRowText: View {
    let title: String
    let subtitle: String
    var small = false
    var titleColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 3 : 5) {
            Text(title).font(.system(size: small ? 16 : 19, weight: .semibold)).foregroundStyle(titleColor)
                .lineLimit(1)
            Text(subtitle).font(.system(size: small ? 13 : 14)).foregroundStyle(HearlyColor.muted)
                .lineLimit(2)
        }
    }
}

private struct SettingsIcon: View {
    let icon: String
    var size: CGFloat
    var tint: Color = Color(red: 0.77, green: 0.8, blue: 0.82)

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size > 45 ? 24 : 20, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.12), lineWidth: 1))
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? HearlyColor.lime : .white.opacity(0.08))
                    .overlay(Capsule().stroke(isOn ? HearlyColor.lime.opacity(0.7) : .white.opacity(0.12), lineWidth: 1.5))
                Circle()
                    .fill(LinearGradient(colors: isOn ? [.white, .white.opacity(0.95)] : [Color(red: 0.7, green: 0.72, blue: 0.76), Color(red: 0.64, green: 0.67, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            }
            .frame(width: 58, height: 32)
            .shadow(color: HearlyColor.lime.opacity(isOn ? 0.12 : 0), radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private extension View {
    func settingsSurface(radius: CGFloat = 20, tint: Color = Color.white.opacity(0.1), fill: Color = Color.white.opacity(0.02)) -> some View {
        background(LinearGradient(colors: [fill, Color.white.opacity(0.01), fill.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(tint, lineWidth: 1))
    }
}
