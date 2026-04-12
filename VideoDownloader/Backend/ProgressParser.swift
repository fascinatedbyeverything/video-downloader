import Foundation

struct DownloadProgress: Equatable {
    let percent: Double
    let speedDescription: String?
    let etaDescription: String?
}

enum ProgressParser {
    // Matches these shapes:
    //   [download]  45.2% of   98.84MiB at    4.90MiB/s ETA 01:45
    //   [download]   9.8% of   98.84MiB at  Unknown B/s ETA Unknown
    //   [download] 100% of   98.84MiB in 00:00:06 at 16.00MiB/s
    //
    // Three alternations (groups shift per branch):
    //   Branch A (with ETA):   groups 1=percent, 2=speed, 3=eta
    //   Branch B (no ETA):     groups 4=percent, 5=speed
    //   Branch C (percent only): group 6=percent
    private static let regex: NSRegularExpression = {
        let pattern = #"^\[download\]\s+(\d+(?:\.\d+)?)%.*?\bat\s+(Unknown B/s|\S+/s)\s+ETA\s+(\S+)|^\[download\]\s+(\d+(?:\.\d+)?)%.*?\bat\s+(Unknown B/s|\S+/s)\s*$|^\[download\]\s+(\d+(?:\.\d+)?)%"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func parse(_ line: String) -> DownloadProgress? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        // Helper to extract a capture group string or nil
        func group(_ i: Int) -> String? {
            guard i < match.numberOfRanges else { return nil }
            let r = match.range(at: i)
            guard r.location != NSNotFound else { return nil }
            return nsLine.substring(with: r)
        }

        // Determine which branch matched and extract percent, speed, eta
        let percent: Double
        let rawSpeed: String?
        let rawEta: String?

        if let p = group(1).flatMap({ Double($0) }) {
            // Branch A: percent=1, speed=2, eta=3
            percent = p
            rawSpeed = group(2)
            rawEta = group(3)
        } else if let p = group(4).flatMap({ Double($0) }) {
            // Branch B: percent=4, speed=5, no eta
            percent = p
            rawSpeed = group(5)
            rawEta = nil
        } else if let p = group(6).flatMap({ Double($0) }) {
            // Branch C: percent only
            percent = p
            rawSpeed = nil
            rawEta = nil
        } else {
            return nil
        }

        let speed = rawSpeed == "Unknown B/s" ? nil : rawSpeed
        let eta = rawEta == "Unknown" ? nil : rawEta

        return DownloadProgress(percent: percent, speedDescription: speed, etaDescription: eta)
    }
}
