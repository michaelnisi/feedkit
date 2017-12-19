//
//  browse.swift
//  FeedKit
//
//  Created by Michael Nisi on 11.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import Ola
import os.log

/// A static structure representing the browse directory.
struct Browse {
  static let log = OSLog(subsystem: "ink.codes.feedkit", category: "browse")
}

// MARK: - FeedCaching

/// A persistent cache for feeds and entries.
public protocol FeedCaching {
  
  func update(feeds: [Feed]) throws
  func feeds(_ urls: [String]) throws -> [Feed]
  
  func update(entries: [Entry]) throws
  func entries(within locators: [EntryLocator]) throws -> [Entry]
  func entries(_ guids: [String]) throws -> [Entry]
  
  func remove(_ urls: [String]) throws
  
  /// Integrates iTunes metadata from `subscriptions`.
  func integrateMetadata(from subscriptions: [Subscription]) throws
  
  /// Queries the local `cache` for entries and returns a tuple of cached
  /// entries and unfullfilled entry `locators`, if any.
  ///
  /// - Parameters:
  ///   - locators: The selection of entries to fetch.
  ///   - ttl: The maximum age of entries to use.
  ///
  /// - Returns: A tuple of cached entries and URLs not satisfied by the cache.
  ///
  /// - Throws: Might throw database errors.
  func fulfill(_ locators: [EntryLocator], ttl: TimeInterval
  ) throws -> ([Entry], [EntryLocator])
  
}

extension FeedCaching {
  
  /// Find and return the newest item in the specified array of cachable items.
  /// Attention: this intentionally crashes if you pass an empty items array or
  /// if one of the items doesn't bear a timestamp.
  ///
  /// - Parameter items: The cachable items to iterate and compare.
  ///
  /// - Returns: The item with the latest timestamp.
  static func latest<T: Cachable> (_ items: [T]) -> T {
    return items.sorted {
      return $0.ts!.compare($1.ts! as Date) == .orderedDescending
      }.first!
  }
  
  /// Returns `true` if the specified timestamp is older than the specified time
  /// to live.
  ///
  /// - Parameters:
  ///   - ts: The timestamp to check if it's older than the specified ttl.
  ///   - ttl: The maximal age to allow.
  ///
  /// - Returns: `true` if the timestamp is older than the maximal age.
  static func stale(_ ts: Date, ttl: TimeInterval) -> Bool {
    return ts.timeIntervalSinceNow + ttl < 0
  }
  
  /// Figures out which URLs still need to be consulted, after items have been
  /// received from the cache, respecting a maximal time cached items stay
  /// valid (ttl) before becoming stale.
  ///
  /// Stale items are also returned, because they might useful to fall back on,
  /// in case the resulting request to refresh them fails.
  ///
  /// Because **entries don’t really get stale**, this function collects and
  /// adds them to the cached items array. Other item types, like feeds, are
  /// checked for their age and put in the cached items or, respectively, the
  /// stale items array.
  ///
  /// URLs of stale items, as well as URLs not represented in `items`, get added
  /// to the URLs array. Finally the latest entry of each feed is checked for
  /// its age and, if stale, its feed URL is added to the needed URLs.
  ///
  /// - Parameters:
  ///   - items: An array of items from the cache.
  ///   - urls: The originally requested URLs.
  ///   - ttl: The maximal age of cached items before they’re stale.
  ///
  /// - Returns: A tuple of cached items, stale items, and URLs still needed.
  static func subtract<T: Cachable> (
    _ items: [T], from urls: [String], with ttl: TimeInterval
  ) -> ([T], [T], [String]?) {
    guard !items.isEmpty else {
      return ([], [], urls.isEmpty ? nil : urls)
    }
    
    var cachedItems = [T]()
    var staleItems = [T]()
    
    var entriesByURLs = [FeedURL: [Entry]]()
    
    let cachedURLs = items.reduce([String]()) { acc, item in
      if let entry = item as? Entry {
        let url = entry.feed
        if entriesByURLs[url] == nil {
          entriesByURLs[url] = [Entry]()
        }
        entriesByURLs[url]?.append(entry)
        cachedItems.append(item)
        return acc
      }
      if !stale(item.ts!, ttl: ttl) {
        cachedItems.append(item)
        return acc + [item.url]
      } else {
        staleItems.append(item)
        return acc
      }
    }

    let cachedEntryURLs = urls.filter {
      guard let entries = entriesByURLs[$0], !entries.isEmpty else {
        return false
      }
      let entry = latest(entries)
      return !stale(entry.ts!, ttl: ttl)
    }

    let notCachedURLs = Array(Set(urls).subtracting(
      cachedURLs + cachedEntryURLs
    ))
    
    if notCachedURLs.isEmpty {
      return (cachedItems, [], nil)
    } else {
      return (cachedItems, staleItems, notCachedURLs)
    }
  }
  
}

/// The `FeedRepository` provides feeds and entries.
public final class FeedRepository: RemoteRepository {
  
  let cache: FeedCaching
  let svc: MangerService

  /// Initializes and returns a new feed repository.
  /// 
  /// - Parameters:
  ///   - cache: The feed cache to use.
  ///   - svc: The remote service.
  ///   - queue: The queue to execute this repository's operations.
  ///   - probe: A reachability probe to check this service.
  public init(
    cache: FeedCaching,
    svc: MangerService,
    queue: OperationQueue,
    probe: Reaching
  ) {
    self.cache = cache
    self.svc = svc

    super.init(queue: queue, probe: probe)
  }

}

