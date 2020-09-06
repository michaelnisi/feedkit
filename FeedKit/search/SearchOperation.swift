//
//  SearchOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import os.log
import Ola

private let log = OSLog.disabled

/// An operation for searching feeds and entries.
final class SearchOperation: SearchRepoOperation {
  
  var perFindGroupBlock: ((Error?, [Find]) -> Void)?
  
  var searchCompletionBlock: ((Error?) -> Void)?
  
  /// `FeedKitError.cancelledByUser` overrides passed errors.
  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    searchCompletionBlock?(er)
    
    perFindGroupBlock = nil
    searchCompletionBlock = nil
    task = nil
    
    isFinished = true
  }
  
  /// Remotely requests search and subsequently updates the cache while falling
  /// back on stale feeds in stock. Finally, end the operation after applying
  /// the callback. Passing empty stock makes no sense. If the remote service
  /// isn’t available, we’re falling back on `stock`.
  ///
  /// - Parameter stock: Stock of stale feeds to fall back on.
  fileprivate func request(_ stock: [Feed]? = nil) throws {
    guard isAvailable else {
      guard let feeds = stock, !feeds.isEmpty else {
        os_log("aborting: service not available", log: log)
        return done(FeedKitError.serviceUnavailable(nil))
      }
      os_log("falling back on stock: service not available", log: log)
      let finds = feeds.map { Find.foundFeed($0) }
      perFindGroupBlock?(nil, finds)
      return done(FeedKitError.serviceUnavailable(nil))
    }
    
    os_log("requesting: %@", log: log, type: .info, term)
    
    // Capturing self as unowned to crash when we've mistakenly ended the
    // operation, here or somewhere else, inducing the system to release it.
    task = try svc.search(term: term) {
      [unowned self] payload, error in
      var er: Error?

      defer {
        self.done(er)
      }
      
      guard !self.isCancelled else {
        return
      }
      
      guard error == nil else {
        er = FeedKitError.serviceUnavailable(error!)
        if let cb = self.perFindGroupBlock {
          if let feeds = stock {
            guard !feeds.isEmpty else { return }
            let finds = feeds.map { Find.foundFeed($0) }
            cb(nil, finds)
          }
        }
        return
      }
      
      guard payload != nil else {
        return
      }
      
      do {
        let (errors, feeds) = serialize.feeds(from: payload!)
        
        if !errors.isEmpty {
          os_log("JSON parse errors: %{public}@", log: log,  type: .error, errors)
        }
        
        try self.cache.update(feeds: feeds, for: self.term)

        guard
          !feeds.isEmpty,
          let cb = self.perFindGroupBlock,
          let cached = try self.cache.feeds(for: self.term, limit: 25) else {
          return
        }
        
        let finds = cached.map { Find.foundFeed($0) }
        
        guard !self.isCancelled else {
          return
        }
        
        cb(nil, finds)
      } catch {
        er = error
      }
    }
  }

  private var fetchingFeeds: FeedsOperation? {
    for dep in dependencies {
      if let op = dep as? FeedsOperation {
        return op
      }
    }
    return nil
  }

  /// Returns URLs of pathless `feeds`, like *Popaganda*, which brought this up,
  /// http://bitchradio.pagatim.libsynpro.com.
  private static func pathless(feeds: [Feed]) -> [FeedURL] {
    return feeds.compactMap {
      let urlString = $0.url
      guard let url = URL(string: urlString), url.path == "", urlString.last != "/" else {
        return nil
      }
      return urlString
    }
  }

  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    guard !term.isEmpty else {
      return done(FeedKitError.invalidSearchTerm(term: term))
    }
    
    os_log(
      """
      starting search operation: (
        term: %{public}@,
        reachable: %i,
        ttl: %{public}@
      )
      """, log: log, type: .info, term, isAvailable, ttl.description
    )
    
    isExecuting = true
    
    if let op = fetchingFeeds {
      guard op.error == nil else {
        return done(op.error)
      }
      
      guard let feed = op.feeds.first else {
        return done()
      }
      
      let find = Find.foundFeed(feed)
      perFindGroupBlock?(nil, [find])
      return done()
    }
    
    do {
      guard let cached = try cache.feeds(for: term, limit: 25) else {
        os_log("nothing cached", log: log, type: .info)
        return try request()
      }

      let problems = SearchOperation.pathless(feeds: cached)
      guard problems.isEmpty else {
        os_log("removing problematic feeds: %{public}@", log: log, problems)
        try cache.remove(problems)
        return try request()
      }

      os_log("cached: %{public}@", log: log, type: .info, cached)
      
      if isCancelled { return done() }
      
      // If we match instead of equal, to yield more interesting results, we
      // cannot determine the age of a cached search because we might have
      // multiple differing timestamps. Using the median timestamp to determine
      // age works for both: equaling and matching.
      
      guard let ts = FeedCache.medianTS(cached) else {
        return done()
      }
      
      let policy = recommend(for: CacheTTL.long)
      let shouldRefresh = FeedCache.stale(ts, ttl: policy.ttl)
      
      if shouldRefresh {
        try request(cached)
      } else {
        guard let cb = perFindGroupBlock else {
          return done()
        }
        let finds = cached.map { Find.foundFeed($0) }
        cb(nil, finds)
        return done()
      }
    } catch {
      done(error)
    }
  }
}
