//
//  MusicAnalyzer.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import AVFoundation
import AVFAudio
import CoreMedia
import MusicUnderstanding
import Observation

/// Drives a live microphone capture and a single MusicUnderstandingSession pass,
/// exposing the live loudness while listening and the detected key + tempo once a
/// pass finalises. A new session is created for every pass, matching the
/// framework's single-use contract.
@MainActor
@Observable
final class MusicAnalyzer {

    // MARK: - Phase

    /// The lifecycle of a capture-and-analyse pass.
    enum Phase {
        case idle
        case listening
        case analysing
    }

    // MARK: - Published state (observed by SwiftUI)

    /// Where the pipeline currently is.
    private(set) var phase: Phase = .idle

    /// The latest live loudness in LUFS; nil before the first sample.
    private(set) var liveLoudnessLUFS: Float?

    /// The detected key as text such as "C shar minor"; nil when unknown.
    private(set) var detectedKey: String?

    /// The detected tempo in beats per minute; nil until enough audio is analysed.
    private(set) var detectedTempoBPM: Int?

    /// Peak loudness from the final pass in LUFS; nil until analysis finishes.
    private(set) var peakLoudnessLUFS: Float?

    /// A user-facing error; cleared on the next start().
    var errorMessage: String?

    // MARK: - Derived

    /// true while a pass is capturing or finishing.
    var isBusy: Bool { phase != .idle }

    /// A short status line for the interface.
    var statusMessage: String {
        switch phase {
        case .idle:
            if detectedKey == nil && detectedTempoBPM == nil {
                return "Tap to begin"
            }
            return "Analysis complete - tap to listen again"
        case .listening:
            return "Listening…"
        case .analysing:
            return "Analysing…"
        }
    }

    // MARK: - Pipeline

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var streamContinuation: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
    @ObservationIgnored private var session: MusicUnderstandingSession?
    @ObservationIgnored private var analysisTask: Task<MusicUnderstandingSession.SessionResult?, Never>?
    @ObservationIgnored private var didRequestPermission = false

    /// Key + rhythm feed the readouts; loudness powers the live meter.
    private let analysisTypes: Set<AnalysisType> = [.key, .rhythm, .loudness]

    // MARK: - Control

    /// Begins a capture pass: requests the mic, starts the engine, and feeds a
    /// live stream of audio buffers into a fresh analysis session.
    func start() async {
        guard phase == .idle else { return }

        detectedKey = nil
        detectedTempoBPM = nil
        peakLoudnessLUFS = nil
        liveLoudnessLUFS = nil
        errorMessage = nil

        await ensureMicrophonePermission()
        guard errorMessage == nil else { return }

        do {
            try await configureAudioSession()
        } catch {
            errorMessage = "Could not start the audio session: " + error.localizedDescription
            return
        }

        // 1. A non-throwing stream of read-only buffers for the session.
        var continuation: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
        let audioStream = AsyncStream<AVReadOnlyAudioPCMBuffer>(bufferingPolicy: .unbounded) { cont in
            continuation = cont
        }

        // 2. Microphone input node -> a tap that pushes read-only buffers.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        do {
            try inputNode.installAudioTap(
                onBus: 0,
                bufferSize: 4096,
                format: nil
            ) { [continuation] buffer, _ in
                continuation?.yield(buffer)
            }
            engine.prepare()
            try? engine.start()
        } catch {
            engine.stop()
            errorMessage = "Could not open the microphone: " + error.localizedDescription
            return
        }

        // 3. Hand the stream to a fresh, single-use analysis session.
        let session = MusicUnderstandingSession(audioProvider: audioStream)

        self.engine = engine
        self.streamContinuation = continuation
        self.session = session
        self.phase = .listening

