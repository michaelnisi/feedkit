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
func subtractStrings(a: [String], fromStrings b:[String]) -> [String] {
  let setA = Set(a)
  let setB = Set(b)
  let diff = setB.subtract(setA)
  return Array(diff)
}

/// Find and return the newest item in the specified array of cachable items.
/// Attention: this intentionally crashes if you pass an empty items array or
/// if one of the items doesn't bear a timestamp.
///
/// - Parameter items: The cachable items to iterate and compare.
/// - Returns: The item with the latest timestamp.
func latest<T: Cachable> (items: [T]) -> T {
  return items.sort {
    return $0.ts!.compare($1.ts!) == .OrderedDescending
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
  items: [T], fromURLs urls: [String], withTTL ttl: NSTimeInterval
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
  cache: FeedCaching,
  withURLs urls: [String],
  ttl: NSTimeInterval
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
/// - Parameter cache: The cache object to retrieve entries from.
/// - Parameter locators: The selection of entries to fetch.
/// - Parameter ttl: The maximum age of entries to use.
/// - Returns: A tuple of cached entries and URLs not satisfied by the cache.
/// - Throws: Might throw database errors.
func entriesFromCache(
  cache: FeedCaching,
  locators: [EntryLocator],
  ttl: NSTimeInterval
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
  
  return (cached, needed)
}

/// Although I despise inheritance, this is an abstract operation class to be
/// extended by operations used in the feed repository. It provides common
/// properties for the—currently two: feed and entries—operations of the
/// browsing API.
class BrowseOperation: SessionTaskOperation {
  let cache: FeedCaching
  let svc: MangerService
  let target: dispatch_queue_t
  let reachable: Bool
  let ttl: CacheTTL

  /// Initialize and return a new feed repo operation.
  ///
  /// - Parameter cache: The persistent feed cache.
  /// - Parameter svc: The remote service to fetch feeds and entries.
  /// - Parameter queue: The target queue for callback blocks.
  /// - Parameter reachable: Flag expected reachability of remote service.
  /// - Parameter ttl: Maximum age of cached items.
  init(
    cache: FeedCaching,
    svc: MangerService,
    target: dispatch_queue_t,
    reachable: Bool = true,
    ttl: CacheTTL
  ) {
    self.cache = cache
    self.svc = svc
    self.target = target
    self.reachable = reachable
    self.ttl = ttl
  }
}

private func post(name: String) {
  let nc = NSNotificationCenter.defaultCenter()
  nc.postNotificationName(name, object: nil)
}

// MARK: - Entries

/// Comply with MangerKit API to use remote service.
extension EntryLocator: MangerQuery {}

final class EntriesOperation: BrowseOperation {

  // MARK: Callbacks

  var entriesBlock: ((ErrorType?, [Entry]) -> Void)?

  var entriesCompletionBlock: ((ErrorType?) -> Void)?

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
    target: dispatch_queue_t,
    locators: [EntryLocator],
    reachable r: Bool = true,
    ttl: CacheTTL
  ) {
    self.locators = locators
    super.init(cache: cache, svc: svc, target: target, reachable: r, ttl: ttl)
  }

  func done(error: ErrorType? = nil) {
    let er = cancelled ? FeedKitError.CancelledByUser : error
    if let cb = self.entriesCompletionBlock {
      dispatch_async(target) {
        cb(er)
      }
    }
    entriesBlock = nil
    entriesCompletionBlock = nil
    finished = true
  }

  /// Request all entries of listed feed URLs remotely.
  ///
  /// - Parameter locators: The locators of entries to request.
  /// - Parameter dispatched: Entries that have already been dispatched.
  func request(locators: [EntryLocator], dispatched: [Entry]) throws {
    let target = self.target
    let cache = self.cache
    let entriesBlock = self.entriesBlock
    
    let c = self.cache
    let l = self.locators

    post("request")

    let queries: [MangerQuery] = locators.map { $0 }

    task = try svc.entries(queries) { error, payload in
      post("response")

      guard !self.cancelled else { return self.done() }

      guard error == nil else {
        return self.done(FeedKitError.ServiceUnavailable(error: error!))
      }
      guard payload != nil else {
        return self.done()
      }
      do {
        let (errors, receivedEntries) = entriesFromPayload(payload!)
        if !errors.isEmpty {
          NSLog("\(#function): \(errors.count) invalid entries")
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
        assert(urls == nil)
        
        let entries = cached.filter() { entry in
          !dispatched.contains(entry)
        }
        
        dispatch_async(target) {
          cb(nil, entries)
        }
        self.done()
      } catch FeedKitError.FeedNotCached {
        fatalError("feedkit: cannot update entries of uncached feeds")
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !cancelled else { return done() }
    executing = true

    do {
      let target = self.target
      let entriesBlock = self.entriesBlock

      let c = self.cache
      let l = self.locators
      
      // TODO: Return unresolved locators instead of URLs
      //
      // I guess, the reason why these are URLs but not locators is that
      // subtractItems was intitially designed for feeds--not for entries.

      let (cached, urls) = try entriesFromCache(c, locators: l, ttl: ttl.seconds)

      // Returning URLs demands from us to perform an extra step reducing URLs
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

      guard !cancelled else { return done() }

      var dispatched = [Entry]()
      if let cb = entriesBlock {
        if !cached.isEmpty {
          dispatched += cached
          dispatch_async(target) {
            cb(nil, cached)
          }
        }
      }

      guard unresolved != nil else {
        return done()
      }

      assert(!unresolved!.isEmpty, "unresolved locators cannot be empty")

      if !reachable {
        done(FeedKitError.Offline)
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

  var feedsBlock: ((ErrorType?, [Feed]) -> Void)?

  var feedsCompletionBlock: ((ErrorType?) -> Void)?

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
    target: dispatch_queue_t,
    urls: [String],
    reachable r: Bool = true,
    ttl: CacheTTL
  ) {
    self.urls = urls
    super.init(cache: cache, svc: svc, target: target, reachable: r, ttl: ttl)
  }

  private func done(error: ErrorType? = nil) {
    let er = cancelled ? FeedKitError.CancelledByUser : error
    if let cb = feedsCompletionBlock {
      dispatch_async(target) {
        cb(er)
      }
    }
    feedsBlock = nil
    feedsCompletionBlock = nil
    finished = true
  }

  /// Request feeds and update the cache.
  ///
  /// - Parameter urls: The URLs of the feeds to request.
  /// - Parameter stale: The stale feeds to eventually fall back on if the
  /// remote request fails.
  private func request(urls: [String], stale: [Feed]) throws {
    post("request")

    let queries: [MangerQuery] = urls.map { EntryLocator(url: $0) }

    let cache = self.cache
    let feedsBlock = self.feedsBlock
    let target = self.target

    task = try svc.feeds(queries) { error, payload in
      post("response")

      guard !self.cancelled else { return self.done() }
      guard error == nil else {
        defer {
          let er = FeedKitError.ServiceUnavailable(error: error!)
          self.done(er)
        }
        guard !stale.isEmpty else { return }

        guard let cb = feedsBlock else { return }
        return dispatch_async(target) {
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
        dispatch_async(target) {
          cb(nil, feeds)
        }
        self.done()
      } catch let er {
        self.done(er)
      }
    }
  }

  override func start() {
    guard !cancelled else { return done() }
    executing = true

    do {
      let target = self.target
      let cache = self.cache
      let feedsBlock = self.feedsBlock
      let t = try feedsFromCache(cache, withURLs: urls, ttl: ttl.seconds)
      let (cached, stale, urlsToRequest) = t

      guard !cancelled else { return done() }

      if urlsToRequest == nil {
        guard !cached.isEmpty else { return done() }
        guard let cb = feedsBlock else { return done() }
        dispatch_async(target) {
          cb(nil, cached)
        }
        return done()
      }
      if !cached.isEmpty {
        if let cb = feedsBlock {
          dispatch_async(target) {
            cb(nil, cached)
          }
        }
      }
      assert(!urlsToRequest!.isEmpty, "URLs to request must not be empty")

      if !reachable {
        if !stale.isEmpty {
          if let cb = feedsBlock {
            dispatch_async(target) {
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
public final class FeedRepository: Browsing {
  let cache: FeedCaching
  let svc: MangerService
  let queue: NSOperationQueue
  let ola: Ola

  // MARK: Pull To Refresh

  var tsByURLs = [String:NSDate]()

  /// Return a time to live interval for forced updates with limited frequency, 
  /// once per `CacheTTL.Short` interval, to prevent swamping the server. These
  /// forced updates are only allowed for single locators: if you pass more than 
  /// one locator, your intend to force gets ignored. If the forced request is
  /// not accepted, the specified ttl or `CacheTTL.medium` is returned.
  ///
  /// - Parameter locators: The locators of the requested entries.
  /// - Parameter force: If you pass `true` and the last forced refresh was
  /// - Parameter ttl: The time-to-live to default to if force is unavailable.
  private func timeToLive(
    locators: [EntryLocator],
    force: Bool,
    ttl: CacheTTL = CacheTTL.Medium
  ) -> CacheTTL {
    if locators.count == 1 && force {
      let locator = locators.first
      let url = locator!.url
      let prev = tsByURLs[url]
      if prev == nil || prev!.timeIntervalSinceNow > CacheTTL.Short.seconds {
        let ts = NSDate()
        tsByURLs[url] = ts
        return CacheTTL.None
      }
    }
    return ttl
  }
  

  /// Initialize and return a new feed repository.
  ///
  /// - Parameter cache: The feed cache to use.
  /// - Parameter svc: The remote service.
  /// - Parameter queue: The queue to execute this repository's operations.
  /// - Parameter ola: The ola object to probe reachability.
  public init(
    cache: FeedCaching,
    svc: MangerService,
    queue: NSOperationQueue,
    ola: Ola
  ) {
    self.cache = cache
    self.svc = svc
    self.queue = queue
    self.ola = ola
  }

  deinit {
    queue.cancelAllOperations()
  }

  func reachable() -> Bool {
    return ola.reach() == .Reachable // harshly oversimplified
  }

  /// Use this method to get feeds for an array of URLs. The `feedsBlock`
  /// callback block might get called multiple times. The second callback block
  /// `feedsCompletionBlock` is called at the end, but before the standard
  /// `completionBlock`.
  ///
  /// - Parameter urls: An array of feed URLs.
  /// - Parameter feedsBlock: Applied zero, one, or two times with the requested
  /// feeds. The error defined in this callback is not being used at the moment.
  /// - Parameter feedsCompletionBlock: Applied when no more `feedBlock` is to
  /// be expected.
  /// - Returns: The executing operation.
  public func feeds(
    urls: [String],
    feedsBlock: (ErrorType?, [Feed]) -> Void,
    feedsCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    let target = dispatch_get_main_queue()

    let op = FeedsOperation(
      cache: cache,
      svc: svc,
      target: target,
      urls: urls,
      reachable: reachable(),
      ttl: CacheTTL.Long
    )
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock

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
  /// - Parameter locators: The locators for the entries to request.
  /// - Parameter force: Force remote request ignoring the cache. As this
  /// produces load on the server, it's limited to once per hour.
  /// - Parameter entriesBlock: Applied zero, one, or two times passing fetched
  /// and/or cached entries. The error is currently not in use.
  /// - Parameter entriesCompletionBlock: The completion block is applied when
  /// all entries have been dispatched.
  /// - Returns: The executing operation.
  public func entries(
    locators: [EntryLocator],
    force: Bool,
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    let target = dispatch_get_main_queue()
    let r = reachable()
    let ttl = timeToLive(locators, force: force, ttl: CacheTTL.Long)

    let op = EntriesOperation(
      cache: cache,
      svc: svc,
      target: target,
      locators: locators,
      reachable: r,
      ttl: ttl
    )
    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    
    // We have to get the according feeds before we can request their entries,
    // because we cannot update entries of uncached feeds. Providing a place to 
    // composite operations, like this, is an advantage of interposing
    // repositories.

    let urls = locators.map { $0.url }

    let dep = FeedsOperation(
      cache: cache,
      svc: svc,
      target: target,
      urls: urls,
      reachable: r,
      ttl: CacheTTL.Forever
    )
    op.addDependency(dep)

    queue.addOperation(dep)
    queue.addOperation(op)

    return op
  }
  
  public func entries(
    locators: [EntryLocator],
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation {
    return self.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }
}
