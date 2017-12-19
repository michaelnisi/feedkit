//
//  FeedsOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import Ola
import os.log

/// A concurrent `Operation` for getting hold of feeds.
final class FeedsOperation: BrowseOperation {
  
  // MARK: Callbacks
  
  var feedsBlock: ((Error?, [Feed]) -> Void)?
  
  var feedsCompletionBlock: ((Error?) -> Void)?
  
  // MARK: State
  
  let urls: [String]
  
  /// Returns an intialized `FeedsOperation` object. Refer to `BrowseOperation`
  /// for more.
  ///
  /// - parameter urls: The feed URLs to retrieve.
  init(
    cache: FeedCaching,
    svc: MangerService,
    urls: [String]
    ) {
    self.urls = urls
    super.init(cache: cache, svc: svc)
  }
  
  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    if let cb = feedsCompletionBlock {
      target.async {
        cb(er)
      }
    }
    feedsBlock = nil
    feedsCompletionBlock = nil
    isFinished = true
  }
  
  /// Request feeds and update the cache.
  ///
  /// - Parameters:
  ///   - urls: The URLs of the feeds to request.
  ///   - stale: The stale feeds to fall back on if the remote request fails.
  fileprivate func request(_ urls: [String], stale: [Feed]) throws {
    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }
    
    let cache = self.cache
    let feedsBlock = self.feedsBlock
    let target = self.target
    
    task = try svc.feeds(queries) { error, payload in
      self.post(name: Notification.Name.FKRemoteResponse)
      
      guard !self.isCancelled else {
        return self.done()
      }
      
      guard error == nil else {
        defer {
          let er = FeedKitError.serviceUnavailable(error: error!)
          self.done(er)
        }
        guard !stale.isEmpty, let cb = feedsBlock else {
          return
        }
        return target.async() {
          cb(nil, stale)
        }
      }
      
      guard payload != nil else {
        return self.done()
      }
      
      do {
        let (errors, feeds) = serialize.feeds(from: payload!)
        
        // TODO: Handle serialization errors
        //
        // Although, owning the remote service, we can be reasonably sure, these
        // objects are O.K., we should probably still handle these errors.
        
        assert(errors.isEmpty, "unhandled errors: \(errors)")
        
        let r = Entry.redirects(in: feeds)
        if !r.isEmpty {
          let urls = r.map { $0.originalURL! }
          try cache.remove(urls)
        }
        
        try cache.update(feeds: feeds)
        
        // TODO: Review
        //
        // This is risky: What if the cache modifies objects during the process
        // of storing them? Shouldn’t we better use those cached objects as our
        // result? This way, we’d also be able to put all foreign keys right on
        // our objects. The extra round trip should be neglectable.
        
        guard let cb = feedsBlock, !feeds.isEmpty else {
          return self.done()
        }
        
        target.async() {
          cb(nil, feeds)
        }
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }
  
  // TODO: Figure out why timeouts aren’t handled expectedly
  
  override func start() {
    guard !isCancelled else { return done() }
    isExecuting = true
    
    do {
      let target = self.target
      let cache = self.cache
      let feedsBlock = self.feedsBlock
      
      let (cached, stale, urlsToRequest) =
        try FeedsOperation.feeds(in: cache, with: urls, within: ttl.seconds)
      
      guard !isCancelled else { return done() }
      
      if urlsToRequest == nil {
        guard !cached.isEmpty else { return done() }
        guard let cb = feedsBlock else { return done() }
        target.async {
          cb(nil, cached)
        }
        return done()
      }
      if !cached.isEmpty {
        if let cb = feedsBlock {
          target.async {
            cb(nil, cached)
          }
        }
      }
      assert(!urlsToRequest!.isEmpty, "URLs to request must not be empty")
      
      if !reachable {
        if !stale.isEmpty {
          if let cb = feedsBlock {
            target.async {
              cb(nil, stale)
            }
          }
        }
        done()
      } else {
        try request(urlsToRequest!, stale: stale)
      }
    } catch let er {
      done(er)
    }
  }
}

// MARK: Accessing Cached Feeds

extension FeedsOperation {
  
  /// Retrieve feeds with the provided URLs from the cache and return a tuple
  /// containing cached feeds, stale feeds, and URLs of feeds currently not in
  /// the cache.
  ///
  /// - Parameters:
  ///   - cache: The cache to query.
  ///   - urls: An array of feed URLs.
  ///   - ttl: The limiting time stamp, a moment in the past.
  ///
  /// - Throws: May throw SQLite errors via Skull.
  ///
  /// - Returns: A tuple of cached feeds, stale feeds, and uncached URLs.
  static func feeds(in cache: FeedCaching, with urls: [String], within ttl: TimeInterval
    ) throws -> ([Feed], [Feed], [String]?) {
    let items = try cache.feeds(urls)
    let t = FeedCache.subtract(items, from: urls, with: ttl)
    return t
  }
  
}
