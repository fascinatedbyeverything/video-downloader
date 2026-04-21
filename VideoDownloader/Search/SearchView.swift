import SwiftUI

struct SearchView: View {
    @State private var model = SearchModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search YouTube — artist, song, title…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { Task { await model.search() } }

                if model.isSearching {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Search") { Task { await model.search() } }
                        .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(8)

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            contentBody
        }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var contentBody: some View {
        if model.isSearching && model.results.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Searching…").foregroundStyle(.secondary).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.results.isEmpty {
            List {
                ForEach(model.results) { result in
                    SearchResultRow(result: result)
                }
            }
            .listStyle(.inset)
        } else if let q = model.lastRunQuery, model.error == nil {
            VStack {
                Text("No results for \"\(q)\"").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
                Text("Search YouTube and download audio or video")
                    .foregroundStyle(.secondary)
                Text("Default action: one-click MP3 download. ▾ menu for other formats.")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
