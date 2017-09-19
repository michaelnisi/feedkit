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

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "browse")

/// Although I despise inheritance, this is an abstract `Operation` to be
/// extended by operations used in the feed repository. It provides common
/// properties for the, currently two: feed and entries; operations of the
/// browsing API.
class BrowseOperation: SessionTaskOperation {
  let cache: FeedCaching
  let svc: MangerService
  let target: DispatchQueue

  /// Initialize and return a new feed repo operation.
  /// 
  /// - Parameters:
  ///   - cache: The persistent feed cache.
  ///   - svc: The remote service to fetch feeds and entries.
  init(cache: FeedCaching, svc: MangerService) {
    self.cache = cache
    self.svc = svc
    
    self.target = {
      guard let q = OperationQueue.current?.underlyingQueue else {
        print("** target: falling back on main")
        return DispatchQueue.main
      }
      print("** target: \(q)")
      return q
    }()
  }
}

// MARK: HTTP

extension BrowseOperation {
  
  static func redirects(in items: [Redirectable]) -> [Redirectable] {
    return items.filter {
      guard let originalURL = $0.originalURL, originalURL != $0.url else {
        return false
      }
      return true
    }
  }
  
}

// MARK: Accessing Cached Items

extension BrowseOperation {
  
  // In this file, we use static functions to expose some logic for testing.

  /// Subtract two arrays of strings. Note that the order of the resulting array
  /// is undefined.
  ///
  /// - Parameters:
  ///   - a: An array of strings.
  ///   - b: The array of strings to subtract from.
  ///
  /// - Returns: Strings from `a` that are not in `b`.
  static func subtract(strings a: [String], from b: [String]) -> [String] {
    let setA = Set(a)
    let setB = Set(b)
    let diff = setB.subtracting(setA)
    return Array(diff)
  }
  
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
  
  /// Find out which URLs still need to be consulted, after items have been
  /// received from the cache, while respecting a maximal time cached items stay
  /// valid (ttl) before becoming stale.
  ///
  /// The stale items are also returned, because they might be used to fall back
  /// on, in case something goes wrong further down the road.
  ///
  /// Because **entries never become stale**, this function collects and adds them
  /// to the cached items array. Other item types, like feeds, are checked for
  /// their age and put in the cached items or, respectively, the stale items
  /// array.
  ///
  /// URLs of stale items, as well as URLs not present in the specified items
  /// array, are added to the URLs array. Finally the latest entry of each feed is
  /// checked for its age and, if stale, its feed URL is added to the URLs.
  ///
  /// - Parameters:
  ///   - items: An array of items from the cache.
  ///   - urls: The originally requested URLs.
  ///   - ttl: The maximal age of cached items before they’re stale.
  ///
  /// - Returns: A tuple of cached items, stale items, and URLs still to consult.
  static func subtract<T: Cachable> (
    items: [T], from urls: [String], with ttl: TimeInterval)
    -> ([T], [T], [String]?) {
    guard !items.isEmpty else {
      return ([], [], urls)
    }
    
    var cachedItems = [T]()
    var staleItems = [T]()
    
    var entries = [Entry]()
    
    let cachedURLs = items.reduce([String]()) { acc, item in
      if let entry = item as? Entry {
        entries.append(entry)
        cachedItems.append(item)
        return acc
      }
      if !FeedCache.stale(item.ts!, ttl: ttl) {
        cachedItems.append(item)
        return acc + [item.url]
      } else {
        staleItems.append(item)
        return acc
      }
    }
    
    var cachedEntryURLs = [String]()
    for url in urls {
      let feed = entries.filter { $0.feed == url }
      guard !feed.isEmpty else {
        break
      }
      let entry = latest(feed)
      if !FeedCache.stale(entry.ts!, ttl: ttl) {
        cachedEntryURLs.append(entry.feed)
      }
    }
    
    let strings = cachedURLs + cachedEntryURLs
    let notCachedURLs = subtract(strings: strings, from: urls)
    
    if notCachedURLs.isEmpty {
      return (cachedItems, [], nil)
    } else {
      return (cachedItems, staleItems, notCachedURLs)
    }
  }

}

// MARK: - Entries

/// Comply with MangerKit API to enable using the remote service.
extension EntryLocator: MangerQuery {}

final class EntriesOperation: BrowseOperation {

  // MARK: Callbacks

  var entriesBlock: ((Error?, [Entry]) -> Void)?

  var entriesCompletionBlock: ((Error?) -> Void)?

  // MARK: State

  let locators: [EntryLocator]

  /// Creates an entries operation with the specified cache, service, dispatch
  /// queue, and entry locators.
  ///
  /// Refer to `BrowseOperation` for more information.
  ///
  /// - parameter locators: The selection of entries to fetch.
  init(cache: FeedCaching, svc: MangerService, locators: [EntryLocator]) {
    self.locators = locators
    super.init(cache: cache, svc: svc)
  }

