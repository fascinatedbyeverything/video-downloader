import Foundation

struct SidecarJSON: Codable, Equatable, Hashable {
    let schemaVersion: Int
    let title: String
    let url: String?
    let site: SiteSource
    let uploader: String?
    let duration: Double
    let format: String
    let formatLabel: String
    let fileSize: Int64
    let fileName: String
    let thumbnailFile: String?
    let dateAdded: Date
    let description: String?
    let mediaFilePath: String?
    let importedFromPath: String?

    static let fileExtension = "meta.json"

    static func sidecarURL(forMediaBasename basename: String, in folder: URL) -> URL {
        folder.appendingPathComponent("\(basename).\(Self.fileExtension)")
    }

    func write(to folder: URL) throws {
        let url = Self.sidecarURL(forMediaBasename: fileName, in: folder)
        let data = try JSONEncoder.pretty.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> SidecarJSON {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso.decode(SidecarJSON.self, from: data)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
