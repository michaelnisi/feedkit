//
//  EntriesOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import Ola
import os.log

/// A concurrent `Operation` for accessing entries.
final class EntriesOperation: BrowseOperation, LocatorsDependent, ProvidingEntries {
  
  /// URLs that have been reloaded ignoring the cache in the last hour.
  static var ignorants = DateCache(ttl: 3600)

  // MARK: ProvidingEntries

  private(set) var error: Error?
  private(set) var entries = Set<Entry>()

  // MARK: Callbacks

  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?

  private var _locators: [EntryLocator]?
  private lazy var locators: [EntryLocator] = {
    guard let locs = _locators else {
      do {
        _locators = try findLocators()
      } catch {
        switch error {
        case ProvidingError.missingLocators:
          fatalError(String(describing: error))
        default:
          self.error = error
          _locators = []
        }
      }
      return _locators!
    }
    return locs
  }()

  /// Creates an entries operation with the specified cache, service, dispatch
  /// queue, and entry locators.
  ///
  /// Refer to `BrowseOperation` for more information.
  ///
  /// - Parameter locators: The selection of entries to fetch.
  init(cache: FeedCaching, svc: MangerService, locators: [EntryLocator]? = nil) {
    self._locators = locators
    super.init(cache: cache, svc: svc)
  }
  
  private func submit(_ otherEntries: [Entry], error: Error? = nil) {
    if error == nil {
      assert(!otherEntries.isEmpty)
    }
    entries.formUnion(otherEntries)
    entriesBlock?(error, otherEntries)
  }
  
