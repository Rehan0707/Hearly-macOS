import AVFoundation

final class VoiceIsolationProcessor {
    var enabled = true
    var threshold: Float = 0.012

    func process(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }

        var energy: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = channelData[channel][frame]
                energy += sample * sample
            }
        }
        let sampleCount = Float(frameCount * channelCount)
        let level = sqrt(energy / sampleCount)

        if enabled && level < threshold {
            for channel in 0..<channelCount {
                channelData[channel].update(repeating: 0, count: frameCount)
            }
        }

        return min(1, level).rounded(toPlaces: 3)
    }
}

private extension Float {
    func rounded(toPlaces places: Int) -> Float {
        let power = powf(10, Float(places))
        return (self * power).rounded() / power
    }
}
