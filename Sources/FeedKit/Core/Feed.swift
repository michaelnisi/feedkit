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

public typealias FeedURL = String

/// Feeds are the central object of this framework.
///
/// The initializer is inconvenient for a reason: **it shouldn't be used
/// directly**. Instead users are expected to obtain their feeds from the
/// repositories provided by this framework. Two feeds are equal if they
/// have equal URLs.
///
/// A feed must have a `title` and an `url`.
public struct Feed: Cachable, Redirectable {
  
  /// Identifies the feed locally for quick access within the cache.
  ///
  /// Dissociative identity disorder or premature optimization? You want a feed
  /// object? Here, have some storage implementation details with it.
  struct ID: Equatable, Codable {
    
    /// The SQLite primary key.
    let rowid: Int64
    
    /// The URL of the feed.
    let url: FeedURL
    
    public static func ==(lhs: ID, rhs: ID) -> Bool {
      return lhs.rowid == rhs.rowid
    }
    
    /// Tries to return a feed URL string from any optional `string`.
    public static func urlString(string: String?) -> String? {
      guard
        let t = string?.lowercased(),
        let url = URL(string: t),
        url.scheme == "http" ||
        url.scheme == "https" ||
        url.scheme == "feed" else {
        return nil
      }
      
      guard url.scheme != "feed" else {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "http"
        
        return (c?.url!.absoluteString)!
      }
      
      return url.absoluteString
    }
    
  }

  public let author: String?
  public let iTunes: ITunesItem?
  public let image: String?
  public let link: String?
  public let originalURL: String?
  public let summary: String?
  public let title: String
  public let ts: Date

  let uid: ID?

  public let updated: Date?
  public let url: FeedURL
}

extension Feed: Codable {}

extension Feed : CustomStringConvertible {

  public var description: String {
    return "Feed: \(title)"
  }
}

extension Feed: CustomDebugStringConvertible {

  public var debugDescription: String {
    return """
    Feed: (
      title: \(title),
      url: \(url),
      summary: \(String(describing: summary))
    )
    """
  }
}

extension Feed: Equatable, Hashable {

  static public func ==(lhs: Feed, rhs: Feed) -> Bool {
    return lhs.url == rhs.url
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}
