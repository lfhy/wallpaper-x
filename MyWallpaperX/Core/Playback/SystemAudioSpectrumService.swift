//
//  SystemAudioSpectrumService.swift
//  MyWallpaperX
//

import Foundation
import AudioToolbox
import CoreAudio
import Accelerate

final class SystemAudioSpectrumService: NSObject {
    private let barCount: Int
    private let fftSize: Int
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let sampleQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.system-audio-spectrum", qos: .utility)
    private let processingMinInterval: TimeInterval = 1.0 / 15.0
    private let processingGate = DispatchSemaphore(value: 1)
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapStreamFormat = AudioStreamBasicDescription()
    private var isEnabled = false
    private var smoothedLevels: [Float]
    private var lastProcessedAt: TimeInterval = 0
    private var adaptiveCeiling: Float = 0.12
    private var style: SystemAudioSpectrumStyle = .balanced
    private var sensitivity: SystemAudioSpectrumSensitivity = .normal

    private struct CopiedAudioFrame {
        let buffers: [Data]
        let streamDescription: AudioStreamBasicDescription
    }

    var onLevels: (([Float]) -> Void)?

    init(barCount: Int) {
        self.barCount = barCount
        self.fftSize = 1024
        self.log2FFTSize = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(self.log2FFTSize, FFTRadix(kFFTRadix2)) else {
            fatalError("Unable to create FFT setup for system audio spectrum")
        }
        self.fftSetup = fftSetup
        var window = Array(repeating: Float(0), count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        self.smoothedLevels = Array(repeating: 0, count: barCount)
        super.init()
    }

    deinit {
        stopCapture()
        vDSP_destroy_fftsetup(fftSetup)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled

        sampleQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                self.startCaptureIfNeeded()
            } else {
                self.stopCapture()
            }
        }
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity
    ) {
        self.style = style
        self.sensitivity = sensitivity
        resetAnalysis()
    }

    func resetAnalysis() {
        smoothedLevels = Array(repeating: 0, count: barCount)
        adaptiveCeiling = 0.12
        lastProcessedAt = 0
        onLevels?(smoothedLevels)
    }

    private func startCaptureIfNeeded() {
        guard tapID == kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown else { return }
        guard #available(macOS 14.2, *) else {
            onLevels?(Array(repeating: 0, count: barCount))
            return
        }

        do {
            let excludedProcessIDs = currentProcessObjectID().map { [$0] } ?? []
            let tapDescription = CATapDescription(
                stereoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "MyWallpaperX System Audio Spectrum"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted
            tapDescription.isProcessRestoreEnabled = false

            let createdTapID = try createProcessTap(description: tapDescription)
            tapID = createdTapID
            let tapUID = try fetchTapUID(for: createdTapID)
            tapStreamFormat = try fetchTapFormat(for: createdTapID)

            let aggregateID = try createAggregateDevice(tapUID: tapUID)
            aggregateDeviceID = aggregateID

            var createdIOProcID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateID,
                nil
            ) { [weak self] _, inInputData, _, _, _ in
                self?.processAudioBufferList(inInputData)
            }
            guard ioStatus == noErr, let createdIOProcID else {
                throw CaptureError.osStatus(ioStatus)
            }
            ioProcID = createdIOProcID

            let startStatus = AudioDeviceStart(aggregateID, createdIOProcID)
            guard startStatus == noErr else {
                throw CaptureError.osStatus(startStatus)
            }
        } catch {
            stopCapture()
            onLevels?(Array(repeating: 0, count: barCount))
        }
    }

    private func stopCapture() {
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }

        tapStreamFormat = AudioStreamBasicDescription()
        smoothedLevels = Array(repeating: 0, count: barCount)
        lastProcessedAt = 0
        onLevels?(smoothedLevels)
    }

    private func createProcessTap(description: CATapDescription) throws -> AudioObjectID {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapID
    }

    private func currentProcessObjectID() -> AudioObjectID? {
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }

        return processObjectID
    }

    private func createAggregateDevice(tapUID: CFString) throws -> AudioObjectID {
        let tapList: [[String: Any]] = [[
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: NSNumber(value: false)
        ]]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MyWallpaperX System Audio Spectrum",
            kAudioAggregateDeviceUIDKey: "com.songziqiang.MyWallpaperX.system-audio-spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: NSNumber(value: 1),
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceTapAutoStartKey: NSNumber(value: 1)
        ]

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &deviceID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return deviceID
    }

    private func fetchTapUID(for tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &tapUID) { pointer in
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapUID
    }

    private func fetchTapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &dataSize,
            &format
        )
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return format
    }

    private func processAudioBufferList(_ inputData: UnsafePointer<AudioBufferList>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessedAt >= processingMinInterval else { return }
        lastProcessedAt = now

        guard processingGate.wait(timeout: .now()) == .success else { return }

        guard let copiedFrame = copyAudioFrame(from: inputData, streamDescription: tapStreamFormat) else {
            processingGate.signal()
            return
        }

        sampleQueue.async { [weak self] in
            guard let self else { return }
            defer { self.processingGate.signal() }
            self.processCopiedAudioFrame(copiedFrame)
        }
    }

    private func copyAudioFrame(
        from bufferListPointer: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> CopiedAudioFrame? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPointer))
        guard !buffers.isEmpty else { return nil }

        let copiedBuffers = buffers.compactMap { buffer -> Data? in
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { return nil }
            return Data(bytes: data, count: Int(buffer.mDataByteSize))
        }

        guard !copiedBuffers.isEmpty else { return nil }
        return CopiedAudioFrame(buffers: copiedBuffers, streamDescription: streamDescription)
    }

    private func processCopiedAudioFrame(_ copiedFrame: CopiedAudioFrame) {
        guard let audioFrame = monoSamples(from: copiedFrame), !audioFrame.samples.isEmpty else {
            return
        }

        let rawLevels = computeBarLevels(from: audioFrame.samples, sampleRate: audioFrame.sampleRate)
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

    private func monoSamples(
        from copiedFrame: CopiedAudioFrame
    ) -> (samples: [Float], sampleRate: Float)? {
        guard !copiedFrame.buffers.isEmpty else { return nil }

        let streamDescription = copiedFrame.streamDescription
        let channelCount = max(1, Int(streamDescription.mChannelsPerFrame))
        let bytesPerFrame = max(1, Int(streamDescription.mBytesPerFrame))
        let sampleRate = Float(max(1, streamDescription.mSampleRate))
        let frameCount = max(1, copiedFrame.buffers[0].count / bytesPerFrame)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0

        if isFloat {
            return (
                samples: monoFloatSamples(
                    from: copiedFrame.buffers,
                    channelCount: channelCount,
                    frameCount: frameCount
                ),
                sampleRate: sampleRate
            )
        }

        if isSignedInteger {
            let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
            if bitsPerChannel <= 16 {
                return (
                    samples: monoInt16Samples(
                        from: copiedFrame.buffers,
                        channelCount: channelCount,
                        frameCount: frameCount
                    ),
                    sampleRate: sampleRate
                )
            }

            return (
                samples: monoInt32Samples(
                    from: copiedFrame.buffers,
                    channelCount: channelCount,
                    frameCount: frameCount
                ),
                sampleRate: sampleRate
            )
        }

        return nil
    }

    private func monoFloatSamples(
        from buffers: [Data],
        channelCount: Int,
        frameCount: Int
    ) -> [Float] {
        guard !buffers.isEmpty else { return [] }
        var mono = Array(repeating: Float(0), count: frameCount)

        if buffers.count == 1 {
            let values = buffers[0].withUnsafeBytes { $0.bindMemory(to: Float.self) }
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
                let values = buffer.withUnsafeBytes { $0.bindMemory(to: Float.self) }
                sum += abs(values[frameIndex])
                contributingChannels += 1
            }
            mono[frameIndex] = contributingChannels > 0 ? (sum / Float(contributingChannels)) : 0
        }
        return mono
    }

    private func monoInt16Samples(
        from buffers: [Data],
        channelCount: Int,
        frameCount: Int
    ) -> [Float] {
        guard !buffers.isEmpty else { return [] }
        var mono = Array(repeating: Float(0), count: frameCount)
        let normalization = Float(Int16.max)

        if buffers.count == 1 {
            let values = buffers[0].withUnsafeBytes { $0.bindMemory(to: Int16.self) }
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
                let values = buffer.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                sum += abs(Float(values[frameIndex]) / normalization)
                contributingChannels += 1
            }
            mono[frameIndex] = contributingChannels > 0 ? (sum / Float(contributingChannels)) : 0
        }
        return mono
    }

    private func monoInt32Samples(
        from buffers: [Data],
        channelCount: Int,
        frameCount: Int
    ) -> [Float] {
        guard !buffers.isEmpty else { return [] }
        var mono = Array(repeating: Float(0), count: frameCount)
        let normalization = Float(Int32.max)

        if buffers.count == 1 {
            let values = buffers[0].withUnsafeBytes { $0.bindMemory(to: Int32.self) }
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
                let values = buffer.withUnsafeBytes { $0.bindMemory(to: Int32.self) }
                sum += abs(Float(values[frameIndex]) / normalization)
                contributingChannels += 1
            }
            mono[frameIndex] = contributingChannels > 0 ? (sum / Float(contributingChannels)) : 0
        }
        return mono
    }

    private func computeBarLevels(from monoSamples: [Float], sampleRate: Float) -> [Float] {
        switch style {
        case .balanced:
            return computeBalancedBarLevels(from: monoSamples)
        case .banded:
            return computeFrequencyBandLevels(from: monoSamples, sampleRate: sampleRate)
        }
    }

    private func computeBalancedBarLevels(from monoSamples: [Float]) -> [Float] {
        let sampleCount = monoSamples.count
        guard sampleCount > 0 else { return Array(repeating: 0, count: barCount) }

        let windowSize = min(sampleCount, max(barCount * 18, 896))
        let startIndex = max(0, sampleCount - windowSize)
        let window = Array(monoSamples[startIndex..<sampleCount])
        let chunkSize = max(1, window.count / barCount)
        var rawLevels = Array(repeating: Float(0), count: barCount)

        for index in 0..<barCount {
            let chunkStart = min(window.count - 1, index * chunkSize)
            let chunkEnd = min(window.count, chunkStart + chunkSize)
            guard chunkStart < chunkEnd else { continue }

            var energy: Float = 0
            var peak: Float = 0
            for sample in window[chunkStart..<chunkEnd] {
                let absolute = abs(sample)
                energy += absolute * absolute
                peak = max(peak, absolute)
            }

            let rms = sqrt(energy / Float(chunkEnd - chunkStart))
            rawLevels[index] = rms * 0.78 + peak * 0.22
        }

        let peakLevel = rawLevels.max() ?? 0
        if peakLevel > adaptiveCeiling {
            adaptiveCeiling = adaptiveCeiling * 0.80 + peakLevel * 0.20
        } else {
            adaptiveCeiling = max(0.02, adaptiveCeiling * 0.972)
        }

        let noiseFloor = adaptiveCeiling * 0.07
        let normalizationRange = max(0.001, adaptiveCeiling - noiseFloor)
        let normalizedLevels = rawLevels.map { level in
            let normalized = max(0, level - noiseFloor) / normalizationRange
            return min(1, pow(normalized, 0.82))
        }

        let globalAverage = normalizedLevels.reduce(0, +) / Float(max(1, normalizedLevels.count))
        let sensitivityGain: Float
        switch sensitivity {
        case .soft:
            sensitivityGain = 0.86
        case .normal:
            sensitivityGain = 1.0
        case .lively:
            sensitivityGain = 1.16
        }

        return normalizedLevels.enumerated().map { index, level in
            let lowerBound = max(0, index - 1)
            let upperBound = min(normalizedLevels.count - 1, index + 1)
            let neighborSlice = normalizedLevels[lowerBound...upperBound]
            let neighborAverage = neighborSlice.reduce(0, +) / Float(neighborSlice.count)
            let mixedLevel = level * 0.52 + neighborAverage * 0.28 + globalAverage * 0.20
            let floorLift = globalAverage * 0.14
            return min(1, max(floorLift, pow(min(1, mixedLevel * sensitivityGain), 0.92)))
        }
    }

    private func computeFrequencyBandLevels(from monoSamples: [Float], sampleRate: Float) -> [Float] {
        let sampleCount = monoSamples.count
        guard sampleCount > 0 else { return Array(repeating: 0, count: barCount) }

        let samplesToCopy = min(sampleCount, fftSize)
        let sourceStart = sampleCount - samplesToCopy
        let destinationStart = fftSize - samplesToCopy
        var fftInput = Array(repeating: Float(0), count: fftSize)
        fftInput.replaceSubrange(
            destinationStart..<fftSize,
            with: monoSamples[sourceStart..<sampleCount]
        )

        var windowedInput = Array(repeating: Float(0), count: fftSize)
        vDSP_vmul(fftInput, 1, hannWindow, 1, &windowedInput, 1, vDSP_Length(fftSize))

        var real = Array(repeating: Float(0), count: fftSize / 2)
        var imaginary = Array(repeating: Float(0), count: fftSize / 2)
        var magnitudes = Array(repeating: Float(0), count: fftSize / 2)

        windowedInput.withUnsafeMutableBufferPointer { inputPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    magnitudes.withUnsafeMutableBufferPointer { magnitudesPointer in
                        var splitComplex = DSPSplitComplex(
                            realp: realPointer.baseAddress!,
                            imagp: imaginaryPointer.baseAddress!
                        )

                        inputPointer.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self,
                            capacity: fftSize / 2
                        ) { complexPointer in
                            vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                        }

                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2FFTSize, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&splitComplex, 1, magnitudesPointer.baseAddress!, 1, vDSP_Length(fftSize / 2))
                    }
                }
            }
        }

        let nyquist = max(sampleRate * 0.5, 1)
        let minimumFrequency: Float = 32
        let maximumFrequency = min(12_000, nyquist)
        let frequencyBinWidth = nyquist / Float(fftSize / 2)
        guard maximumFrequency > minimumFrequency, frequencyBinWidth > 0 else {
            return Array(repeating: 0, count: barCount)
        }

        var rawLevels = Array(repeating: Float(0), count: barCount)
        for index in 0..<barCount {
            let lowerProgress = Float(index) / Float(barCount)
            let upperProgress = Float(index + 1) / Float(barCount)
            let lowerFrequency = minimumFrequency * pow(maximumFrequency / minimumFrequency, lowerProgress)
            let upperFrequency = minimumFrequency * pow(maximumFrequency / minimumFrequency, upperProgress)
            let lowerBin = max(1, Int(lowerFrequency / frequencyBinWidth))
            let upperBin = min(magnitudes.count - 1, max(lowerBin + 1, Int(ceil(upperFrequency / frequencyBinWidth))))
            guard lowerBin < upperBin else { continue }

            var bandEnergy: Float = 0
            var strongestBin: Float = 0
            for bin in lowerBin..<upperBin {
                let magnitude = sqrt(magnitudes[bin])
                bandEnergy += magnitude
                strongestBin = max(strongestBin, magnitude)
            }

            let averageEnergy = bandEnergy / Float(upperBin - lowerBin)
            rawLevels[index] = max(averageEnergy * 0.78 + strongestBin * 0.22, 0)
        }

        let peakLevel = rawLevels.max() ?? 0
        if peakLevel > adaptiveCeiling {
            adaptiveCeiling = adaptiveCeiling * 0.78 + peakLevel * 0.22
        } else {
            adaptiveCeiling = max(0.018, adaptiveCeiling * 0.965)
        }

        let noiseFloor = adaptiveCeiling * 0.08
        let normalizationRange = max(0.001, adaptiveCeiling - noiseFloor)
        let normalizedLevels = rawLevels.map { level in
            let normalized = max(0, level - noiseFloor) / normalizationRange
            return min(1, pow(normalized, 0.74))
        }

        let globalAverage = normalizedLevels.reduce(0, +) / Float(max(1, normalizedLevels.count))
        let sensitivityGain: Float
        switch sensitivity {
        case .soft:
            sensitivityGain = 0.88
        case .normal:
            sensitivityGain = 1.0
        case .lively:
            sensitivityGain = 1.18
        }

        return normalizedLevels.enumerated().map { index, level in
            let lowerBound = max(0, index - 1)
            let upperBound = min(normalizedLevels.count - 1, index + 1)
            let neighborSlice = normalizedLevels[lowerBound...upperBound]
            let neighborAverage = neighborSlice.reduce(0, +) / Float(neighborSlice.count)

            let mixedLevel: Float
            switch style {
            case .balanced:
                mixedLevel = level * 0.44 + neighborAverage * 0.28 + globalAverage * 0.28
            case .banded:
                mixedLevel = level * 0.70 + neighborAverage * 0.18 + globalAverage * 0.12
            }

            let amplified = min(1, mixedLevel * sensitivityGain)
            let floorLift = style == .balanced ? globalAverage * 0.10 : globalAverage * 0.04
            return min(1, max(floorLift, pow(amplified, style == .balanced ? 0.88 : 0.76)))
        }
    }
}

private extension SystemAudioSpectrumService {
    enum CaptureError: Error {
        case osStatus(OSStatus)
    }
}
