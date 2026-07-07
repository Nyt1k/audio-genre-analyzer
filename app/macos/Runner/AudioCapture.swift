import Accelerate
import AVFoundation
import Cocoa
import FlutterMacOS
import ScreenCaptureKit

// Captures system (or single-app) audio via ScreenCaptureKit and streams
// mono Float32 PCM to Dart. Audio is accumulated on the capture queue and
// flushed in ~100ms batches so the platform channel is not hammered by
// every 10ms sample buffer.
@available(macOS 13.0, *)
class AudioCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate, FlutterStreamHandler {
    static let sampleRate = 48000
    private static let flushFrames = 4800 // 100ms at 48kHz

    private var stream: SCStream?
    private var eventSink: FlutterEventSink?
    private let captureQueue = DispatchQueue(label: "audio.capture")

    // touched only on captureQueue
    private var accumulator: [Float32] = []
    private var monoScratch: [Float32] = []

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Method channel handlers

    func listApps(result: @escaping FlutterResult) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "content", message: error.localizedDescription, details: nil))
                    return
                }
                let apps = (content?.applications ?? [])
                    .filter { !$0.applicationName.isEmpty }
                    .map { ["pid": Int($0.processID), "name": $0.applicationName] }
                    .sorted { ($0["name"] as! String) < ($1["name"] as! String) }
                result(apps)
            }
        }
    }

    func start(pid: Int?, result: @escaping FlutterResult) {
        stopStream()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else { return }
            guard error == nil, let content = content, let display = content.displays.first else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "content",
                                        message: error?.localizedDescription ?? "no display",
                                        details: nil))
                }
                return
            }

            let filter: SCContentFilter
            if let pid = pid,
               let app = content.applications.first(where: { Int($0.processID) == pid }) {
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Self.sampleRate
            config.channelCount = 1
            // video output is not attached, but the stream wants a sane config
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            do {
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.captureQueue)
                stream.startCapture { err in
                    DispatchQueue.main.async {
                        if let err = err {
                            result(FlutterError(code: "start", message: err.localizedDescription, details: nil))
                        } else {
                            self.stream = stream
                            result(true)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    func stop(result: @escaping FlutterResult) {
        stopStream()
        result(true)
    }

    private func stopStream() {
        stream?.stopCapture()
        stream = nil
        captureQueue.async { [weak self] in
            self?.accumulator.removeAll(keepingCapacity: false)
            self?.monoScratch.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - SCStreamOutput (called on captureQueue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            let buffers = Array(audioBufferList)
            guard let first = buffers.first, let firstData = first.mData else { return }
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float32>.size
            guard frames > 0 else { return }

            if buffers.count == 1 {
                let ptr = firstData.assumingMemoryBound(to: Float32.self)
                accumulator.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frames))
            } else {
                mixToMono(buffers, frames: frames)
            }
            if accumulator.count >= Self.flushFrames {
                flush()
            }
        }
    }

    // averages deinterleaved channels into monoScratch and appends it
    private func mixToMono(_ buffers: [AudioBuffer], frames: Int) {
        if monoScratch.count < frames {
            monoScratch = [Float32](repeating: 0, count: frames)
        }
        monoScratch.withUnsafeMutableBufferPointer { scratch in
            vDSP_vclr(scratch.baseAddress!, 1, vDSP_Length(frames))
            for buffer in buffers {
                guard let p = buffer.mData?.assumingMemoryBound(to: Float32.self) else { continue }
                vDSP_vadd(scratch.baseAddress!, 1, p, 1, scratch.baseAddress!, 1, vDSP_Length(frames))
            }
            var scale = 1 / Float32(buffers.count)
            vDSP_vsmul(scratch.baseAddress!, 1, &scale, scratch.baseAddress!, 1, vDSP_Length(frames))
        }
        accumulator.append(contentsOf: monoScratch[0..<frames])
    }

    private func flush() {
        let data = accumulator.withUnsafeBufferPointer { Data(buffer: $0) }
        accumulator.removeAll(keepingCapacity: true)
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(FlutterStandardTypedData(bytes: data))
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(FlutterError(code: "stream",
                                          message: error.localizedDescription,
                                          details: nil))
            self?.stream = nil
        }
    }
}

@available(macOS 13.0, *)
func registerAudioCapture(with messenger: FlutterBinaryMessenger) {
    let manager = AudioCaptureManager()

    let methods = FlutterMethodChannel(name: "genre/capture", binaryMessenger: messenger)
    methods.setMethodCallHandler { call, result in
        switch call.method {
        case "listApps":
            manager.listApps(result: result)
        case "start":
            let args = call.arguments as? [String: Any]
            manager.start(pid: args?["pid"] as? Int, result: result)
        case "stop":
            manager.stop(result: result)
        case "sampleRate":
            result(AudioCaptureManager.sampleRate)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    let events = FlutterEventChannel(name: "genre/audio", binaryMessenger: messenger)
    events.setStreamHandler(manager)
}
