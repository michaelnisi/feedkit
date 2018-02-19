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

/// A concurrent `Operation` for accessing feeds.
final class FeedsOperation: BrowseOperation, FeedURLsDependent {
  
  // MARK: ProvidingFeeds
  
  private(set) var error: Error?
  private(set) var feeds = Set<Feed>()

  // MARK: Callbacks

  var feedsBlock: ((Error?, [Feed]) -> Void)?
  var feedsCompletionBlock: ((Error?) -> Void)?

  private var _urls: [String]?
  
  private var urls: [String] {
    guard let actualURLs = _urls else {
      do {
        _urls = try findFeedURLs()
      } catch {
        self.error = error
        _urls = []
      }
      return _urls!
    }
    return actualURLs
  }

  init(cache: FeedCaching, svc: MangerService, urls: [String]? = nil) {
    self._urls = urls
    super.init(cache: cache, svc: svc)
  }
  
  /// Use submit and done to handle final results, instead of individually
  /// affecting the state of this operation.
  private func submit(_ otherFeeds: [Feed], error: Error? = nil) {
    assert(!otherFeeds.isEmpty)
    feeds.formUnion(otherFeeds)
    target.sync {
      feedsBlock?(error, otherFeeds)
    }
  }

  private func done(_ error: Error? = nil) {
    let er: Error? = {
      guard !isCancelled else {
        return FeedKitError.cancelledByUser
      }
      self.error = self.error ?? error
      return self.error
    }()
    
    let cb = feedsCompletionBlock
    target.sync { cb?(er) }
    
    feedsBlock = nil
    feedsCompletionBlock = nil
    task = nil
    
    isFinished = true
  }

  /// Request feeds and update the cache.
  ///
  /// - Parameters:
  ///   - urls: The URLs of the feeds to request.
  ///   - stale: The stale feeds to fall back on if the remote request fails.
  private func request(_ urls: [String], stale: [Feed]) throws {
    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }

    let cache = self.cache

    task = try svc.feeds(queries) { [weak self] error, payload in
      guard let me = self, !me.isCancelled else {
        self?.done()
        return
      }

      guard error == nil else {
        let er = FeedKitError.serviceUnavailable(error: error!)
        if !stale.isEmpty {
          self?.submit(stale)
        }
        self?.done(er)
        return
      }

      guard payload != nil else {
        self?.done()
        return
      }

      do {
        let (errors, feeds) = serialize.feeds(from: payload!)
        
        guard !me.isCancelled else { return me.done() }
        
        // TODO: Handle serialization errors
        //
        // Although, owning the remote service, we can be reasonably sure, these
        // objects are OK, we should probably still handle these errors.

        assert(errors.isEmpty, "unhandled errors: \(errors)")

        var freshURLs = Set(urls)

        // Handling HTTP Redirects

        let redirects = Entry.redirects(in: feeds)
        var redirectedURLs = [String]()
        for r in redirects {
          guard let originalURL = r.originalURL else {
            fatalError("original URL required")
          }
          freshURLs.remove(originalURL)
          freshURLs.insert(r.url)
          redirectedURLs.append(originalURL)
        }

        if !redirectedURLs.isEmpty {
          try cache.remove(redirectedURLs)
        }

        try cache.update(feeds: feeds)
        
        guard !me.isCancelled else { return me.done() }
        
        // Preparing Result
        
        let cachedFeeds = try cache.feeds(Array(freshURLs))
        if !cachedFeeds.isEmpty {
          self?.submit(cachedFeeds)
        }
        self?.done()
      } catch {
        self?.done(error)
      }
    }
  }

  override func start() {
    os_log("starting FeedsOperation", log: Browse.log, type: .debug)
    
    guard !isCancelled else { return done() }
    isExecuting = true

    guard error == nil, !urls.isEmpty else {
      os_log("aborting FeedsOperation: no URLs provided",
             log: Browse.log, type: .debug)
      return done(error)
    }
    
    do {
      os_log("trying cache: %{public}@", log: Browse.log, type: .debug, urls)
      
      let items = try cache.feeds(urls)
      let (cached, stale, needed) = FeedCache.subtract(
        items, from: urls, with: ttl.seconds
      )

      guard !isCancelled else { return done() }
      
      // Why, compared to EntriesOperation, is needed optional?
      
      os_log("cached: %{public}@", log: Browse.log, type: .debug, cached)
      os_log("missing: %{public}@", log: Browse.log, type: .debug,
             String(describing: needed))

      guard let urlsToRequest = needed else {
        if !cached.isEmpty {
          submit(cached)
        }
        return done()
      }
      
      if !cached.isEmpty {
        submit(cached)
      }
      
      assert(!urlsToRequest.isEmpty, "URLs to request must not be empty")

      if !reachable {
        if !stale.isEmpty {
          submit(stale)
          done()
        } else {
          done(FeedKitError.offline)
        }
      } else {
        try request(urlsToRequest, stale: stale)
      }
    } catch {
      done(error)
    }
  }
}

