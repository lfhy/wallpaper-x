//
//  SystemAudioSpectrumService.swift
//  MyWallpaperX
//

import Foundation
import ScreenCaptureKit
import CoreMedia
import AudioToolbox

final class SystemAudioSpectrumService: NSObject {
    private let barCount: Int
    private let sampleQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.system-audio-spectrum", qos: .userInitiated)
    private var stream: SCStream?
    private var isEnabled = false
    private var smoothedLevels: [Float]

    var onLevels: (([Float]) -> Void)?

    init(barCount: Int) {
        self.barCount = barCount
        self.smoothedLevels = Array(repeating: 0, count: barCount)
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled

        if enabled {
            Task { [weak self] in
                await self?.startCaptureIfNeeded()
            }
        } else {
            Task { [weak self] in
                await self?.stopCapture()
            }
        }
    }

    @MainActor
    private func startCaptureIfNeeded() async {
        guard stream == nil else { return }

        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first else {
                onLevels?(Array(repeating: 0, count: barCount))
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.queueDepth = 1
            configuration.showsCursor = false
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
            self.stream = stream
        } catch {
            onLevels?(Array(repeating: 0, count: barCount))
        }
    }

    @MainActor
    private func stopCapture() async {
        guard let stream else {
            onLevels?(Array(repeating: 0, count: barCount))
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
        }
        self.stream = nil
        smoothedLevels = Array(repeating: 0, count: barCount)
        onLevels?(smoothedLevels)
    }

    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let monoSamples = monoSamples(from: sampleBuffer), !monoSamples.isEmpty else {
            return
        }

        let rawLevels = computeBarLevels(from: monoSamples)
        var nextLevels = Array(repeating: Float(0), count: barCount)

        for index in 0..<barCount {
            let incoming = rawLevels[index]
            let previous = smoothedLevels[index]
            if incoming >= previous {
                nextLevels[index] = previous * 0.34 + incoming * 0.66
            } else {
                nextLevels[index] = max(incoming, previous * 0.84)
            }
        }

        smoothedLevels = nextLevels
        onLevels?(nextLevels)
    }

    private func monoSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let streamDescription = streamDescriptionPointer.pointee
        let channelCount = max(1, Int(streamDescription.mChannelsPerFrame))
        let maxBuffers = max(1, channelCount)
        let audioBufferListSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size * max(0, maxBuffers - 1)
        let audioBufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { audioBufferListPointer.deallocate() }

        let bufferList = audioBufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let bufferListPointerView = UnsafeMutableAudioBufferListPointer(bufferList)
        let frameCount = max(1, CMSampleBufferGetNumSamples(sampleBuffer))
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0

        if isFloat {
            return monoFloatSamples(
                from: bufferListPointerView,
                channelCount: channelCount,
                frameCount: frameCount
            )
        }

        if isSignedInteger {
            return monoInt16Samples(
                from: bufferListPointerView,
                channelCount: channelCount,
                frameCount: frameCount
            )
        }

        return nil
    }

    private func monoFloatSamples(
        from buffers: UnsafeMutableAudioBufferListPointer,
        channelCount: Int,
        frameCount: Int
    ) -> [Float] {
        guard !buffers.isEmpty else { return [] }
        var mono = Array(repeating: Float(0), count: frameCount)

        if buffers.count == 1, let data = buffers[0].mData {
            let values = data.assumingMemoryBound(to: Float.self)
            for frameIndex in 0..<frameCount {
                var sum: Float = 0
                for channelIndex in 0..<channelCount {
                    sum += abs(values[frameIndex * channelCount + channelIndex])
                }
                mono[frameIndex] = sum / Float(channelCount)
            }
            return mono
        }

        for frameIndex in 0..<frameCount {
            var sum: Float = 0
            var contributingChannels = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Float.self)
                sum += abs(values[frameIndex])
                contributingChannels += 1
            }
            mono[frameIndex] = contributingChannels > 0 ? (sum / Float(contributingChannels)) : 0
        }
        return mono
    }

    private func monoInt16Samples(
        from buffers: UnsafeMutableAudioBufferListPointer,
        channelCount: Int,
        frameCount: Int
    ) -> [Float] {
        guard !buffers.isEmpty else { return [] }
        var mono = Array(repeating: Float(0), count: frameCount)
        let normalization = Float(Int16.max)

        if buffers.count == 1, let data = buffers[0].mData {
            let values = data.assumingMemoryBound(to: Int16.self)
            for frameIndex in 0..<frameCount {
                var sum: Float = 0
                for channelIndex in 0..<channelCount {
                    let sample = Float(values[frameIndex * channelCount + channelIndex]) / normalization
                    sum += abs(sample)
                }
                mono[frameIndex] = sum / Float(channelCount)
            }
            return mono
        }

        for frameIndex in 0..<frameCount {
            var sum: Float = 0
            var contributingChannels = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let values = data.assumingMemoryBound(to: Int16.self)
                sum += abs(Float(values[frameIndex]) / normalization)
                contributingChannels += 1
            }
            mono[frameIndex] = contributingChannels > 0 ? (sum / Float(contributingChannels)) : 0
        }
        return mono
    }

    private func computeBarLevels(from monoSamples: [Float]) -> [Float] {
        let sampleCount = monoSamples.count
        guard sampleCount > 0 else { return Array(repeating: 0, count: barCount) }

        let windowSize = min(sampleCount, max(barCount * 8, 512))
        let startIndex = max(0, sampleCount - windowSize)
        let window = Array(monoSamples[startIndex..<sampleCount])
        let chunkSize = max(1, window.count / barCount)

        return (0..<barCount).map { index in
            let chunkStart = min(window.count - 1, index * chunkSize)
            let chunkEnd = min(window.count, chunkStart + chunkSize)
            guard chunkStart < chunkEnd else { return 0 }

            var energy: Float = 0
            for sample in window[chunkStart..<chunkEnd] {
                energy += sample * sample
            }

            let rms = sqrt(energy / Float(chunkEnd - chunkStart))
            return min(1, pow(max(rms * 8.0, 0), 0.72))
        }
    }
}

extension SystemAudioSpectrumService: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        processAudioSampleBuffer(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.stream = nil
            if self?.isEnabled == true {
                await self?.startCaptureIfNeeded()
            } else {
                self?.onLevels?(Array(repeating: 0, count: self?.barCount ?? 0))
            }
        }
    }
}
