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

/// Unique identifier of an entry.
public typealias EntryGUID = String

/// RSS item or Atom entry. In this domain we speak of `entry` to talk about
/// a child of a feed.
///
/// Identified by `guid`, entries are equal if their guids are equal.
public struct Entry: Redirectable {
  public let author: String?
  public let duration: Int?
  public let enclosure: Enclosure?
  public let feed: FeedURL
  public let feedImage: String?
  public let feedTitle: String?
  public let guid: EntryGUID
  public let iTunes: ITunesItem?
  public let image: String?
  public let link: String?
  public let originalURL: String?
  public let subtitle: String?
  public let summary: String?
  public let title: String
  public let ts: Date
  public let updated: Date
}

extension Entry: Codable {}

extension Entry : Cachable {
  /// The URL of the feed this entry belongs to.
  public var url: String { feed }
}

extension Entry : CustomStringConvertible {
  public var description: String {
    "Entry: ( \(title), \(guid), \(url), \(originalURL ?? "") )"
  }
}

extension Entry: Equatable, Hashable {
  static public func ==(lhs: Entry, rhs: Entry) -> Bool {
    lhs.guid == rhs.guid
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(guid)
  }
}
