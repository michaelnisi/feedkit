//
//  Subscription.swift
//  FeedKit
//
//  Created by Michael Nisi on 07.05.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

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
  public var hashValue: Int {
    return url.hashValue
  }
}

extension Subscription: CustomStringConvertible {
  public var description: String {
    return "Subscription: { \(title ?? "Untitled"), \(url) }"
  }
}
