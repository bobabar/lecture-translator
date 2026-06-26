@preconcurrency import AVFoundation
import Foundation

enum CaptureError: LocalizedError {
    case noInputDevice
    case microphoneDenied
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone or audio input device is available. Connect an input device, then try again."
        case .microphoneDenied:
            return "Microphone access is required to translate live speech."
        case .unsupportedAudioFormat:
            return "The current microphone format could not be read as floating point audio."
        }
    }
}

final class AudioCaptureService: @unchecked Sendable {
    private let silenceRMSThreshold: Float = 0.0035
    private let workQueue = DispatchQueue(label: "LectureTranslator.AudioCapture")

    private var engine: AVAudioEngine?
    private var chunks: [[Float]] = []
    private var sampleCount = 0
    private var inputSampleRate: Double = 48_000
    private var profile = LatencyProfile.balanced
    private var onChunk: ((Data) -> Void)?
    private var onSkipped: (() -> Void)?
    private var isCapturing = false

    func start(
        profile: LatencyProfile,
        onChunk: @escaping (Data) -> Void,
        onSkipped: @escaping () -> Void
    ) throws {
        try ensureMicrophoneAccess()

        stop(flush: false)

        self.profile = profile
        self.onChunk = onChunk
        self.onSkipped = onSkipped
        self.chunks = []
        self.sampleCount = 0
        self.isCapturing = true

        let nextEngine = AVAudioEngine()
        let input = nextEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw CaptureError.unsupportedAudioFormat
        }
        inputSampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            self.workQueue.async {
                self.accept(samples: samples)
            }
        }

        nextEngine.prepare()
        try nextEngine.start()
        engine = nextEngine
    }

    func update(profile: LatencyProfile) {
        workQueue.async {
            self.profile = profile
        }
    }

    func stop(flush: Bool = true) {
        isCapturing = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        if flush {
            workQueue.async {
                self.flush(force: true)
                self.chunks = []
                self.sampleCount = 0
            }
        }
    }

    private func ensureMicrophoneAccess() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            try ensureAudioInputAvailable()
            return
        case .notDetermined:
            try ensureAudioInputAvailable()
            let semaphore = DispatchSemaphore(value: 0)
            let result = PermissionResult()
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                result.granted = allowed
                semaphore.signal()
            }
            semaphore.wait()
            if !result.granted {
                throw CaptureError.microphoneDenied
            }
            try ensureAudioInputAvailable()
        default:
            throw CaptureError.microphoneDenied
        }
    }

    private func ensureAudioInputAvailable() throws {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw CaptureError.noInputDevice
        }
    }

    private func accept(samples: [Float]) {
        guard isCapturing else { return }
        guard !samples.isEmpty else { return }
        chunks.append(samples)
        sampleCount += samples.count

        if Double(sampleCount) >= inputSampleRate * profile.seconds {
            flush(force: false)
        }
    }

    private func flush(force: Bool) {
        guard sampleCount > 0 else { return }

        let merged = chunks.flatMap { $0 }
        let overlapSamples = Int(profile.overlap * inputSampleRate)
        let tail: [Float] = force || overlapSamples <= 0
            ? []
            : Array(merged.suffix(min(overlapSamples, merged.count)))

        chunks = tail.isEmpty ? [] : [tail]
        sampleCount = tail.count

        guard force || merged.count >= Int(inputSampleRate) else { return }

        if rms(merged) < silenceRMSThreshold {
            onSkipped?()
            return
        }

        let resampled = resampleTo16kHz(samples: merged, inputSampleRate: inputSampleRate)
        onChunk?(WAVEncoder.encode(samples: resampled))
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + ($1 * $1) }
        return sqrt(sum / Float(samples.count))
    }

    private func resampleTo16kHz(samples: [Float], inputSampleRate: Double) -> [Float] {
        let outputSampleRate = 16_000.0
        guard inputSampleRate != outputSampleRate else { return samples }

        let ratio = inputSampleRate / outputSampleRate
        let outputCount = Int(Double(samples.count) / ratio)
        guard outputCount > 0 else { return [] }

        return (0..<outputCount).map { index in
            let sourceIndex = Double(index) * ratio
            let before = Int(sourceIndex)
            let after = min(before + 1, samples.count - 1)
            let weight = Float(sourceIndex - Double(before))
            return samples[before] * (1 - weight) + samples[after] * weight
        }
    }
}

private final class PermissionResult: @unchecked Sendable {
    var granted = false
}
