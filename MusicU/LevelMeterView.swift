//
//  LevelMeterView.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// A circular meter that visualises a 0…1 level as a coloured progress ring.
///
/// It renders a faint track plus a live arc so the listener always has visual
/// feedback, even before the first key/tempo readout is known.
struct LevelMeterView: View {
    /// Normalised level in the range 0…1.
    let level: Double

    var body: some View {
        ZStack {
            // Faint full-circle track.
            Circle()
                .stroke(Color(white: 1.0).opacity(0.08), lineWidth: 12)
                .frame(width: 168, height: 168)

            // Live arc, starting at 12 o'clock and growing clockwise.
            Circle()
                .trim(from: 0.0, to: CGFloat(min(1.0, max(0.0001, level))))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.29, green: 0.83, blue: 0.63),
                            Color(red: 0.23, green: 0.55, blue: 0.96),
                            Color(red: 0.60, green: 0.35, blue: 0.98)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}
