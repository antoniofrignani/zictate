//
//  AudioCaptureService.swift
//  Zictate
//
//  Created by Codex on 12/02/26.
//

import AVFoundation
import Foundation

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let syncQueue = DispatchQueue(label: "zictate.audio.capture.sync")

    private var capturedSamples: [Float] = []
    private var capturedSampleRate: Int = 16_000
    private var isRunning = false
    private var onFrameUpdate: (([Float]) -> Void)?
    private var lastFrameEmissionTime: TimeInterval = 0

    func start(onFrameUpdate: (([Float]) -> Void)? = nil) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        capturedSampleRate = Int(format.sampleRate)

        syncQueue.sync {
            capturedSamples.removeAll(keepingCapacity: true)
            self.onFrameUpdate = onFrameUpdate
            self.lastFrameEmissionTime = 0
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channelData = buffer.floatChannelData?.pointee else { return }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            let emissionTime = Date().timeIntervalSinceReferenceDate

            self.syncQueue.async {
                self.capturedSamples.append(contentsOf: samples)

                let shouldEmit = (emissionTime - self.lastFrameEmissionTime) >= (1.0 / 90.0)
                guard shouldEmit else { return }
                self.lastFrameEmissionTime = emissionTime

                guard let onFrameUpdate = self.onFrameUpdate else { return }
                DispatchQueue.main.async {
                    onFrameUpdate(samples)
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() -> (samples: [Float], sampleRate: Int) {
        guard isRunning else { return ([], capturedSampleRate) }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        var snapshot: [Float] = []
        syncQueue.sync {
            snapshot = capturedSamples
            capturedSamples.removeAll(keepingCapacity: false)
            onFrameUpdate = nil
            lastFrameEmissionTime = 0
        }
        return (snapshot, capturedSampleRate)
    }
}
