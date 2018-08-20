//
//  FetchSubscribedFeedsOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog.disabled

/// Synced data from iCloud might contain additional information, we don’t
/// have yet, and cannot aquire otherwise, like iTunes GUIDs and URLs of
/// pre-scaled images. Especially those smaller images are of interest to us,
/// because they enable a palpable improvement for the user. This operation not
/// only fetches the subscribed feeds, but integrates the iTunes metadata into
/// our local caches, mediating between the two tiers, `SubscriptionCaching`
/// and `Browsing`.
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
  
  /// A temporary cache of orginal URLs that have been redirected. Helpful to
  /// guard against reappearing redirects, resulting from incorrect handling in
  /// upstream systems.
  static var redirects = Set<FeedURL>()
  
  private func resubscribe(redirected feeds: [Feed]) throws {
    let redirects = feeds.filter { $0.isRedirected }
    
    guard !redirects.isEmpty else {
      return
    }
    
    os_log("updating redirected subscriptions: %{public}@", log: log,
           redirects.map {($0.originalURL, $0.url) })
    
    var originals = [FeedURL]()
    var resubscriptions = [Subscription]()
    
    for redirect in redirects {
      guard let original = redirect.originalURL else {
        continue
      }

      originals.append(original)
      
      // If an URL has already been redirected during this session, we avoid
      // resubscribeing to the new URL. Fuzzy logic, but resolving a concrete
      // issue at this moment.
      guard !FetchSubscribedFeedsOperation.redirects.contains(original) else {
        continue
      }
      
      FetchSubscribedFeedsOperation.redirects.insert(original)

      if original != redirect.url  {
        resubscriptions.append(Subscription(feed: redirect))
      }
    }
    
    try cache.remove(urls: originals)
    try cache.add(subscriptions: resubscriptions)
  }
  
  private func fetchFeeds(of subscriptions: [Subscription]) {
    guard !isCancelled, !subscriptions.isEmpty else {
      return done()
    }
    
    let urls = subscriptions.map { $0.url }
    
    var acc = [Feed]()
    
    // TODO: Extract into dependency chain
    op = browser.feeds(urls, ttl: .forever, feedsBlock: { error, feeds in
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
        try self.resubscribe(redirected: acc)
        
        // Preventing overwriting of existing iTunes items here,
        // not sure why though.
        let missing = acc.compactMap { $0.iTunes == nil ? $0.url : nil }
        let iTunes: [ITunesItem] = subscriptions.compactMap {
          guard missing.contains($0.url) else {
            return nil
          }
          return $0.iTunes
        }

        try self.browser.integrate(iTunesItems: iTunes)
      } catch {
        return self.done(error)
      }

      self.done()
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  override func start() {
    os_log("starting FetchSubscribedFeedsOperation", log: log, type: .debug)
    
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
