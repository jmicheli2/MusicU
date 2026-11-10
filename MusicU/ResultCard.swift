//
//  ResultCard.swift
//  MusicU
//
//  Created by Jacques Micheli on 09/11/2026.
//

import SwiftUI

/// A translucent, rounded container that presents a single measured music property.
struct ResultCard<Content: View>: View {
    /// The section title, shown small and uppercased above the value.
    let title: String
    /// The SF Symbol shown next to the title.
    let systemImage: String
    /// The measured value rendered inside the card.
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 0.29, green: 0.82, blue: 0.66))
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(white: 0.55))
                    .kerning(1.5)
            }

            Spacer(minLength: 0)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color(white: 1.0).opacity(0.10), lineWidth: 1)
                )
        )
    }
}
