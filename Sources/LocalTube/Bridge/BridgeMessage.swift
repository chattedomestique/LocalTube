import Foundation

// MARK: - Bridge Message Types (JS → Swift)
//
// Each message from the WKWebView has a `type` string and optional `payload` dictionary.

enum BridgeMessageType: String, Decodable {
    case getState
    case playVideo
    case stopPlayer
    case openFolderPicker
    case validatePIN
    case setPIN
    case requestEditorMode
    case exitEditorMode
    case addChannel
    case deleteChannel
    case updateChannel
    case addVideoURLs
    case deleteVideo
    case retryDownload
    case saveSettings
    case checkDependencies
}

struct BridgeMessage: Decodable {
    let type: BridgeMessageType
    let payload: [String: AnyCodable]?
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) { value = v; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:                  try container.encode(v)
        case let v as Int:                   try container.encode(v)
        case let v as Double:                try container.encode(v)
        case let v as String:                try container.encode(v)
        case let v as [String: AnyCodable]:  try container.encode(v)
        case let v as [AnyCodable]:          try container.encode(v)
        default: try container.encodeNil()
        }
    }

    // MARK: - Convenience accessors

    var string: String? { value as? String }
    var int: Int? { value as? Int }
    var double: Double? { value as? Double }
    var bool: Bool? { value as? Bool }
    var dict: [String: AnyCodable]? { value as? [String: AnyCodable] }
    var array: [AnyCodable]? { value as? [AnyCodable] }
}
