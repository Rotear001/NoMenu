import AppKit
@preconcurrency import ScreenCaptureKit
import CoreImage
import Combine
import OSLog

@MainActor
final class LiveArtworkCapture {
    struct Request: Equatable {
        let displayID: CGDirectDisplayID
        let strip: CGRect
        let frames: [UUID: CGRect]
        let fps: LiveArtworkFrameRate
    }
    var onFrames: (([UUID: CGImage]) -> Void)?
    var onFailure: (() -> Void)?
    var permissionIsGranted: () -> Bool = { false }
    private var request: Request?
    private var generation = UUID()
    private var transition: Task<Void, Never>?
    private var stream: SCStream?
    private var output: ArtworkStreamOutput?
    private let logger = Logger(subsystem: "com.nomenu.utility", category: "LiveArtwork")

    func update(_ next: Request?) {
        guard request != next else { return }
        request = next
        generation = UUID()
        let token = generation
        let previous = transition
        // Serialize stop/start even when content lookup/start is in flight.
        transition = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if let stream = self.stream {
                try? await stream.stopCapture()
                self.stream = nil
                self.output = nil
                logger.notice("capture stopped; streams=0 crops=0")
            }
            guard token == generation, let next, permissionIsGranted() else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard token == generation,
                      let display = content.displays.first(where: { $0.displayID == next.displayID }) else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let scale = CGFloat(CGDisplayPixelsWide(next.displayID)) / display.frame.width
                config.sourceRect = next.strip.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                config.width = max(1, Int(next.strip.width * scale))
                config.height = max(1, Int(next.strip.height * scale))
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(next.fps.framesPerSecond))
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                let sink = ArtworkStreamOutput(strip: next.strip, frames: next.frames, failed: { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.update(nil)
                    self.onFailure?()
                }) { [weak self] images in
                    guard let self, self.generation == token else { return }
                    self.onFrames?(images)
                }
                let capture = SCStream(filter: filter, configuration: config, delegate: sink)
                try capture.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
                self.output = sink
                self.stream = capture
                try await capture.startCapture()
                logger.notice("capture started; streams=1 crops=\(next.frames.count) fps=\(next.fps.framesPerSecond)")
                if token != generation {
                    try? await capture.stopCapture()
                    self.stream = nil
                    self.output = nil
                }
            } catch {
                if let stream = self.stream { try? await stream.stopCapture() }
                self.stream = nil
                self.output = nil
                if token == generation { request = nil; onFailure?() }
            }
        }
    }
}

/// A single utility queue and a one-batch main-actor mailbox bound frame work.
private final class ArtworkStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.nomenu.utility.live-artwork", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let strip: CGRect
    private let frames: [UUID: CGRect]
    private let deliver: @MainActor @Sendable ([UUID: CGImage]) -> Void
    private let failed: @MainActor @Sendable () -> Void
    private let lock = NSLock()
    private var pending = false
    init(strip: CGRect, frames: [UUID: CGRect], failed: @escaping @MainActor @Sendable () -> Void,
         deliver: @escaping @MainActor @Sendable ([UUID: CGImage]) -> Void) {
        self.strip = strip
        self.frames = frames
        self.deliver = deliver
        self.failed = failed
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [failed] in failed() }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        if pending { lock.unlock(); return }
        pending = true
        lock.unlock()
        let source = CIImage(cvPixelBuffer: buffer)
        let sx = source.extent.width / strip.width
        let sy = source.extent.height / strip.height
        var images: [UUID: CGImage] = [:]
        for (id, frame) in frames where strip.contains(frame) {
            let crop = CGRect(x: (frame.minX - strip.minX) * sx,
                              y: source.extent.height - (frame.maxY - strip.minY) * sy,
                              width: frame.width * sx, height: frame.height * sy).integral
            if let image = context.createCGImage(source, from: crop) { images[id] = image }
        }
        Task { @MainActor [self, images] in
            deliver(images)
            finishDelivery()
        }
    }
    private func finishDelivery() {
        lock.lock(); pending = false; lock.unlock()
    }
}

@MainActor
final class LiveArtworkImage: ObservableObject {
    struct Acceptance {
        let fingerprint: String
        let published: Bool
    }
    private(set) var lastCaptureTimestamp: Date?
    private(set) var lastPublicationTimestamp: Date?
    @Published private(set) var image: NSImage?
    private var pixels: Data?
    @discardableResult
    func accept(_ frame: CGImage) -> Acceptance {
        lastCaptureTimestamp = Date()
        guard let bytes = frame.dataProvider?.data else {
            return Acceptance(fingerprint: "unavailable", published: false)
        }
        let data = bytes as Data
        let fingerprint = Self.fingerprint(data)
        guard pixels != data else { return Acceptance(fingerprint: fingerprint, published: false) }
        pixels = data
        lastPublicationTimestamp = Date()
        image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        return Acceptance(fingerprint: fingerprint, published: true)
    }
    func clear() { pixels = nil; image = nil; lastCaptureTimestamp = nil; lastPublicationTimestamp = nil }

    private static func fingerprint(_ data: Data) -> String {
        var hash: UInt32 = 2_166_136_261
        let stride = max(1, data.count / 256)
        var index = 0
        while index < data.count {
            hash = (hash ^ UInt32(data[index])) &* 16_777_619
            index += stride
        }
        hash = (hash ^ UInt32(data.count & 0xffff_ffff)) &* 16_777_619
        return String(format: "%08X", hash)
    }
}

/// Identity selects the consumer; independently verified compositor evidence
/// selects geometry. Never reinterpret an off-screen AX rectangle as pixels.
@MainActor
enum ArtworkSourceMapping {
    static func sources(for consumers: [MenuBarItem], strip: CGRect, screen: NSScreen,
                        windows: [[String: Any]]) -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        for item in consumers {
            guard let frame = item.accessibilityFrame, !frame.isEmpty, strip.contains(frame) else { continue }
            // These classification reasons positively establish an occluder.
            guard !item.visibilityReason.contains("active application's menu extent"),
                  !item.visibilityReason.contains("unsafe/notch area") else { continue }
            if screen.safeAreaInsets.top > 0 {
                let safeLeft = screen.auxiliaryTopLeftArea?.width ?? 0
                let safeRight = screen.auxiliaryTopRightArea?.width ?? 0
                guard frame.maxX <= strip.minX + safeLeft || frame.minX >= strip.maxX - safeRight else { continue }
            }
            let verified = windows.contains { window in
                guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == item.processIdentifier,
                      (window[kCGWindowIsOnscreen as String] as? Bool) == true,
                      (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                      let raw = window[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
                return abs(bounds.minX - frame.minX) < 1 && abs(bounds.minY - frame.minY) < 1
                    && abs(bounds.width - frame.width) < 1 && abs(bounds.height - frame.height) < 1
            }
            if verified { result[item.id] = frame }
        }
        return result
    }
}
