//
//  AddYouTubeLinkSheet.swift
//  Ponder
//

import SwiftUI

struct AddYouTubeLinkSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String, String) -> Bool

    @State private var urlString = ""
    @State private var title = ""
    @State private var showInvalidURL = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube URL", text: $urlString)
                        .youtubeURLTextInput()
                        .autocorrectionDisabled()
                    TextField("Title", text: $title)
                }
            }
            .navigationTitle("YouTube Video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if onAdd(urlString, title.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            isPresented = false
                        } else {
                            showInvalidURL = true
                        }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Invalid YouTube Link", isPresented: $showInvalidURL) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Paste a valid YouTube video, Shorts, or youtu.be link.")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func youtubeURLTextInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
