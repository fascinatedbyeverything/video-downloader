import SwiftUI
import AppKit

struct LibraryView: View {
    @Environment(LibraryModel.self) private var library
    @State private var showImport = false

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            HStack {
                TextField("Search…", text: $library.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Picker("Sort", selection: $library.sort) {
                    ForEach(LibraryModel.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 160)
                Picker(selection: $library.viewMode) {
                    Image(systemName: "square.grid.2x2").tag(LibraryModel.ViewMode.grid)
                    Image(systemName: "list.bullet").tag(LibraryModel.ViewMode.list)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 80)
                Spacer()
                Button("Import…") { showImport = true }
                Button("Rescan") {
                    Task { await library.scan(folder: DriveCheck.libraryFolder) }
                }
            }
            .padding(8)

            Divider()

            ScrollView {
                switch library.viewMode {
                case .grid:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(library.filteredItems) { item in
                            LibraryItemView(item: item, style: .grid)
                        }
                    }
                    .padding(12)
                case .list:
                    VStack(spacing: 0) {
                        ForEach(library.filteredItems) { item in
                            LibraryItemView(item: item, style: .list)
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet(onCompletion: {
                showImport = false
                Task { await library.scan(folder: DriveCheck.libraryFolder) }
            })
        }
    }
}
