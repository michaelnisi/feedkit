//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2017 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation

/// Enumerate supported enclosure media types. Note that unknown is legit here.
public enum EnclosureType: Int, Codable {
  case unknown
  case audioMPEG
  case audioXMPEG
  case videoXM4V
  case audioMP4
  case xm4A
  case videoMP4
  
  public init(withString type: String) {
    switch type {
    case "audio/mpeg": self = .audioMPEG
    case "audio/x-mpeg": self = .audioXMPEG
    case "video/x-m4v": self = .videoXM4V
    case "audio/mp4": self = .audioMP4
    case "audio/x-m4a": self = .xm4A
    case "video/mp4": self = .videoMP4
    default: self = .unknown
    }
  }
  
  /// Returns `true` if the enclosure claims to be video. Of course, total
  /// bullshit, I would prefer not having `EnclosureType` at all.
  public var isVideo: Bool {
    assert(self != .unknown, "add case")
    
    switch self {
    case .videoXM4V, .videoMP4, .unknown:
      return true
    default:
      return false
    }
  }
}

/// The infamous RSS enclosure tag is mapped to this structure.
public struct Enclosure: Codable {
  public let url: String
  public let length: Int?
  public let type: EnclosureType
}

extension Enclosure : CustomStringConvertible {
  public var description: String {
    "Enclosure: \(url)"
  }
}

extension Enclosure: Equatable, Hashable {
  public static func ==(lhs: Enclosure, rhs: Enclosure) -> Bool {
    lhs.url == rhs.url
  }
  
  public func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}
