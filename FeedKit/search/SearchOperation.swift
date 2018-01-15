//
//  SearchOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

/// An operation for searching feeds and entries.
final class SearchOperation: SearchRepoOperation {
  
  var perFindGroupBlock: ((Error?, [Find]) -> Void)?
  
  var searchCompletionBlock: ((Error?) -> Void)?
  
  /// `FeedKitError.cancelledByUser` overrides passed errors.
  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    if let cb = searchCompletionBlock {
      // Dispatching synchronously here to only let this operation finish
      // after searchCompletionBlock completes.
      target.sync {
        cb(er)
      }
    }
    perFindGroupBlock = nil
    searchCompletionBlock = nil
    isFinished = true
  }
  
  /// Remotely request search and subsequently update the cache while falling
  /// back on stale feeds in stock. Finally, end the operation after applying
  /// the callback. Passing empty stock makes no sense.
  ///
  /// - Parameter stock: Stock of stale feeds to fall back on.
  fileprivate func request(_ stock: [Feed]? = nil) throws {
    // Capturing self as unowned to crash when we've mistakenly ended the
    // operation, here or somewhere else, inducing the system to release it.
    task = try svc.search(term: term) { [unowned self] payload, error in
      self.post(name: Notification.Name.FKRemoteResponse)
      
      var er: Error?
      defer {
        self.done(er)
      }
      
      guard !self.isCancelled else {
        return
      }
      
      guard error == nil else {
        er = FeedKitError.serviceUnavailable(error: error!)
        if let cb = self.perFindGroupBlock {
          if let feeds = stock {
            guard !feeds.isEmpty else { return }
            let finds = feeds.map { Find.foundFeed($0) }
            self.target.sync() {
              cb(nil, finds)
            }
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
          os_log("JSON parse errors: %{public}@", log: Search.log,  type: .error, errors)
        }
        
        try self.cache.update(feeds: feeds, for: self.term)
        
        guard
          !feeds.isEmpty,
          let cb = self.perFindGroupBlock,
          let cached = try self.cache.feeds(for: self.term, limit: 25) else {
            return
        }
        
        let finds = cached.map { Find.foundFeed($0) }
        self.target.sync() {
          cb(nil, finds)
        }
      } catch {
        er = error
      }
    }
  }
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    guard !term.isEmpty else {
      return done(FeedKitError.invalidSearchTerm(term: term))
    }
    isExecuting = true
    
    do {
      guard let cached = try cache.feeds(for: term, limit: 25) else {
        return try request()
      }
      
      if isCancelled { return done() }
      
      // If we match instead of equal, to yield more interesting results, we
      // cannot determine the age of a cached search because we might have
      // multiple differing timestamps. Using the median timestamp to determine
      // age works for both: equaling and matching.
      
      guard let ts = FeedCache.medianTS(cached) else {
        return done()
      }
      
      let shouldRefresh = FeedCache.stale(ts, ttl: CacheTTL.long.seconds)
      
      if shouldRefresh {
        try request(cached)
      } else {
        guard let cb = perFindGroupBlock else {
          return done()
        }
        let finds = cached.map { Find.foundFeed($0) }
        target.sync {
          cb(nil, finds)
        }
        return done()
      }
    } catch let er {
      done(er)
    }
  }
}
