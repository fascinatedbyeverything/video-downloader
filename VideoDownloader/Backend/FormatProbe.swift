import Foundation

struct FormatRow: Identifiable, Equatable, Hashable {
    let id: String
    let formatID: String
    let container: String
    let resolution: String
    let fps: String?
    let fileSize: String?
    let tbr: String?
    let proto: String?
    let vcodec: String?
    let acodec: String?
    let note: String?
}

enum FormatProbe {
    /// Parse the output of `yt-dlp -F <url>`.
    /// Skip [info] / header / separator lines; each remaining line is one format row.
    static func parse(_ output: String) -> [FormatRow] {
        var rows: [FormatRow] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = String(raw)
            guard !line.hasPrefix("[info]"),
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("ID"),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  line.rangeOfCharacter(from: CharacterSet(charactersIn: "─")) == nil
            else { continue }

            // "│" is a column divider; replace with spaces for token splitting
            let cleaned = line.replacingOccurrences(of: "│", with: " ")
            let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3 else { continue }

            let formatID = tokens[0]
            let ext = tokens[1]
            var idx = 2
            var resolution: String
            if tokens[idx] == "audio", idx + 1 < tokens.count, tokens[idx + 1] == "only" {
                resolution = "audio only"
                idx += 2
            } else {
                resolution = tokens[idx]
                idx += 1
            }

            var fps: String? = nil
            if idx < tokens.count, Int(tokens[idx]) != nil {
                fps = tokens[idx]; idx += 1
            }
            var fileSize: String? = nil
            if idx < tokens.count, tokens[idx].contains("iB") {
                fileSize = tokens[idx]; idx += 1
            }
            let note = idx < tokens.count ? tokens[idx...].joined(separator: " ") : nil

            rows.append(FormatRow(
                id: formatID,
                formatID: formatID,
                container: ext,
                resolution: resolution,
                fps: fps,
                fileSize: fileSize,
                tbr: nil,
                proto: nil,
                vcodec: nil,
                acodec: nil,
                note: note
            ))
        }
        return rows
    }
}
