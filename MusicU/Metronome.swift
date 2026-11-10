//
//  Metronome.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import AVFoundation
import Observation

/// A self-contained, sample-accurate metronome.
///
/// It owns its own `AVAudioEngine` and plays a "ding" synthesized in memory at
/// a tempo driven by `bpm`, so it is completely independent of
/// `MusicAnalyzer` and the microphone. Start it while the audio analysis is
/// not running, stop it when that is. Changing `bpm` while it is running
/// retimes the next beats immediately, without restarting the engine.
///
/// The audio session is configured and (de)activated with the asynchronous
/// `activate`/`deactivate` API, so it never blocks the main thread.
@MainActor
@Observable
final class Metronome {

    // MARK: - Tuning

    /// Lowest tempo the slider can produce, in beats per minute.
    static let minimumBPM: Double = 20

    /// Highest tempo the slider can produce, in beats per minute.
    static let maximumBPM: Double = 300

    /// How far ahead the scheduler pre-schedules beats (seconds).
    private static let lookAhead = 0.35

    /// How often the scheduler wakes to top up the pending beats (seconds).
    private static let tick = 0.025

    /// Shape of the synthesized ding: duration, decay and pitch.
    private static let tingDuration = 0.22
    private static let tingDecayRate = 24.0
    private static let tingFundamental = 1174.7  // D6 - bright, bell-like

    // MARK: - Observed state (SwiftUI)

    /// The current tempo in beats per minute. Binding a slider to this retimes
    /// the metronome live, whether it is stopped or running.
    var bpm: Double = 120

    /// true while the metronome is sounding.
    private(set) var isRunning = false

    // MARK: - Engine state

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var dingBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private var deactivationTask: Task<Void, Never>?
    @ObservationIgnored private var nextBeatPlayerTime = 0.0
    /// Bumped by every start and stop; lets a start in flight notice that it
    /// was superseded by a stop while it was awaiting the session.
    @ObservationIgnored private var generation = 0

    // MARK: - Control

    /// Starts the metronome. Safe to call when it already is.
    func start() async {
        guard !isRunning else { return }
        // Latch synchronously: a second tap during the async activation below
        // sees `isRunning` and no-ops instead of building a second engine.
        isRunning = true
        generation &+= 1
        let myGeneration = generation

        // If a stop is still unwinding its deactivation, drop it so it cannot
        // deactivate the session right after we re-activate it.
        deactivationTask?.cancel()
        deactivationTask = nil

        // Asynchronous session activation - never blocks the main thread.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            _ = try await AVAudioSession.sharedInstance().activate()
        } catch {
            if myGeneration == generation { isRunning = false }
            return
        }

        // A stop may have landed while we were awaiting: abort without leaving
        // an engine running behind.
        guard myGeneration == generation else { return }

        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()
        guard
            let format = outputFormat(of: newEngine),
            let buffer = makeDingBuffer(sampleRate: format.sampleRate)
        else {
            if myGeneration == generation { isRunning = false }
            return
        }
        newEngine.attach(newPlayer)

        do {
            // Connect with the explicit mono format so the player's *output*
            // channel count (1) matches the synthesized mono buffer. Passing
            // nil would let the player adopt the mixer's stereo output (2) and
            // AVAudioPlayerNode would trap on scheduleBuffer. The main mixer
            // transparently upmixes mono to the device's stereo output.
            try newEngine.connectNode(newPlayer, to: newEngine.mainMixerNode, format: format)
            try newEngine.start()
            try newPlayer.playAudio()
        } catch {
            if myGeneration == generation { isRunning = false }
            return
        }

        self.engine = newEngine
        self.player = newPlayer
        self.dingBuffer = buffer
        nextBeatPlayerTime = 0.0

        // Weak `self`: the task is stored on `self`, so a strong capture would
        // form a cycle kept alive until `stop()` nils it. Weak capture means a
        // released metronome silently stops its clock.
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { break }
                self.scheduleBeats()
                try? await Task.sleep(for: .seconds(Self.tick))
            }
        }
    }

    /// Stops the metronome. Safe to call when it already is.
    func stop() {
        guard isRunning else { return }
        generation &+= 1
        scheduler?.cancel()
        scheduler = nil

        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        dingBuffer = nil
        isRunning = false

        // Deactivate asynchronously, fire-and-forget: the scheduler is already
        // cancelled above, so a late failure can no longer matter.
        deactivationTask = Task {
            _ = try? await AVAudioSession.sharedInstance().deactivate()
        }
    }

    // MARK: - Scheduling

    /// Tops up the player's pending beats up to `lookAhead` seconds into the
    /// future. `bpm` is read on every wake, so dragging the slider retimes the
    /// coming beats without restarting anything.
    private func scheduleBeats() {
        guard
            let player,
            let dingBuffer,
            let nodeTime = player.lastRenderTime
        else { return }

        // `lastRenderTime` is expressed on the *node* timeline; the player
        // schedules against its own timeline, relative to when it started.
        guard let playerNow = player.playerTime(forNodeTime: nodeTime) else { return }
        let nowSeconds = Double(playerNow.sampleTime) / playerNow.sampleRate
        let secondsPerBeat = 60.0 / bpm

        // If we fell more than half a beat behind (a main-thread hiccup),
        // resync to the future instead of bursting a stack of past dings.
        if nextBeatPlayerTime < nowSeconds - secondsPerBeat * 0.5 {
            nextBeatPlayerTime = nowSeconds + secondsPerBeat
        }

        while nextBeatPlayerTime < nowSeconds + Self.lookAhead {
            let when = AVAudioTime(
                sampleTime: AVAudioFramePosition(nextBeatPlayerTime * playerNow.sampleRate),
                atRate: playerNow.sampleRate
            )
            player.scheduleBuffer(dingBuffer, at: when)
            nextBeatPlayerTime += secondsPerBeat
        }
    }

    // MARK: - Sound

    /// The device sample rate in mono, so the engine never resamples the buffer.
    private func outputFormat(of engine: AVAudioEngine) -> AVAudioFormat? {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0 else { return nil }
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    /// Synthesizes the "ding": a short struck-bell tone - a fundamental plus an
    /// inharmonic overtone, with a fast exponential decay.
    private func makeDingBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }

        let frameCount = AVAudioFrameCount((Self.tingDuration * sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // A hair's-breadth linear attack keeps the strike from clicking.
            let envelope = t < 0.002 ? t / 0.002 : exp(-(t - 0.002) * Self.tingDecayRate)
            let fundamental = sin(2 * .pi * Self.tingFundamental * t)
            let overtone = 0.08 * sin(2 * .pi * Self.tingFundamental * 2.76 * t)
            channel[frame] = Float((fundamental + overtone) * envelope * 0.6)
        }
        return buffer
    }
}
