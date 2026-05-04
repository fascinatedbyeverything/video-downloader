import Foundation
import AppKit

enum SpotifyAppControllerError: Error {
    case spotifyNotInstalled
    case appleScriptError(String)
}

enum SpotifyPlayerState: String {
    case playing, paused, stopped, unknown

    init(_ raw: String) {
        switch raw {
        case "playing": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: self = .unknown
        }
    }
}

struct SpotifyCurrentTrackInfo {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
    let positionMs: Int
}

enum SpotifyAppController {
    static func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }

    /// Launch Spotify if not running. No-op if already running.
    static func ensureRunning() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            throw SpotifyAppControllerError.spotifyNotInstalled
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            cfg.hides = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
            try await Task.sleep(nanoseconds: 1_500_000_000) // settle
        }
    }

    static func play(uri: String) throws {
        try runAppleScript(#"tell application "Spotify" to play track "\#(uri)""#)
    }

    static func pause() throws {
        try runAppleScript(#"tell application "Spotify" to pause"#)
    }

    static func resume() throws {
        try runAppleScript(#"tell application "Spotify" to play"#)
    }

    static func currentTrack() throws -> SpotifyCurrentTrackInfo? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set tID to id of current track
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDur to duration of current track
            set tPos to player position
            return tID & "\u{2}" & tName & "\u{2}" & tArtist & "\u{2}" & tAlbum & "\u{2}" & tDur & "\u{2}" & tPos
        end tell
        """
        let raw = try runAppleScript(script)
        guard !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\u{2}")
        guard parts.count == 6 else { return nil }
        let id = parts[0].replacingOccurrences(of: "spotify:track:", with: "")
        return SpotifyCurrentTrackInfo(
            id: id,
            name: parts[1],
            artist: parts[2],
            album: parts[3],
            durationMs: Int(parts[4]) ?? 0,
            positionMs: Int((Double(parts[5]) ?? 0) * 1000)
        )
    }

    static func playerState() throws -> SpotifyPlayerState {
        let raw = try runAppleScript(#"tell application "Spotify" to player state as string"#)
        return SpotifyPlayerState(raw)
    }

    @discardableResult
    private static func runAppleScript(_ source: String) throws -> String {
        var errInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyAppControllerError.appleScriptError("compile failed")
        }
        let result = script.executeAndReturnError(&errInfo)
        if let errInfo = errInfo {
            throw SpotifyAppControllerError.appleScriptError("\(errInfo)")
        }
        return result.stringValue ?? ""
    }
}
