import Foundation
import AVFoundation
import Network
import Combine

@MainActor
final class AudioReceiver: ObservableObject {
    @Published private(set) var status = "正在初始化音频..."
    @Published private(set) var isRunning = false

    private let port: NWEndpoint.Port = 49152
    private var listener: NWListener?
    private var connection: NWConnection?
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private var pending = Data()
    private let parseQueue = DispatchQueue(label: "com.iphonespeaker.parse")

    func start() {
        stopListenerOnly()
        configureAudio()
        do {
            let params = NWParameters.tcp
            // usbmux/iproxy connects to the device-side TCP port over USB.
            let newListener = try NWListener(using: params, on: port)
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { @MainActor in self.accept(connection) }
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.status = "Listening on :49152 · 等待 USB 主机连接"
                        self?.isRunning = true
                    case .failed(let error):
                        self?.status = "监听失败：\(error.localizedDescription)"
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener = newListener
            newListener.start(queue: DispatchQueue(label: "com.iphonespeaker.listener"))
        } catch {
            status = "无法启动监听：\(error.localizedDescription)"
        }
    }

    private func configureAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)
            if !audioEngine.attachedNodes.contains(player) {
                audioEngine.attach(player)
                audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFormat)
            }
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            status = "音频初始化失败：\(error.localizedDescription)"
        }
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        pending.removeAll(keepingCapacity: true)
        status = "USB 主机已连接 · 正在接收音频"
        newConnection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.status = "连接中断：\(error.localizedDescription)" }
            } else if case .cancelled = state {
                Task { @MainActor in self?.status = "等待 USB 主机连接" }
            }
        }
        newConnection.start(queue: DispatchQueue(label: "com.iphonespeaker.connection"))
        receiveNext(from: newConnection)
    }

    private func receiveNext(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.parseQueue.async {
                    self.pending.append(data)
                    self.consumeFrames()
                }
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receiveNext(from: connection)
        }
    }

    // Wire protocol: uint32 big-endian byte count, followed by interleaved PCM16 LE stereo.
    private func consumeFrames() {
        while pending.count >= 4 {
            let length = pending.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= 32 * 1024 else {
                pending.removeAll()
                return
            }
            let total = 4 + Int(length)
            guard pending.count >= total else { return }
            let payload = Data(pending[4..<total])
            pending.removeSubrange(0..<total)
            schedulePCM16(payload)
        }
    }

    private func schedulePCM16(_ data: Data) {
        let frameBytes = 4
        let frameCount = data.count / frameBytes
        guard frameCount > 0, frameCount * frameBytes == data.count else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                            frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        data.withUnsafeBytes { raw in
            guard let bytes = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for frame in 0..<frameCount {
                let left = Int16(littleEndian: bytes[frame * 2])
                let right = Int16(littleEndian: bytes[frame * 2 + 1])
                channels[0][frame] = Float(left) / 32768.0
                channels[1][frame] = Float(right) / 32768.0
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.audioEngine.isRunning {
                try? self.audioEngine.start()
            }
            if !self.player.isPlaying {
                self.player.play()
            }
            self.player.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    private func stopListenerOnly() {
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
    }
}
