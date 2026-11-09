//
//  TempoView.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// A card that shows the detected tempo in beats per minute (BPM).
struct TempoView: View {
    /// The detected tempo in BPM; \`nil\` renders a placeholder.
    let bpm: Int?
    /// \`true\` while a pass is running, so the placeholder reads \`"Reading…"\`.
    let isBusy: Bool

    var body: some View {
        ResultCard(title: "Tempo", systemImage: "metronome") {
            if let bpm {
                VStack(spacing: 2) {
                    Text("\(bpm)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.heavy)
                        .foregroundStyle(Color(white: 0.97))
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(white: 0.50))
                }
            } else {
                Text(isBusy ? "Reading…" : "—")
                    .font(.title)
                    .foregroundStyle(Color(white: 0.40))
            }
        }
    }
}