// MARK: - Browsing

extension FeedRepository: Browsing {
  
  public func integrateMetadata(
    from subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)?
  ) -> Void {
    os_log("integrating metadata from: %{public}@", log: Browse.log, type: .debug,
           String(describing: subscriptions))
    
    let cache = self.cache
    
    queue.addOperation {
      guard let target = OperationQueue.current?.underlyingQueue else {
        return
      }
      
      var er: Error?
      
      defer {
        target.async {
          completionBlock?(er)
        }
      }
      
      do {
        try cache.integrateMetadata(from: subscriptions)
      } catch {
        er = error
      }
    }
  }
  
  /// Use this method to get feeds for the specified `urls`. The `feedsBlock`
  /// callback block might get called multiple times. Each iteration providing
  /// groups of feeds as they become available. The order of these feeds and
  /// groups is not specified. The second callback block `feedsCompletionBlock` 
  /// is called at the end, but before the standard `completionBlock`.
  ///
  /// - Parameters:
  ///   - urls: An array of feed URLs.
  ///   - feedsBlock: Applied zero, one, or two times with the requested
  /// feeds. The error defined in this callback is not being used at the moment.
  ///   - feedsError: The group error of this iteration.
  ///   - feeds: The resulting feeds of this iteration.
  ///   - feedsCompletionBlock: Applied when no more `feedBlock` is to
  /// be expected.
  ///   - error: The final error of this operation.
  ///
  /// - Returns: The executing operation.
  public func feeds(
    _ urls: [String],
    feedsBlock: @escaping (_ feedsError: Error?, _ feeds: [Feed]) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FeedsOperation(
      cache: cache,
      svc: svc,
      urls: urls
    )

    let r = reachable()
    let uri = urls.count == 1 ? urls.first : nil
    let ttl = timeToLive(
      uri,
      force: false,
      reachable: r,
      status: svc.client.status,
      ttl: CacheTTL.short
    )

    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    op.reachable = r
    op.ttl = ttl

    queue.addOperation(op)

    return op
  }
  
  public func makeEntriesOperation() -> Operation {
    let op = EntriesOperation(
      cache: cache,
      svc: svc
    )
    return op
  }

  /// Fetches entries for the given locators, aggregating local and remote data.
  ///
  /// Locators provide a feed URL, a moment in the past, and an optional guid.
  /// This way, you can limit the requested entries to specific time ranges,
  /// skipping entries you already have.
  ///
  /// The GUID is used to get specific entries already in the cache. If there is
  /// no entry with this GUID in the cache, feed URL and interval are used to
  /// request the entry from the remote service. It cannot be guaranteed to be
  /// successful, because the remote feed might have removed the requested entry
  /// in the meantime.
  ///
  /// This method uses a local cache and a remote service to fulfill the request.
  /// If the remote service is unavavailable, it tries to fall back on the cache
  /// and might end up skipping requested entries. This is made transparent by
  /// an error passed to the entries completion block.
  ///
  /// Callbacks are dispatched on the main queue: `DispatchQueue.main`.
  /// 
  /// - Parameters:
  ///   - locators: The locators for the entries to request.
  ///   - force: Force remote request ignoring the cache. As this
  /// produces load on the server, it is limited to once per hour per feed. If
  /// you pass multiple locators, the force parameter is ignored.
  ///
  ///   - entriesBlock: Applied zero, one, or two times passing fetched
  /// and/or cached entries. The error is currently not in use.
  ///   - entriesError: An optional error, specific to these entries.
  ///   - entries: All or some of the requested entries.
  ///
  ///   - entriesCompletionBlock: The completion block is applied when
  /// all entries have been dispatched.
  ///   - error: The, optional, final error of this operation, as a whole.
  ///
  /// - Returns: The executing operation.
  public func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = EntriesOperation(
      cache: cache,
      svc: svc,
      locators: locators
    )

    let r = reachable()
    let uri = locators.count == 1 ? locators.first?.url : nil
    let ttl = timeToLive(
      uri,
      force: force,
      reachable: r,
      status: svc.client.status,
      ttl: CacheTTL.short
    )

    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    op.reachable = r
    op.ttl = ttl

    // We have to get the according feeds, before we can request their entries,
    // because we cannot update entries of uncached feeds. Providing a place to
    // composite operations, like this, is an advantage of interposing
    // repositories, compared to exposing operations directly.

    let urls = locators.map { $0.url }

    let dep = FeedsOperation(
      cache: cache,
      svc: svc,
      urls: urls
    )

    dep.ttl = CacheTTL.forever
    dep.reachable = r

    dep.feedsBlock = { error, feeds in
      if let er = error {
        os_log("could not fetch feeds: %{public}@", log: Browse.log, type: .error,
               String(reflecting: er))
      }
    }

    dep.feedsCompletionBlock = { error in
      if let er = error {
        os_log("could not fetch feeds: %{public}@", log: Browse.log, type: .error,
               String(reflecting: er))
      }
    }

    assert(dep.ttl == CacheTTL.forever)

    op.addDependency(dep)

    queue.addOperation(op)
    queue.addOperation(dep)

    return op
  }

  public func entries(
    _ locators: [EntryLocator],
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    return self.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }
}

