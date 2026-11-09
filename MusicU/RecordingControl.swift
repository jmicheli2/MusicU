//
//  RecordingControl.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// The central transport: a start/stop button ringed by a live loudness meter,
/// with a status caption beneath it.
struct RecordingControl: View {
    /// The pipeline that owns capture and analysis.
    let analyzer: MusicAnalyzer

    var body: some View {
        VStack(spacing: 20) {
            meterAndButton
            Text(analyzer.statusMessage)
                .font(.callout)
                .foregroundStyle(Color(white: 0.72))
                .animation(.easeInOut(duration: 0.3), value: analyzer.phase)
        }
    }

    private var meterAndButton: some View {
        ZStack {
            LevelMeterView(level: Self.normalizedLevel(analyzer.liveLoudnessLUFS))
                .opacity(analyzer.isBusy ? 1.0 : 0.22)

            Button {
                Task {
                    if analyzer.isBusy {
                        analyzer.stop()
                    } else {
                        await analyzer.start()
                    }
                }
            } label: {
                TransportButtonIcon(isBusy: analyzer.isBusy, phase: analyzer.phase)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200, height: 200)
        .animation(.easeInOut(duration: 0.35), value: analyzer.isBusy)
    }

    /// Maps an LUFS value (~ -60…0) onto a 0…1 level for the meter.
    private static func normalizedLevel(_ lufs: Float?) -> Double {
        guard let lufs, lufs.isFinite else { return 0.0 }
        return min(1.0, max(0.0, (Double(lufs) + 60.0) / 60.0))
    }
}

/// The round start/stop glyph at the centre of the meter.
private struct TransportButtonIcon: View {
    let isBusy: Bool
    let phase: MusicAnalyzer.Phase

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: isBusy ? [
                        Color(red: 0.29, green: 0.83, blue: 0.63),
                        Color(red: 0.23, green: 0.50, blue: 0.96)
                    ] : [
                        Color(white: 0.19),
                        Color(white: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 132, height: 132)
            .overlay(
                Circle()
                    .stroke(Color(white: 1.0).opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .overlay {
                if phase == .analysing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: isBusy ? "stop.fill" : "play.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(isBusy ? 1.0 : 0.97)
    }
}
