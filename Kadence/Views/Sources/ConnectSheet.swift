//
//  ConnectSheet.swift
//  Kadence
//
//  layouts.md §12 — the connect sheet. Task 12 only routes to it; task 13
//  builds it. Until then it offers nothing but Cancel.
//

import SwiftUI

struct ConnectSheet: View {
    let request: SourcesRouter.Sheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Tokens.Spacing.xxxl)
        .frame(width: Tokens.Size.connectSheetWidth)
    }
}
