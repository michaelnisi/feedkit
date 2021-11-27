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

/// A feed subscription.
public struct Subscription {
  public let url: FeedURL
  public let ts: Date
  public let iTunes: ITunesItem?
  public let title: String?
  
  public init(
    url: FeedURL,
    ts: Date? = nil,
    iTunes: ITunesItem? = nil,
    title: String? = nil
  ) {
    self.url = url
    self.ts = ts ?? Date()
    self.iTunes = iTunes
    self.title = title
  }
  
  public init(feed: Feed) {
    self.url = feed.url
    self.ts = Date()
    self.iTunes = feed.iTunes
    self.title = feed.title
  }
}

extension Subscription: Equatable {
  public static func ==(lhs: Subscription, rhs: Subscription) -> Bool {
    return lhs.url == rhs.url
  }
}

extension Subscription: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
  
}

extension Subscription: CustomStringConvertible {
  public var description: String {
    return "Subscription: { \(title ?? "Untitled"), \(url) }"
  }
}
