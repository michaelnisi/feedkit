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

        // Updating and rereading to produce merged results.

        try cache.update(feeds: feeds)
        let cachedFeeds = try cache.feeds(Array(freshURLs))

        guard let cb = feedsBlock, !cachedFeeds.isEmpty else {
          return self.done()
        }

        target.async() {
          cb(nil, cachedFeeds)
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

      let items = try cache.feeds(urls)
      let (cached, stale, urlsToRequest) = FeedCache.subtract(
        items, from: urls, with: ttl.seconds
      )

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

