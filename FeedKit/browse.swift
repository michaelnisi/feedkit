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

/// Subtract two arrays of strings. Note that the order of the resulting array
/// is undefined.
///
/// - Parameter a: An array of strings.
/// - Parameter b: The array of strings to subtract from.
/// - Returns: Strings from `a` that are not in `b`.
func subtractStrings(_ a: [String], fromStrings b:[String]) -> [String] {
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
/// - Returns: The item with the latest timestamp.
func latest<T: Cachable> (_ items: [T]) -> T {
  return items.sorted {
    return $0.ts!.compare($1.ts! as Date) == .orderedDescending
  }.first!
}

/// Find out which URLs still need to be consulted, after items have been
/// received from the cache, also respecting a maximal time cached items stay
/// valid (ttl) before they become stale.
///
/// The stale items are also returned, because they might be used to fall back
/// on, if something goes wrong further down the road.
///
/// Because **entries never become stale** this function collects and adds them 
/// to the cached items array. Other item types, like feeds, are checked for 
/// their age and put in the cached items or, respectively, the stale items 
/// array.
///
/// URLs of stale items, as well as URLs not present in the specified items 
/// array, are added to the URLs array. Finally the latest entry of each feed is 
/// checked for its age and, if stale, its feed URL is added to the URLs.
///
/// - Parameter items: An array of items from the cache.
/// - Parameter urls: The originally requested URLs.
/// - Parameter ttl: The maximal age of cached items before they become stale.
/// - Returns: A tuple of cached items, stale items, and URLs still to consult.
private func subtractItems<T: Cachable> (
  _ items: [T], fromURLs urls: [String], withTTL ttl: TimeInterval
) -> ([T], [T], [String]?) {

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
    if !stale(item.ts!, ttl: ttl) {
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
    if !stale(entry.ts!, ttl: ttl) {
      cachedEntryURLs.append(entry.feed)
    }
  }

  let notCachedURLs = subtractStrings(
    cachedURLs + cachedEntryURLs, fromStrings: urls
  )

  if notCachedURLs.isEmpty {
    return (cachedItems, [], nil)
  } else {
    return (cachedItems, staleItems, notCachedURLs)
  }
}

/// Retrieve feeds with the provided URLs from the cache and return a tuple
/// containing cached feeds, stale feeds, and URLs of feeds currently not in
/// the cache.
func feedsFromCache(
  _ cache: FeedCaching,
  withURLs urls: [String],
  ttl: TimeInterval
) throws -> ([Feed], [Feed], [String]?) {
  let items = try cache.feeds(urls)
  let t = subtractItems(items, fromURLs: urls, withTTL: ttl)
  return t
}

/// Query the cache for persisted entries to return a tuple containing cached
/// entries and URLs of stale or feeds not cached yet.
///
/// This function firstly finds all entries matching any GUIDs passed in the
/// locators. It then merges all locators without GUIDs and those not matching
/// any entry by GUID in the cache. With these, not yet satisfied, locators,
/// the cache is queried again. Both results are combined to one and subtracted,
/// segregated into cached entries, stale entries (an empty array apparently),
/// and URLs of stale or not yet cached feeds, to the resulting tuple.
///
/// - parameter cache: The cache object to retrieve entries from.
/// - parameter locators: The selection of entries to fetch.
/// - parameter ttl: The maximum age of entries to use.
///
/// - returns: A tuple of cached entries and URLs not satisfied by the cache.
///
/// - throws: Might throw database errors.
func entriesFromCache(
  _ cache: FeedCaching,
  locators: [EntryLocator],
  ttl: TimeInterval
) throws -> ([Entry], [String]?) {
  let guids = locators.reduce([String]()) { acc, loc in
    guard let guid = loc.guid else {
      return acc
    }
    return acc + [guid]
  }
  let resolved = try cache.entries(guids)
  let resguids = resolved.map { $0.guid }
  let unresolved = locators.filter {
    guard let guid = $0.guid else { return true }
    return !resguids.contains(guid)
  }

  let items = try cache.entries(unresolved) + resolved
  let urls = unresolved.map { $0.url }

  let t = subtractItems(items, fromURLs: urls, withTTL: ttl)
  let (cached, stale, needed) = t
  assert(stale.isEmpty, "entries cannot be stale")
  
  // TODO: Investigate issue with getting specific entries
  //
  // After substraction, in some cases, all entries of a feed are included, 
  // even if the user asked for a specific entry.
  
  return (cached, needed)
}

// TODO: Combine dispatch_sync and dispatch_async as in the search module

/// Although I despise inheritance, this is an abstract operation class to be
/// extended by operations used in the feed repository. It provides common
/// properties for the—currently two: feed and entries—operations of the
/// browsing API.
class BrowseOperation: SessionTaskOperation {
  
  let cache: FeedCaching
  let svc: MangerService
  let target: DispatchQueue

  /// Initialize and return a new feed repo operation.
  ///
  /// - Parameter cache: The persistent feed cache.
  /// - Parameter svc: The remote service to fetch feeds and entries.
  /// - Parameter queue: The target queue for callback blocks.
  init(
    cache: FeedCaching,
    svc: MangerService,
    target: DispatchQueue
  ) {
    self.cache = cache
    self.svc = svc
    self.target = target
  }
}

func post(_ name: String) {
  let nc = NotificationCenter.default
  nc.post(name: Notification.Name(rawValue: name), object: nil)
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
  /// - Parameter locators: The selection of entries to fetch.
  init(
    cache: FeedCaching,
    svc: MangerService,
    target: DispatchQueue,
    locators: [EntryLocator]
  ) {
    self.locators = locators
    super.init(cache: cache, svc: svc, target: target)
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
  /// - Parameter locators: The locators of entries to request.
  /// - Parameter dispatched: Entries that have already been dispatched.
  func request(_ locators: [EntryLocator], dispatched: [Entry]) throws {
    let target = self.target
    let cache = self.cache
    let entriesBlock = self.entriesBlock
    
    let c = self.cache
    let l = self.locators

    let queries: [MangerQuery] = locators.map { $0 }

    task = try svc.entries(queries) { error, payload in
      post(FeedKitRemoteResponseNotification)

      guard !self.isCancelled else { return self.done() }

      guard error == nil else {
        return self.done(FeedKitError.serviceUnavailable(error: error!))
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let (errors, receivedEntries) = entriesFromPayload(payload!)
        if !errors.isEmpty {
          NSLog("\(#function): \(errors.first) of \(errors.count) invalid entries")
        }
        try cache.updateEntries(receivedEntries) // empty ones too
        
        guard let cb = entriesBlock else {
          return self.done()
        }
        guard !receivedEntries.isEmpty else {
          return self.done()
        }
        
        // The cached entries, contrary to the wired entries, contain the
        // feedTitle property. Also we should not dispatch more entries than
        // those that actually have been requested. To match these requirements 
        // centrally, we retrieve our, freshly updated, entries from the cache, 
        // in the hopes that SQLite is fast enough.
        
        let (cached, urls) = try entriesFromCache(c, locators: l, ttl: FOREVER)
        assert(urls == nil, "TODO: Handle URLs")
        
        let entries = cached.filter() { entry in
          !dispatched.contains(entry)
        }
        
        target.async() {
          cb(nil, entries)
        }
        self.done()
      } catch FeedKitError.feedNotCached {
        
        // TODO: Investigate fatal error
        //
        // Failing to load the queue, I ran into this.
        
        fatalError("feedkit: cannot update entries of uncached feeds")
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
      
      // TODO: Return unresolved locators instead of URLs
      //
      // I guess, the reason why these are URLs, not locators, is that
      // subtractItems was intitially built for feeds, not for entries.

      let (cached, urls) = try entriesFromCache(cache, locators: locators, ttl: ttl.seconds)

      // Returning URLs requires us to perform an extra work reducing URLs
      // back to the initial locators. A first step to improve this might be to 
      // move the reduce into entriesFromCache and actually return locators, 
      // which would fix the API, and give a us space to remove this step later
      // requiring only internals changes.
      
      let unresolved = urls?.reduce([EntryLocator]()) { acc, url in
        for locator in locators {
          if locator.url == url {
            return acc + [locator]
          }
        }
        return acc
      }

      guard !isCancelled else { return done() }

      var dispatched = [Entry]()
      if let cb = entriesBlock {
        if !cached.isEmpty {
          dispatched += cached
          target.async {
            cb(nil, cached)
          }
        }
      }

      guard unresolved != nil else {
        return done()
      }

      assert(!unresolved!.isEmpty, "unresolved locators cannot be empty")

      if !reachable {
        done(FeedKitError.offline)
      } else {
        try request(unresolved!, dispatched: dispatched)
      }
    } catch let er {
      done(er)
    }
  }
}

// MARK: - Feeds

final class FeedsOperation: BrowseOperation {

  // MARK: Callbacks

  var feedsBlock: ((Error?, [Feed]) -> Void)?

  var feedsCompletionBlock: ((Error?) -> Void)?

  // MARK: State

  let urls: [String]

  /// Returns an intialized `FeedsOperation` object.
  ///
  /// Look at `BrowseOperation` for more.
  ///
  /// - Parameter urls: The feed URLs to retrieve.
  init(
    cache: FeedCaching,
    svc: MangerService,
    target: DispatchQueue,
    urls: [String]
  ) {
    self.urls = urls
    super.init(cache: cache, svc: svc, target: target)
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
  /// - Parameter urls: The URLs of the feeds to request.
  /// - Parameter stale: The stale feeds to eventually fall back on if the
  /// remote request fails.
  fileprivate func request(_ urls: [String], stale: [Feed]) throws {
    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }

    let cache = self.cache
    let feedsBlock = self.feedsBlock
    let target = self.target

    task = try svc.feeds(queries) { error, payload in
      post(FeedKitRemoteResponseNotification)

      guard !self.isCancelled else { return self.done() }
      guard error == nil else {
        defer {
          let er = FeedKitError.serviceUnavailable(error: error!)
          self.done(er)
        }
        guard !stale.isEmpty else { return }

        guard let cb = feedsBlock else { return }
        return target.async() {
          cb(nil, stale)
        }
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let (errors, feeds) = feedsFromPayload(payload!)
        assert(errors.isEmpty, "unhandled errors: \(errors)")
        try cache.updateFeeds(feeds)
        guard let cb = feedsBlock else { return self.done() }
        guard !feeds.isEmpty else { return self.done() }
        target.async() {
          cb(nil, feeds)
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
      let cache = self.cache
      let feedsBlock = self.feedsBlock
      let t = try feedsFromCache(cache, withURLs: urls, ttl: ttl.seconds)
      let (cached, stale, urlsToRequest) = t

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

/// The `FeedRepository` provides feeds and entries.
public final class FeedRepository: RemoteRepository, Browsing {
  let cache: FeedCaching
  let svc: MangerService

  /// Initialize and return a new feed repository.
  ///
  /// - Parameter cache: The feed cache to use.
  /// - Parameter svc: The remote service.
  /// - Parameter queue: The queue to execute this repository's operations.
  /// - Parameter probe: A reachability probe.
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
  
  // TODO: Add force parameter

  /// Use this method to get feeds for the specified `urls`. The `feedsBlock`
  /// callback block might get called multiple times. The second callback block
  /// `feedsCompletionBlock` is called at the end, but before the standard
  /// `completionBlock`.
  ///
  /// - parameter urls: An array of feed URLs.
  /// - parameter feedsBlock: Applied zero, one, or two times with the requested
  /// feeds. The error defined in this callback is not being used at the moment.
  /// - parameter feedsCompletionBlock: Applied when no more `feedBlock` is to
  /// be expected.
  ///
  /// - returns: The executing operation.
  public func feeds(
    _ urls: [String],
    feedsBlock: @escaping (Error?, [Feed]) -> Void,
    feedsCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    let target = DispatchQueue.main

    let op = FeedsOperation(
      cache: cache,
      svc: svc,
      target: target,
      urls: urls
    )
    
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    op.reachable = reachable()
    op.ttl = timeToLive()

    queue.addOperation(op)

    return op
  }
  
  /// Get entries for the given locators aggregating local and remote data.
  ///
  /// Locators provide a feed URL, a moment in the past, and an optional guid.
  /// This way you can limit the requested entries to specific time ranges,
  /// skipping entries you already have.
  ///
  /// The GUID is used to get specific entries already in the cache. If there is
  /// no entry with this GUID in the cache, feed URL and interval are used to
  /// request the entry from the remote service. It cannot be guaranteed to be
  /// successful, because the remote feed might have removed the requested entry
  /// in the meantime.
  ///
  /// This method uses a local cache and a remote service to fulfill the request.
  /// If the remote service is unavavailable it tries to fall back on the cache
  /// and might end up skipping requested entries. This is made transparent by
  /// an error passed to the entries completion block.
  ///
  /// - parameter locators: The locators for the entries to request.
  /// - parameter force: Force remote request ignoring the cache. As this
  /// produces load on the server, it is limited to once per hour per feed. If 
  /// you pass multiple locators, the force parameter is ignored.
  /// - parameter entriesBlock: Applied zero, one, or two times passing fetched
  /// and/or cached entries. The error is currently not in use.
  /// - parameter entriesCompletionBlock: The completion block is applied when
  /// all entries have been dispatched.
  ///
  /// - returns: The executing operation.
  public func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    let target = DispatchQueue.main
    
    let op = EntriesOperation(
      cache: cache,
      svc: svc,
      target: target,
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
    op.ttl = ttl
    op.reachable = r
    
    // We have to get the according feeds before we can request their entries,
    // because we cannot update entries of uncached feeds. Providing a place to 
    // composite operations, like this, is an advantage of interposing
    // repositories.

    let urls = locators.map { $0.url }

    let dep = FeedsOperation(
      cache: cache,
      svc: svc,
      target: target,
      urls: urls
    )
    
    dep.ttl = CacheTTL.forever
    dep.reachable = r
    
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
