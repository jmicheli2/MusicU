//
//  KeyView.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// A card that shows the detected musical key (tonic + mode), e.g. \`"C major"\`.
struct KeyView: View {
    /// The detected key as display text; \`nil\` renders a placeholder.
    let keyText: String?
    /// \`true\` while a pass is running, so the placeholder reads \`"Listening…"\`.
    let isBusy: Bool

    var body: some View {
        ResultCard(title: "Key", systemImage: "music.quarternote.3") {
            if let keyText {
                Text(keyText)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(white: 0.97))
                    .contentTransition(.numericText())
            } else {
                Text(isBusy ? "Listening…" : "—")
                    .font(.title)
                    .foregroundStyle(Color(white: 0.40))
            }
        }
    }
}
