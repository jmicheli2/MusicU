//
//  ContentView.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// The app's single screen: a dark, glassy layout with a live loudness meter,
/// a start/stop transport, and two readout cards for the detected key and tempo.
struct ContentView: View {
    @State private var analyzer = MusicAnalyzer()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                Spacer(minLength: 24)

                RecordingControl(analyzer: analyzer)

                Spacer(minLength: 24)

                HStack(spacing: 16) {
                    KeyView(keyText: analyzer.detectedKey, isBusy: analyzer.isBusy)
                    TempoView(bpm: analyzer.detectedTempoBPM, isBusy: analyzer.isBusy)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 24)

                footer
            }
            .frame(maxWidth: 460)
            .padding(.top, 44)
            .padding(.bottom, 32)
            .animation(.easeInOut(duration: 0.35), value: analyzer.phase)
            .animation(.easeInOut(duration: 0.35), value: analyzer.detectedKey)
            .animation(.easeInOut(duration: 0.35), value: analyzer.detectedTempoBPM)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.059, blue: 0.157),
                Color(red: 0.012, green: 0.016, blue: 0.031)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color(red: 0.13, green: 0.52, blue: 0.60).opacity(0.35), .clear],
                center: UnitPoint(x: 0.5, y: 0.18),
                startRadius: 0,
                endRadius: 320
            )
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("MusicU")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundStyle(Color(white: 0.97))
            Text("Key and tempo, detected from the microphone")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.58))
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let error = analyzer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if let peak = analyzer.peakLoudnessLUFS {
                Text("Peak " + String(format: "%.1f", Double(peak)) + " LUFS")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.45))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
