import Foundation

enum DownloadFormat: Equatable, Hashable {
    case best
    case p1080
    case p720
    case p480
    case audioMP3
    case audioWAV
    case custom(formatID: String)

    var ytdlpFormat: String {
        switch self {
        case .best: return "bestvideo+bestaudio/best"
        case .p1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .p720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .p480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .audioMP3: return "bestaudio"
        case .audioWAV: return "bestaudio"
        case .custom(let id): return id
        }
    }

    var displayName: String {
        switch self {
        case .best: return "Best"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .audioMP3: return "Audio — MP3 (320 kbps)"
        case .audioWAV: return "Audio — WAV (16-bit/44.1kHz)"
        case .custom(let id): return "Custom (\(id))"
        }
    }

    var isAudioOnly: Bool {
        switch self {
        case .audioMP3, .audioWAV: return true
        default: return false
        }
    }

    var audioPostProcess: AudioPostProcess? {
        switch self {
        case .audioMP3: return .mp3_320
        case .audioWAV: return .wav_16_441
        default: return nil
        }
    }

    static let presets: [DownloadFormat] = [.best, .p1080, .p720, .p480, .audioMP3, .audioWAV]
}

enum AudioPostProcess {
    case mp3_320       // 320 kbps CBR MP3
    case wav_16_441    // 16-bit 44.1kHz PCM WAV
}
