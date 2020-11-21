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

private let log = OSLog.disabled

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

  /// Optionally reduces final entries result to just the latest entry.
  var isLatest = false

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
      guard !otherEntries.isEmpty else {
        os_log("not submitting empty entries", log: log)
        return
      }
    }

    os_log("%@: submitting: ( %@, %@ )",
           log: log, type: .info, self, otherEntries, String(describing: error))

    entries.formUnion(otherEntries)
    entriesBlock?(error, otherEntries)
  }
  
  /// If we have been cancelled, it’s OK to just say `done()` and be done.
  private func done(_ error: Error? = nil) {
    os_log("%@: done: %@",
           log: log, type: .info, self, String(describing: error))

    let er: Error? = {
      guard !isCancelled else {
        os_log("%@: cancelled", log: log, type: .info, self)
        return FeedKitError.cancelledByUser
      }
      self.error = self.error ?? error
      return self.error
    }()

    entriesCompletionBlock?(er)
    
    entriesBlock = nil
    entriesCompletionBlock = nil
    task = nil

    if isLatest, let l = (entries.sorted { $0.updated > $1.updated }.first) {
      // Reducing our result to just the latest entry.
      self.entries = Set([l])
    }

    isFinished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  ///   - stock: Cached entries as fallback option.
  private func request(
    _ locators: [EntryLocator],
    substantiating stock: [Entry] = []
  ) throws {
    os_log("%@: requesting entries: %@",
           log: log, type: .info, self, locators)

    let cache = self.cache
    let policy = recommend(for: ttl)

    task = try svc.entries(locators, cachePolicy: policy.http) {
      [weak self] error, payload in
      guard let me = self, !me.isCancelled else {
        self?.done()
        return
      }

      guard error == nil else {
        if !stock.isEmpty {
          os_log("** falling back on cached", log: log, type: .info)
          self?.submit(stock)
        }

        self?.done(FeedKitError.serviceUnavailable(error!))
        return
      }

      guard let p = payload else {
        os_log("%@: no payload", log: log, me)

        if !stock.isEmpty {
          os_log("** falling back on cached", log: log, type: .info)
          self?.submit(stock)
        }

        self?.done()
        return
      }

      do {
        let (errors, receivedEntries) = serialize.entries(from: p)
        
        guard !me.isCancelled else { return me.done() }

        if !errors.isEmpty {
          os_log("%@: invalid entries: %@",
                 log: log,  type: .error, me, errors)
        }

        guard !receivedEntries.isEmpty else {
          os_log("%@: no entries serialized from this payload: %@",
                 log: log, me, p)
          self?.done()
          return
        }
        
        os_log("%@: received entries: %@",
               log: log, type: .info, me, receivedEntries)
        
        // Handling HTTP Redirects

        let redirects = Entry.redirects(in: receivedEntries)
        var orginalURLsByURLs = [FeedURL: FeedURL]()

        if !redirects.isEmpty {
          os_log("%@: handling redirects: %@",
                 log: log, me, redirects)
          
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
          os_log("%@: ** replacing entries: %@",
                 log: log, type: .info, me, url)
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
        os_log("%@: feeds not cached: %@",
               log: log, me, urls)
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
          ttl: CacheTTL.short.defaults, http: .reloadIgnoringCacheData)
      }
    }
    
    return p
  }

  override func start() {
    os_log("%@: starting", log: log, type: .info, self)
    
    guard !isCancelled else { return done() }
    isExecuting = true
    
    guard error == nil, !locators.isEmpty else {
      os_log("%@: aborting: no locators provided",
             log: log, type: .info, self)
      return done(error)
    }
    
    let policy = recommend(for: ttl)
    
    if policy.ttl == 0, locators.count == 1, let l = locators.first, l.guid == nil {
      singlyForced = l.url
    }
    
    do {
      os_log("%@: trying cache: %@",
             log: log, type: .info, self, locators)

      let (cached, missing) = try cache.fulfill(locators, ttl: policy.ttl)

      guard !isCancelled else { return done() }

      os_log("""
      %@: (
        ttl: %f,
        cached: %@,
        missing: %@
      )
      """, log: log,
           type: .info,
           self,
           policy.ttl,
           cached.map { $0.title },
           missing
      )

      // Not submitting cached for singly forced reloads, because these might
      // be attempting to get rid of doublets.

      let isSinglyForced = singlyForced != nil

      if !isSinglyForced, !cached.isEmpty {
        submit(cached)
      }

      guard !missing.isEmpty else {
        return done()
      }

      guard isAvailable else {
        switch availability {
        case .no:
          return done(FeedKitError.serviceUnavailable(nil))
        case .offline:
          return done(FeedKitError.offline)
        case .presumably:
          fatalError("impossible state")
        }
      }

      if isSinglyForced {
        try request(missing, substantiating: cached)
      } else {
        try request(missing)
      }
    } catch {
      done(error)
    }
  }
}