  func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    if let cb = self.entriesCompletionBlock {
      target.async {
        cb(er)
      }
    }
    entriesBlock = nil
    entriesCompletionBlock = nil
    isFinished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameters:
  ///   - locators: The locators of entries to request.
  ///   - dispatched: Entries that have already been dispatched.
  func request(_ locators: [EntryLocator], dispatched: [Entry]) throws {
    let reload = ttl == .none

    task = try svc.entries(locators, reload: reload) { error, payload in
      self.post(name: FeedKitRemoteResponseNotification)

      guard !self.isCancelled else { return self.done() }

      guard error == nil else {
        return self.done(FeedKitError.serviceUnavailable(error: error!))
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let (errors, receivedEntries) = serialize.entries(from: payload!)
        if !errors.isEmpty {
          if #available(iOS 10.0, *) {
            os_log("invalid entries", log: log,  type: .error)
          }
        }

        let r = BrowseOperation.redirects(in: receivedEntries)
        if !r.isEmpty {
          let urls = r.reduce([String]()) { acc, entry in
            guard let url = entry.originalURL, !acc.contains(url) else {
              return acc
            }
            return acc + [url]
          }
          try self.cache.remove(urls)
        }

        try self.cache.update(entries: receivedEntries)

        guard let cb = self.entriesBlock, !receivedEntries.isEmpty else {
          return self.done()
        }

        // The cached entries, contrary to the wired entries, contain the
        // feedTitle property. Also we should not dispatch more entries than
        // those that actually have been requested. To match these requirements
        // centrally, we retrieve our, freshly updated, entries from the cache,
        // in the hopes that SQLite is fast enough.

        let (cached, missing) = try EntriesOperation.entries(
          in: self.cache, locators: self.locators, ttl: .infinity)
        
        let error: FeedKitError? = {
          guard !missing.isEmpty else {
            return nil
          }
          return FeedKitError.missingEntries(locators: locators)
        }()

        let entries = cached.filter() { entry in
          !dispatched.contains(entry)
        }
        
        self.target.async() {
          cb(error, entries)
        }
        self.done()
      } catch FeedKitError.feedNotCached(let urls) {
        if #available(iOS 10.0, *) {
          os_log("feed not cached: %{public}@", log: log,  type: .error, urls)
        }
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !isCancelled else { return done() }
    isExecuting = true
    
    do {
      let target = self.target
      let entriesBlock = self.entriesBlock

      let (cached, missing) = try EntriesOperation.entries(
        in: cache, locators: locators, ttl: ttl.seconds)

      guard !isCancelled else { return done() }

      var dispatched = [Entry]()
      
      if let cb = entriesBlock, !cached.isEmpty {
        dispatched += cached
        target.async {
          cb(nil, cached)
        }
      }

      guard !missing.isEmpty else {
        return done()
      }

      if !reachable {
        done(FeedKitError.offline)
      } else {
        try request(missing, dispatched: dispatched)
      }
    } catch let er {
      done(er)
    }
  }
}

// MARK: Accessing Cached Entries

extension EntriesOperation {
  
  /// Queries the local `cache` for entries and returns a tuple of cached 
  /// entries and unfullfilled entry `locators`, if any.
  ///
  /// - Parameters:
  ///   - cache: The cache object to retrieve entries from.
  ///   - locators: The selection of entries to fetch.
  ///   - ttl: The maximum age of entries to use.
  ///
  /// - Returns: A tuple of cached entries and URLs not satisfied by the cache.
  ///
  /// - Throws: Might throw database errors.
  static func entries(in cache: FeedCaching, locators: [EntryLocator], ttl: TimeInterval)
    throws -> ([Entry], [EntryLocator]) {
      let guids = locators.flatMap { $0.guid }
      let resolved = try cache.entries(guids) // TODO: cache.entries(with: guids)
      
      guard resolved.count < locators.count else {
        return (resolved, [])
      }
      
      let resguids = resolved.map { $0.guid }
      
      let unresolved = locators.filter {
        guard let guid = $0.guid else { return true }
        return !resguids.contains(guid)
      }
      
      // TODO: Merge locators having no guids but equal URLs
      
      let items = try cache.entries(within: unresolved) + resolved
      let unresolvedURLs = unresolved.map { $0.url }
      
      let (cached, stale, needed) =
        BrowseOperation.subtract(items: items, from: unresolvedURLs, with: ttl)
      assert(stale.isEmpty, "entries cannot be stale")
      
      let neededLocators: [EntryLocator] = locators.filter {
        let urls = needed ?? []
        if let guid = $0.guid {
          return !resguids.contains(guid) || urls.contains($0.url)
        }
        return urls.contains($0.url)
      }
      
      guard neededLocators != locators else {
        return ([], neededLocators)
      }
      
      return (cached, neededLocators)
  }
  
}

// MARK: - Feeds

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
  /// - parameter urls: The URLs of the feeds to request.
  /// - parameter stale: The stale feeds to eventually fall back on if the
  /// remote request fails.
  fileprivate func request(_ urls: [String], stale: [Feed]) throws {
    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }

    let cache = self.cache
    let feedsBlock = self.feedsBlock
    let target = self.target

    task = try svc.feeds(queries) { error, payload in
      self.post(name: FeedKitRemoteResponseNotification)

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

        let r = BrowseOperation.redirects(in: feeds)
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
    let t = BrowseOperation.subtract(items: items, from: urls, with: ttl)
    return t
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

extension FeedRepository: Browsing {

  // TODO: Add force parameter to feeds()

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
        // TODO: Pass error to entries operation
        assert(false, "unhandled error: \(er)")
      }
    }

    dep.feedsCompletionBlock = { error in
      if let er = error {
        // TODO: Pass error to entries operation
        assert(false, "unhandled error: \(er)")
      }
    }

    assert(dep.ttl == CacheTTL.forever)

    op.addDependency(dep)

    queue.addOperation(dep)
    queue.addOperation(op)

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

// MARK: - Caching

extension FeedRepository: Caching {
  public func flush() throws {
    try cache.flush()
  }
}