  /// If we have been cancelled, it’s OK to just say `done()` and be done.
  private func done(_ error: Error? = nil) {
    let er: Error? = {
      guard !isCancelled else {
        os_log("%{public}@: cancelled", log: Browse.log, type: .debug, self)
        return FeedKitError.cancelledByUser
      }
      self.error = self.error ?? error
      return self.error
    }()
    

    entriesCompletionBlock?(er)
    
    entriesBlock = nil
    entriesCompletionBlock = nil
    task = nil

    isFinished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  private func request(_ locators: [EntryLocator]) throws {
    os_log("%{public}@: requesting entries: %{public}@",
           log: Browse.log, type: .debug, self, locators)

    let cache = self.cache
    let policy = recommend(for: ttl)

    task = try svc.entries(locators, cachePolicy: policy.http) {
      [weak self] error, payload in
      guard let me = self, !me.isCancelled else {
        self?.done()
        return
      }

      guard error == nil else {
        self?.done(FeedKitError.serviceUnavailable(error!))
        return
      }

      guard let p = payload else {
        os_log("%{public}@: no payload", log: Browse.log, me)
        self?.done()
        return
      }

      do {
        let (errors, receivedEntries) = serialize.entries(from: p)
        
        guard !me.isCancelled else { return me.done() }

        if !errors.isEmpty {
          os_log("%{public}@: invalid entries: %{public}@",
                 log: Browse.log,  type: .error, me, errors)
        }

        guard !receivedEntries.isEmpty else {
          os_log("%{public}@: no entries serialized from this payload: %{public}@",
                 log: Browse.log, me, p)
          self?.done()
          return
        }
        
        os_log("%{public}@: received entries: %{public}@",
               log: Browse.log, type: .debug, me, receivedEntries)
        
        // Handling HTTP Redirects

        let redirects = Entry.redirects(in: receivedEntries)
        var orginalURLsByURLs = [FeedURL: FeedURL]()

        if !redirects.isEmpty {
          os_log("%{public}@: handling redirects: %{public}@",
                 log: Browse.log, me, redirects)
          
          let originalURLs: [FeedURL] = redirects.compactMap {
            guard let originalURL = $0.originalURL else {
              return nil
            }
            orginalURLsByURLs[$0.url] = originalURL
            return originalURL
          }
          
          if !originalURLs.isEmpty {
            try cache.remove(originalURLs)
          }
        }

        if let url = me.singlyForced {
          os_log("%{public}@: ** replacing entries: %{public}@",
                 log: Browse.log, type: .debug, me, url)
          try cache.removeEntries(matching: [url])
        }
        try cache.update(entries: receivedEntries)
        
        guard !me.isCancelled else { return me.done() }
        
        // Preparing Result

        // The cached entries, contrary to the freshly received entries, have
        // more properties. Also, we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve the freshly updated entries from the cache,
        // relying on SQLite’s speed.

        let (cached, missing) = try cache.fulfill(locators, ttl: .infinity)
        
        guard !me.isCancelled else { return me.done() }

        let error: FeedKitError? = {
          guard !missing.isEmpty else {
            return nil
          }
          return FeedKitError.missingEntries(locators: missing)
        }()
        
        let a = Set(cached)
        let b = self?.entries ?? Set<Entry>()
        let fresh = Array(a.subtracting(b))
        
        if !fresh.isEmpty {
          if orginalURLsByURLs.isEmpty {
            self?.submit(fresh, error: error)
          } else {
            self?.submit(fresh.map {
              guard let originalURL = orginalURLsByURLs[$0.url] else {
                return $0
              }
              return Entry(
                author: $0.author,
                duration: $0.duration,
                enclosure: $0.enclosure,
                feed: $0.feed,
                feedImage: $0.feedImage,
                feedTitle: $0.feedTitle,
                guid: $0.guid,
                iTunes: $0.iTunes,
                image: $0.image,
                link: $0.link,
                originalURL: originalURL,
                subtitle: $0.subtitle,
                summary: $0.summary,
                title: $0.title,
                ts: $0.ts,
                updated: $0.updated
              )
            }, error: error)
          }
        } else if error != nil {
          self?.submit([], error: error)
        }

        self?.done()
      } catch FeedKitError.feedNotCached(let urls) {
        os_log("%{public}@: feeds not cached: %{public}@",
               log: Browse.log, me, urls)
        self?.done()
      } catch {
        self?.done(error)
      }
    }
  }
  
  private var singlyForced: FeedURL?
  
  override func recommend(for ttl: CacheTTL) -> CachePolicy {
    let p = super.recommend(for: ttl)
    
    // Guarding against excessive cache ignorance, allowing one forced refresh
    // per hour.
    
    if p.ttl == 0 {
      guard
        locators.count == 1,
        let url = locators.first?.url,
        EntriesOperation.ignorants.update(url) else {
        return CachePolicy(
          ttl: CacheTTL.short.defaults, http: .useProtocolCachePolicy)
      }
    }
    
    return p
  }

  override func start() {
    os_log("%{public}@: starting", log: Browse.log, type: .debug, self)
    
    guard !isCancelled else { return done() }
    isExecuting = true
    
    guard error == nil, !locators.isEmpty else {
      os_log("%{public}@: aborting: no locators provided",
             log: Browse.log, type: .debug, self)
      return done(error)
    }
    
    let policy = recommend(for: ttl)
    
    if policy.ttl == 0, locators.count == 1, let l = locators.first, l.guid == nil {
      singlyForced = l.url
    }
    
    do {
      os_log("%{public}@: trying cache: %{public}@",
             log: Browse.log, type: .debug, self, locators)

      let (cached, missing) = try cache.fulfill(locators, ttl: policy.ttl)

      guard !isCancelled else { return done() }

      os_log("""
      %{public}@: (
        ttl: %f,
        cached: %{public}@,
        missing: %{public}@
      )
      """, log: Browse.log,
           type: .debug,
           self,
           policy.ttl,
           cached.map { $0.title },
           missing
      )

      if !cached.isEmpty {
        submit(cached)
      }

      guard !missing.isEmpty else {
        return done()
      }

      if !isAvailable {
        done(FeedKitError.offline)
      } else {
        try request(missing)
      }
    } catch {
      done(error)
    }
  }
}
