//
//  MetronomeView.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// A glass card below the key/tempo readouts: a horizontal tempo slider
/// (20…300 BPM), a live BPM readout, and a start/stop button that drives the
/// `Metronome`.
///
/// The card is deliberately self-contained - it knows nothing about the
/// analyzer.
struct MetronomeView: View {
    /// The metronome that owns the tempo and the engine. `@Bindable` gives the
    /// slider a direct two-way binding to `bpm`.
    @Bindable var metronome: Metronome

    var body: some View {
        VStack(spacing: 16) {
            header

            Slider(value: $metronome.bpm, in: Metronome.minimumBPM...Metronome.maximumBPM)
                .tint(Color(red: 0.29, green: 0.83, blue: 0.63))

            HStack {
                Text(Metronome.minimumBPM, format: .number.precision(.fractionLength(0)))
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.40))
                Spacer()
                Text(Metronome.maximumBPM, format: .number.precision(.fractionLength(0)))
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.40))
            }

            transportButton
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color(white: 1.0).opacity(0.10), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.25), value: metronome.isRunning)
    }

    // MARK: - Subviews

    /// The small uppercased title, and the big live BPM readout on the right.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "metronome")
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.29, green: 0.82, blue: 0.66))
                Text("METRONOME")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(white: 0.55))
                    .kerning(1.5)
            }

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metronome.bpm, format: .number.precision(.fractionLength(0)))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .foregroundStyle(Color(white: 0.97))
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(white: 0.50))
            }
            .animation(.easeInOut(duration: 0.15), value: metronome.bpm)
        }
    }

    /// A pill transport: dark at rest, the app's green-to-blue gradient while
    /// sounding - echoing the big recording button.
    private var transportButton: some View {
        Button {
            Task {
                if metronome.isRunning {
                    metronome.stop()
                } else {
                    await metronome.start()
                }
            }
        } label: {
            Label(
                metronome.isRunning ? "Stop" : "Start",
                systemImage: metronome.isRunning ? "stop.fill" : "play.fill"
            )
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        metronome.isRunning
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.29, green: 0.83, blue: 0.63),
                                        Color(red: 0.23, green: 0.50, blue: 0.96)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color(white: 0.14))
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color(white: 1.0).opacity(metronome.isRunning ? 0.25 : 0.12), lineWidth: 1)
            )
            .shadow(
                color: metronome.isRunning
                    ? Color(red: 0.29, green: 0.83, blue: 0.63).opacity(0.35)
                    : .clear,
                radius: 10,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.059, blue: 0.157),
                Color(red: 0.012, green: 0.016, blue: 0.031)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        MetronomeView(metronome: Metronome())
            .frame(maxWidth: 420)
    }
}
