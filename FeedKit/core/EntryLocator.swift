//
//  EntryLocator.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

/// Entry locators identify a specific entry by `guid`, or skirt intervals
/// of entries from a specific feed, between now and `since`.
public struct EntryLocator {
  
  public let url: FeedURL
  public let since: Date
  public let guid: String?
  public let title: String?
  
  /// Initializes a newly created entry locator with the specified feed URL,
  /// time interval, and optional guid.
  ///
  /// This object might be used to locate multiple entries within an interval
  /// or to locate a single entry specifically using its guid.
  ///
  /// - Parameters:
  ///   - url: The URL of the feed.
  ///   - since: A date in the past when the interval begins.
  ///   - guid: An identifier to locate a specific entry.
  ///   - title: Arbitrary title for user-facing error messages.
  ///
  /// - Returns: The newly created entry locator.
  public init(
    url: FeedURL,
    since: Date? = nil,
    guid: String? = nil,
    title: String? = nil
  ) {
    self.url = url
    self.since = since ?? Date(timeIntervalSince1970: 0)
    self.guid = guid
    self.title = title
  }
  
  /// Creates a new locator from `entry`.
  ///
  /// - Parameter entry: The entry to locate.
  public init(entry: Entry) {
    self.init(url: entry.feed, since: entry.updated, guid: entry.guid,
              title: entry.title)
  }
  
  /// Returns a new `EntryLocator` with a modified *inclusive* `since`.
  public var including: EntryLocator {
    return EntryLocator(
      url: url, since: since.addingTimeInterval(-1), guid: guid)
  }
}

extension EntryLocator: Hashable {

  public func hash(into hasher: inout Hasher) {
    guard let guid = self.guid else {
      hasher.combine(url)
      hasher.combine(since)
      return
    }

    hasher.combine(guid)
  }

}

extension EntryLocator: Equatable {

  public static func ==(lhs: EntryLocator, rhs: EntryLocator) -> Bool {
    return lhs.hashValue == rhs.hashValue
  }

}

extension EntryLocator {
  
  public func encode(with coder: NSCoder) {
    coder.encode(self.guid, forKey: "guid")
    coder.encode(self.url, forKey: "url")
    coder.encode(self.since, forKey: "since")
    coder.encode(self.title, forKey: "title")
  }
  
  public init?(coder: NSCoder) {
    guard
      let guid = coder.decodeObject(forKey: "guid") as? String,
      let url = coder.decodeObject(forKey: "url") as? String else {
        return nil
    }
    let since = coder.decodeObject(forKey: "since") as? Date
    let title = coder.decodeObject(forKey: "title") as? String
    
    self.url = url
    self.since = since ?? Date(timeIntervalSince1970: 0)
    self.guid = guid
    self.title = title
  }
}

extension EntryLocator {
  
  /// Removes doublets, having the same GUID, and merges locators with similar
  /// URLs into a single locator with the longest time-to-live for that URL.
  static func reduce(
    _ locators: [EntryLocator],
    expanding: Bool = true
  ) -> [EntryLocator] {
    guard !locators.isEmpty else {
      return []
    }
    
    let unique = Array(Set(locators))
    
    var withGuids = [EntryLocator]()
    var withoutGuidsByUrl = [String : [EntryLocator]]()
    
    for loc in unique {
      if loc.guid == nil {
        let url = loc.url
        if let prev = withoutGuidsByUrl[url] {
          withoutGuidsByUrl[url] = prev + [loc]
        } else {
          withoutGuidsByUrl[url] = [loc]
        }
      } else {
        withGuids.append(loc)
      }
    }
    
    guard !withoutGuidsByUrl.isEmpty else {
      return withGuids
    }
    
    var withoutGuids = [EntryLocator]()
    
    let areInIncreasingOrder: (EntryLocator, EntryLocator) -> Bool = {
      return expanding ?
        { $0.since < $1.since } :
        { $0.since > $1.since }
    }()
    
    for it in withoutGuidsByUrl {
      let sorted = it.value.sorted(by: areInIncreasingOrder)

      guard let loc = sorted.first else {
        continue
      }
      
      withoutGuids.append(loc)
    }
    
    return withGuids + withoutGuids
  }
}
