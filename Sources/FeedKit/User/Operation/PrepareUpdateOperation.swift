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
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "User")

/// Prepares updating of the queue, producing entry locators from subscriptions
/// and currently newest episodes in queue. The resulting entry locators are
/// published via the `ProvidingLocators` interface.
final class PrepareUpdateOperation: Operation, ProvidingLocators {
  private(set) var error: Error?
  private(set) var locators = [EntryLocator]()
  
  private let cache: UserCaching

  init(cache: UserCaching) {
    self.cache = cache
  }

  override func main() {
    os_log("starting PrepareUpdateOperation", log: log, type: .info)
    
    do {
      let subscriptions = try cache.subscribed()
      let latest = try cache.newest()
      locators = latest.merged(with: subscriptions).sorted()
      
      os_log("prepared: %{public}i", log: log, type: .info, locators.count)
    } catch {
      self.error = error
    }
  }
}

extension Array where Element == EntryLocator {
  /// Returns latest entry locators of subscribed feeds.
  func merged(with subscriptions: [Subscription]) -> Set<EntryLocator> {
    var datesByURLs = [FeedURL: Date]()
      
    for loc in self {
      let url = loc.url
      if let prev = datesByURLs[url], prev > loc.since {
        continue
      }
      datesByURLs[url] = loc.since
    }
    
    return Set(subscriptions.map {
      let (url, ts) = ($0.url, $0.ts)

      if let prev = datesByURLs[url], prev > ts {
        return EntryLocator(url: url, since: prev)
      }

      return EntryLocator(url: url, since: ts)
    })
  }
}