        runAnalysis(session)
    }

    /// Stops capturing and finalises the pass, then reveals the key + tempo.
    func stop() {
        guard phase == .listening else { return }
        phase = .analysing
        // Finishing the stream ends the loudness sequence and completes analyze().
        streamContinuation?.finish()
    }

    // MARK: - Analysis

    private func runAnalysis(_ session: MusicUnderstandingSession) {
        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return nil }
            do {
                let result = try await withThrowingTaskGroup(
                    of: MusicUnderstandingSession.SessionResult?.self
                ) { group in
                    // The live loudness meter.
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return nil }
                        do {
                            for try await loudness in session.loudnessResults {
                                self.liveLoudnessLUFS = loudness.momentary.first?.value
                            }
                        } catch {
                            // The sequence ended or was cancelled - expected.
                        }
                        return nil
                    }

                    // The final, aggregated pass.
                    group.addTask { @MainActor [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await session.analyze(for: self.analysisTypes)
                    }

                    // Surface the first non-nil result (the aggregated pass).
                    var finalResult: MusicUnderstandingSession.SessionResult?
                    for try await value in group {
                        if let value {
                            finalResult = value
                        }
                    }
                    return finalResult
                }
                apply(result)
            } catch {
                fail(error)
            }
            return nil
        }
    }

    private func apply(_ result: MusicUnderstandingSession.SessionResult?) {
        teardownEngine()
        session = nil
        streamContinuation = nil
        // The running task cannot clear itself; defer the drop one hop.
        Task { @MainActor [weak self] in
            self?.analysisTask = nil
        }

        if let key = result?.key {
            detectedKey = Self.describe(key: key)
        }
        if let rhythm = result?.rhythm, let bpm = rhythm.beatsPerMinute {
            detectedTempoBPM = Int(bpm.rounded())
        }
        if let loudness = result?.loudness {
            peakLoudnessLUFS = loudness.peak.value
        }

        phase = .idle
        if result == nil {
            errorMessage = "That pass did not produce a result - try again."
        }
    }

    private func fail(_ error: Error) {
        teardownEngine()
        session = nil
        streamContinuation = nil
        Task { @MainActor [weak self] in
            self?.analysisTask = nil
        }
        phase = .idle
        errorMessage = "Analysis failed: " + error.localizedDescription
    }

    // MARK: - Teardown

    private func teardownEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    // MARK: - Audio setup

    private func ensureMicrophonePermission() async {
        guard !didRequestPermission else { return }
        didRequestPermission = true
        let granted = await AVAudioApplication.requestRecordPermission()
        if !granted {
            errorMessage = "Microphone access is required. Enable it in Settings to use MusicU."
        }
    }

    /// Uses the asynchronous audio-session API: `start()` runs on the main
    /// actor, and the synchronous `setActive` blocks the main thread long
    /// enough for the system to warn about UI unresponsiveness.
    private func configureAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record)
        _ = try await audioSession.activate()
    }

    // MARK: - Key formatting

    /// Describes a KeyResult as readable text such as "C major".
    private static func describe(key: KeyResult) -> String {
        let ranges = key.ranges
        // The dominant key is the one that spans the longest range.
        let dominant = ranges.max {
            CMTimeGetSeconds($0.range.duration) < CMTimeGetSeconds($1.range.duration)
        } ?? ranges.last
        guard let signature = dominant?.value else { return "—" }

        let note = noteName(for: signature.tonic)
        switch signature.mode {
        case .major:
            return note + " major"
        case .minor:
            return note + " minor"
        @unknown default:
            return note
        }
    }

    /// Maps a KeyResult.Tonic to a note label, preserving sharp/flat spellings.
    private static func noteName(for tonic: KeyResult.Tonic) -> String {
        switch tonic {
        case .c: return "C"
        case .cSharp: return "C♯"
        case .dFlat: return "D♭"
        case .d: return "D"
        case .dSharp: return "D♯"
        case .eFlat: return "E♭"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F♯"
        case .gFlat: return "G♭"
        case .g: return "G"
        case .gSharp: return "G♯"
        case .aFlat: return "A♭"
        case .a: return "A"
        case .aSharp: return "A♯"
        case .bFlat: return "B♭"
        case .b: return "B"
        }
    }
}
