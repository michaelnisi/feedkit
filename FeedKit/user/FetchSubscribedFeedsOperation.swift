//
//  FetchSubscribedFeedsOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

/// Synced data from iCloud might contain additional information, we don’t
/// have yet, and cannot aquire otherwise, like iTunes GUIDs and URLs of
/// pre-scaled images. Especially those smaller images are of interest to us,
/// because they enable a palpable improvement for the user. This operation not
/// only fetches the subscribed feeds, but integrates the iTunes metadata into
/// our local caches.
final class FetchSubscribedFeedsOperation: FeedKitOperation {
  
  let browser: Browsing
  let cache: SubscriptionCaching
  
  init(browser: Browsing, cache: SubscriptionCaching) {
    self.browser = browser
    self.cache = cache
  }
  
  var feedsBlock: (([Feed], Error?) -> Void)?
  var feedsCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the feeds.
  weak fileprivate var op: Operation?
  
  private func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    feedsCompletionBlock?(er)

    feedsBlock = nil
    feedsCompletionBlock = nil
    
    isFinished = true
    op?.cancel()
    op = nil
  }
  
  private func update(redirected feeds: [Feed]) throws {
    let r = feeds.filter { $0.isRedirected }
    guard !r.isEmpty else {
      return
    }
    
    os_log("resubscribing to redirected feeds: %{public}@", log: User.log,
           r.map {($0.originalURL, $0.url) })
    
    try cache.remove(urls: r.compactMap { $0.originalURL })
    let s = r.map { Subscription(feed: $0) }
    try cache.add(subscriptions: s)
  }
  
  private func fetchFeeds(of subscriptions: [Subscription]) {
    guard !isCancelled, !subscriptions.isEmpty else {
      return done()
    }
    
    let urls = subscriptions.map { $0.url }
    
    var acc = [Feed]()
    
    // TODO: Extract into dependency chain
    op = browser.feeds(urls, feedsBlock: { error, feeds in
      guard !self.isCancelled else {
        return
      }
      
      acc = acc + feeds
      
      self.feedsBlock?(feeds, error)
    }) { error in
      guard !self.isCancelled, error == nil else {
        return self.done(error)
      }
      
      do {
        try self.update(redirected: acc)
      } catch {
        return self.done(error)
      }

      // Preventing overwriting of existing iTunes items here,
      // not sure why though.
      let missing = acc.compactMap { $0.iTunes == nil ? $0.url : nil }
      let iTunes: [ITunesItem] = subscriptions.compactMap {
        guard missing.contains($0.url) else {
          return nil
        }
        return $0.iTunes
      }
      
      self.browser.integrate(iTunesItems: iTunes) { error in
        self.done(error)
      }
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  override func start() {
    os_log("starting FetchSubscribedFeedsOperation", log: User.log, type: .debug)
    
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    do {
      let subscriptions = try cache.subscribed()
      fetchFeeds(of: subscriptions)
    } catch {
      done(error)
    }
  }
  
}
