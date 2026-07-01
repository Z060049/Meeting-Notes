import Foundation

public final class InactivityMonitor: @unchecked Sendable {
    private let timeout: TimeInterval
    private let threshold: Float
    private let onTimeout: () -> Void
    private var timer: DispatchSourceTimer?
    private var lastActivityAt: Date
    private let queue = DispatchQueue(label: "com.autoscribe.inactivity-monitor")

    public init(
        timeout: TimeInterval,
        threshold: Float = 0.01,
        onTimeout: @escaping () -> Void
    ) {
        self.timeout = timeout
        self.threshold = threshold
        self.onTimeout = onTimeout
        self.lastActivityAt = Date()
    }

    public func start() {
        queue.async {
            self.lastActivityAt = Date()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.timeout, repeating: 5)
            timer.setEventHandler { [weak self] in
                self?.checkTimeout()
            }
            timer.resume()
            self.timer = timer
        }
    }

    public func recordAudioLevel(_ level: Float) {
        guard level >= threshold else {
            return
        }

        queue.async {
            self.lastActivityAt = Date()
        }
    }

    public func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    public func restart() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
        start()
    }

    private func checkTimeout() {
        guard Date().timeIntervalSince(lastActivityAt) >= timeout else {
            return
        }
        timer?.cancel()
        timer = nil
        onTimeout()
    }
}
