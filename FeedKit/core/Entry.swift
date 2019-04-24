//
//  Entry.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

/// Unique identifier of an entry.
public typealias EntryGUID = String

/// RSS item or Atom entry. In this domain we speak of `entry` to talk about
/// a child of a feed.
///
/// Identified by `guid`, entries are equal if their guids are equal.
public struct Entry: Redirectable, Imaginable {
  
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
  public let ts: Date?
  public let updated: Date
}

extension Entry: Codable {}

extension Entry : Cachable {
  
  /// The URL of the feed this entry belongs to.
  public var url: String {
    get { return feed }
  }
}

extension Entry : CustomStringConvertible {
  
  public var description: String {
    return "Entry: ( \(title), \(guid) )"
  }
}

extension Entry: Equatable, Hashable {
  
  static public func ==(lhs: Entry, rhs: Entry) -> Bool {
    return lhs.guid == rhs.guid
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(guid)
  }
}
