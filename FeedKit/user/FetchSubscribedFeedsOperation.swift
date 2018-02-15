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
    
    if let cb = feedsCompletionBlock {
      DispatchQueue.global().async {
        cb(er)
      }
    }
    
    feedsBlock = nil
    feedsCompletionBlock = nil
    
    isFinished = true
    op?.cancel()
    op = nil
  }
  private func fetchFeeds(of subscriptions: [Subscription]) {
    guard !isCancelled, !subscriptions.isEmpty else {
      return done()
    }
    
    let urls = subscriptions.map { $0.url }
    
    var acc = [Feed]()
    
    op = browser.feeds(urls, feedsBlock: { error, feeds in
      guard !self.isCancelled else {
        return
      }
      
      acc = acc + feeds
      
      DispatchQueue.global().async {
        self.feedsBlock?(feeds, error)
      }
    }) { error in
      guard !self.isCancelled, error == nil else {
        return self.done(error)
      }

      // Preventing overwriting of existing iTunes items here,
      // not sure why though.
      let missing = acc.flatMap { $0.iTunes == nil ? $0.url : nil }
      let iTunes: [ITunesItem] = subscriptions.flatMap {
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
