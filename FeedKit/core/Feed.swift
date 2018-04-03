//
//  Feed.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

public typealias FeedURL = String

public struct FeedID: Equatable {
  let rowid: Int64
  let url: FeedURL
  
  public static func ==(lhs: FeedID, rhs: FeedID) -> Bool {
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

/// Feeds are the central object of this framework.
///
/// The initializer is inconvenient for a reason: **it shouldn't be used
/// directly**. Instead users are expected to obtain their feeds from the
/// repositories provided by this framework. Two feeds are equal if they
/// have equal URLs.
///
/// A feed is required to, at least, have `title` and `url`.
public struct Feed: Cachable, Redirectable, Imaginable {
  public let author: String?
  public let iTunes: ITunesItem?
  public let image: String?
  public let link: String?
  public let originalURL: String?
  public let summary: String?
  public let title: String
  public let ts: Date?
  public let uid: FeedID? // TODO: Rename to feedID
  public let updated: Date?
  public let url: FeedURL
}

extension Feed : CustomStringConvertible {
  public var description: String {
    return "Feed: \(title)"
  }
}

extension Feed: CustomDebugStringConvertible {
  public var debugDescription: String {
    return """
    Feed(
    title: \(title),
    url: \(url),
    summary: \(String(describing: summary))
    )
    """
  }
}

extension Feed: Equatable {
  static public func ==(lhs: Feed, rhs: Feed) -> Bool {
    return lhs.url == rhs.url
  }
}

extension Feed: Hashable {
  public var hashValue: Int {
    get { return url.hashValue }
  }
}
