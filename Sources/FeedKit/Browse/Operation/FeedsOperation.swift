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
import MangerKit
import Ola
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "feeds")

/// A concurrent `Operation` for accessing feeds.
final class FeedsOperation: BrowseOperation, FeedURLsDependent, ProdvidingFeeds {
  static var urlCache = DateCache(ttl: 3600)
  
  // MARK: ProvidingFeeds
  
  private(set) var error: Error?
  private(set) var feeds = Set<Feed>()
  private(set) var redirects = Set<FeedURL>()

  // MARK: Callbacks

  var feedsBlock: ((Error?, [Feed]) -> Void)?
  var feedsCompletionBlock: ((Error?) -> Void)?
  var redirectsBlock: (([FeedURL]) -> Void)?

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
    feedsBlock?(error, otherFeeds)
  }

  private func done(_ error: Error? = nil) {
    let er: Error? = {
      guard !isCancelled else {
        os_log("%{public}@: cancelled", log: log, type: .info, self)
        return FeedKitError.cancelledByUser
      }
      self.error = self.error ?? error
      return self.error
    }()
    
    feedsCompletionBlock?(er)
    
    feedsBlock = nil
    feedsCompletionBlock = nil
    task = nil
    
    redirectsBlock = nil
    
    isFinished = true
  }

  /// Request feeds and update the cache.
  ///
  /// - Parameters:
  ///   - urls: The URLs of the feeds to request.
  ///   - stale: The stale feeds to fall back on if the remote request fails.
  private func request(_ urls: [String], stale: [Feed]) throws {
    os_log("%{public}@: requesting feeds: %{public}i", log: log, type: .info, self, urls.count)

    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }

    let cache = self.cache
    let policy = recommend(for: ttl)

    task = try svc.feeds(queries, cachePolicy: policy.http) { [unowned self] error, payload in
      guard !isCancelled else {
        done()
        return
      }

      guard error == nil else {
        let er = FeedKitError.serviceUnavailable(error!)
        if !stale.isEmpty {
          submit(stale)
        }
        done(er)
        return
      }

      guard payload != nil else {
        done()
        return
      }

      do {
        let (_, feeds) = Serialize.feeds(from: payload!)
        
        guard !isCancelled else { return done() }

        // https://github.com/michaelnisi/feedkit/issues/22
//        assert(errors.isEmpty, "unhandled: \(errors)")

        var freshURLs = Set(urls)

        // Handling HTTP Redirects

        let redirects = Entry.redirects(in: feeds)
        var orginalURLsByURLs = [String: String]()
        
        if !redirects.isEmpty {
          os_log("handling redirects: %{public}i", log: log, redirects.count)
          
          var redirectedURLs = [String]()
          for r in redirects {
            guard let originalURL = r.originalURL else {
              fatalError("original URL required")
            }
            freshURLs.remove(originalURL)
            freshURLs.insert(r.url)
            redirectedURLs.append(originalURL)
            
            orginalURLsByURLs[r.url] = r.originalURL
          }
          
          if !redirectedURLs.isEmpty {
            try cache.remove(redirectedURLs)
            self.redirects = Set(redirectedURLs)
            redirectsBlock?(redirectedURLs)
          }
        }

        try cache.update(feeds: feeds)
        
        guard !isCancelled else { return done() }
        
        // Preparing Result
        
        let cachedFeeds = try cache.feeds(Array(freshURLs))
        if !cachedFeeds.isEmpty {
          if orginalURLsByURLs.isEmpty {
            submit(cachedFeeds)
          } else {
            submit(cachedFeeds.map {
              guard let originalURL = orginalURLsByURLs[$0.url] else {
                return $0
              }
              // We don’t persist original URLs and our feed structs are
              // unmutable, so we are returning a new one adding the
              // original URL.
              return Feed(
                author: $0.author,
                iTunes: $0.iTunes,
                image: $0.image,
                link: $0.link,
                originalURL: originalURL,
                summary: $0.summary,
                title: $0.title,
                ts: $0.ts,
                uid: $0.uid,
                updated: $0.updated,
                url: $0.url
              )
            })
          }
        }
        done()
      } catch {
        done(error)
      }
    }
  }

  override func recommend(for: CacheTTL) -> CachePolicy {
    let p = super.recommend(for: ttl)
    
    // Guarding against excessive cache ignorance, allowing one forced refresh
    // per day.
    
    if p.ttl == 0 {
      guard
        urls.count == 1,
        let url = urls.first,
        FeedsOperation.urlCache.update(url) else {
        return CachePolicy(
          ttl: CacheTTL.long.defaults, http: .useProtocolCachePolicy)
      }
    }
    
    return p
  }
  
  override func start() {
    os_log("%{public}@: starting", log: log, type: .info, self)
    
    guard !isCancelled else { return done() }
    isExecuting = true

    guard error == nil, !urls.isEmpty else {
      os_log("%{public}@: aborting: no URLs provided",
             log: log, type: .info, self)
      return done(error)
    }
    
    do {
      os_log("%{public}@: trying cache: %{public}i", log: log, type: .info, self, urls.count)
      
      let items = try cache.feeds(urls)
      let policy = recommend(for: ttl)
      let (cached, stale, needed) = FeedCache.subtract(
        items, from: urls, with: policy.ttl
      )

      guard !isCancelled else {
        return done()
      }
      
      // Why, compared to EntriesOperation, is needed optional?
      
      os_log("""
      %{public}@: (
        ttl: %f,
        cached: %{public}i,
        stale: %{public}i,
        missing: %{public}i
      )
      """, log: log, type: .info, self, policy.ttl, cached.count, stale.count, (needed ?? []).count)

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

      if !isAvailable {
        if !stale.isEmpty {
          submit(stale)
          done()
        } else {
          done(FeedKitError.serviceUnavailable(nil))
        }
      } else {
        try request(urlsToRequest, stale: stale)
      }
    } catch {
      done(error)
    }
  }
}
