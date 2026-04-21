import Foundation
import Observation

@Observable
final class SearchModel: @unchecked Sendable {
    var query: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false
    var error: String?
    var lastRunQuery: String? = nil

    @ObservationIgnored
    private var liveProcess: Process?

    @MainActor
    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = []
            error = nil
            lastRunQuery = nil
            return
        }

        // Cancel any in-flight search before starting a new one.
        cancelInternal()

        isSearching = true
        error = nil

        do {
            let found = try await YTDLPSearch.search(query: q) { [weak self] p in
                Task { @MainActor in
                    self?.liveProcess = p
                }
            }
            self.results = found
            self.error = nil
        } catch YTDLPSearch.SearchError.cancelled {
            // New search already took over — don't stomp its state.
            return
        } catch {
            self.results = []
            self.error = error.localizedDescription
        }

        self.isSearching = false
        self.liveProcess = nil
        self.lastRunQuery = q
    }

    @MainActor
    func cancel() {
        cancelInternal()
        isSearching = false
    }

    private func cancelInternal() {
        if let p = liveProcess, p.isRunning {
            p.terminate()
        }
        liveProcess = nil
    }
}
