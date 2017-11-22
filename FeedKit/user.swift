//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import AVFoundation
import Foundation
import Skull
import os.log

fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

/// Confines `Queue` state dependency.
fileprivate protocol EntryQueueHost {
  var queue: Queue<Entry> { get set }
}

/// The `UserLibrary` manages the user‘s data, for example, feed subscriptions
/// and queue.
public final class UserLibrary: EntryQueueHost {
  fileprivate let cache: UserCaching
  fileprivate let browser: Browsing
  fileprivate let operationQueue: OperationQueue
  
  /// Creates a fresh EntryQueue object.
  ///
  /// - Parameters:
  ///   - cache: The cache to store user data locallly.
  ///   - browser: The browser to access feeds and entries.
  ///   - queue: A serial operation queue to execute operations in order.
  public init(cache: UserCaching, browser: Browsing, queue: OperationQueue) {
    self.cache = cache
    self.browser = browser
    self.operationQueue = queue
    
    synchronize()
  }
  
  /// The actual queue data structure. Starting off with an empty queue.
  fileprivate var queue = Queue<Entry>()
  
  /// The current subscribed URLs—to some extend.
  fileprivate var subscriptions = Set<FeedURL>()
}

// MARK: - Subscribing

private final class FetchFeedsOperation: FeedKitOperation {
  
  let browser: Browsing
  let cache: SubscriptionCaching
  
  init(browser: Browsing, cache: SubscriptionCaching) {
    self.browser = browser
    self.cache = cache
  }
  
  var feedsBlock: (([Feed], Error?) -> Void)?
  var feedsCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the feeds.
  weak fileprivate var op: Operation?
  
  private func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    if let cb = feedsCompletionBlock {
      DispatchQueue.global().async {
        cb(er)
      }
    }
    
    feedsBlock = nil
    feedsCompletionBlock = nil
    
    isFinished = true
    op?.cancel()
    op = nil
  }
  
  private func fetchFeeds(of subscriptions: [Subscription]) {
    guard !isCancelled, !subscriptions.isEmpty else {
      return done()
    }
    
    let urls = subscriptions.map { $0.url }
    
    var acc = [Feed]()

    op = browser.feeds(urls, feedsBlock: { error, feeds in
      guard !self.isCancelled else {
        return
      }
      
      acc = acc + feeds

      DispatchQueue.global().async {
        self.feedsBlock?(feeds, error)
      }
    }) { error in
      guard !self.isCancelled, error == nil else {
        return self.done(error)
      }
      
      let urls = acc.flatMap { $0.iTunes == nil ? $0.url : nil }
      let missing = subscriptions.filter { urls.contains($0.url) }

      self.browser.integrateMetadata(from: missing) { error in
        self.done(error)
      }
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    do {
      let subscriptions = try cache.subscribed()
      fetchFeeds(of: subscriptions)
    } catch {
      done(error)
    }
  }
  
}

extension UserLibrary: Subscribing {
  
  public func add(
    subscriptions: [Subscription],
    addComplete: ((_ error: Error?) -> Void)? = nil) throws {
    guard !subscriptions.isEmpty else {
      DispatchQueue.global().async {
        addComplete?(nil)
      }
      return
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      do {
        try cache.add(subscriptions: subscriptions)
        self.subscriptions.formUnion(subscriptions.map { $0.url })
      } catch {
        DispatchQueue.global().async {
          addComplete?(error)
        }
        return
      }

      DispatchQueue.global().async {
        addComplete?(nil)
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: self)
      }
    }

  }
  
  public func unsubscribe(
    from urls: [FeedURL],
    unsubscribeComplete: ((_ error: Error?) -> Void)? = nil) throws {
    func done(_ error: Error? = nil) -> Void {
      DispatchQueue.global().async {
        unsubscribeComplete?(error)
      }
    }
    
    guard !urls.isEmpty else {
      return done()
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      do {
        try cache.remove(urls: urls)
        self.subscriptions.subtract(urls)
      } catch {
        return done(error)
      }
      
      done()
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: self)
      }
    }
  }
  
  @discardableResult
  public func fetchFeeds(
    feedsBlock: @escaping (_ feeds: [Feed], _ feedsError: Error?) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FetchFeedsOperation(browser: browser, cache: cache)
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  public func has(subscription url: FeedURL) -> Bool {
    return subscriptions.contains(url)
  }
  
  public func synchronize() {
    DispatchQueue.global(qos: .background).async {
      do {
        let subscribed = try self.cache.subscribed()
        
        let urls = Set(subscribed.map { $0.url })
        let unsubscribed = self.subscriptions.subtracting(urls)
        self.subscriptions.subtract(unsubscribed)
        self.subscriptions.formUnion(urls)
      } catch {
        os_log("failed to reload subscriptions", log: log, type: .error,
               error as CVarArg)
      }
    }
  }

}

// MARK: - Updating

extension UserLibrary: Updating {
  
  private static func guidsToIgnore(cache: QueueCaching) throws -> [String] {
    let previous = try cache.previous()
    return previous.flatMap {
      switch $0 {
      case .entry(let loc, _):
        return loc.guid
      }
    }
  }
  
  /// Returns the locators to update from `queued` items, while subscribed to
  /// to `subscriptions`.
  static func locatorsToUpdate(
    from queued: [Queued],
    with subscriptions: [FeedURL]) -> [EntryLocator] {
    var latestByURL = [FeedURL: EntryLocator]()
    
    for q in queued {
      switch q {
      case .entry(let loc, _):
        guard subscriptions.contains(loc.url) else {
          continue
        }
        
        if let latest = latestByURL[loc.url] {
          if latest.since > loc.since { // newer wins
            continue
          }
        }
        
        latestByURL[loc.url] = EntryLocator(url: loc.url, since: loc.since)
      }
    }
    
    return latestByURL.flatMap { $0.value }
  }
  
  private static func queuedLocators(
    from cache: QueueCaching,
    with subscriptions: [Subscription]) throws -> [EntryLocator] {
    let queued = try cache.queued()
    let urls = subscriptions.map { $0.url }
    return locatorsToUpdate(from: queued, with: urls)
  }
  
  static func latest(
    from entries: [Entry],
    using subscriptions: [Subscription]) -> [Entry] {
    // TODO: Keep newer than subscription
    return entries
  }
  
  public func update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    os_log("updating", log: log,  type: .info)
    
    let cache = self.cache
    let forcing = true
    
    var locatingError: Error?
    
    // Locating results: subscriptions, locators, and ignored GUIDs; where the
    // subscriptions are used for the request and to filter the fetched entries
    // before enqueuing them in the completion block below.
    
    var subscriptions: [Subscription]!
    var locators: [EntryLocator]!
    var ignored: [String]!
    
    let locating = BlockOperation {
      do {
        subscriptions = try cache.subscribed()
        locators = try UserLibrary.queuedLocators(from: cache, with: subscriptions)
        ignored = try UserLibrary.guidsToIgnore(cache: cache)
        
        // TODO: Remove this uniqueness check
        let urls = locators.map { $0.url }
        assert(urls.count == Set(urls).count)
      } catch {
        locatingError = error
      }
    }
    
    func fetchEntries() {
      guard locatingError == nil, !locators.isEmpty else {
        return DispatchQueue.global().async {
          updateComplete(false, locatingError)
        }
      }
      
      var acc = [Entry]()
      browser.entries(locators, force: forcing, entriesBlock: { error, entries in
        guard error == nil else {
          os_log("faulty entries: %{public}@", log: log, type: .error,
                 error! as CVarArg)
          return
        }
        
        guard !ignored.isEmpty else {
          return acc.append(contentsOf: entries)
        }
        
        acc = acc + entries.filter { !ignored.contains($0.guid) }
      }) { error in
        guard error == nil else {
          return DispatchQueue.global().async {
            updateComplete(false, error)
          }
        }
        
        let latest = UserLibrary.latest(from: acc, using: subscriptions)
        
        do {
          try self.enqueue(entries: latest) { error in
            DispatchQueue.global().async {
              updateComplete(true, error)
            }
          }
        } catch {
          DispatchQueue.global().async {
            updateComplete(false, error)
          }
        }
      }
    }
    
    // Assuming our custom serial queue: 'ink.codes.feekit.user'.
    let q = operationQueue.underlyingQueue!
    
    locating.completionBlock = {
      q.async {
        fetchEntries()
      }
    }
    
    operationQueue.addOperation(locating)
  }
  
}

// MARK: - Queueing

private final class FKFetchQueueOperation: FeedKitOperation {
  let browser: Browsing
  let cache: QueueCaching
  var user: EntryQueueHost

  init(browser: Browsing, cache: QueueCaching, user: EntryQueueHost) {
    self.browser = browser
    self.cache = cache
    self.user = user
  }
  
  var entriesBlock: (([Entry], Error?) -> Void)?
  var fetchQueueCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the entries.
  weak var op: Operation?
  
  private func done(but error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    os_log("done: %{public}@", log: log, type: .debug,
           er != nil ? String(reflecting: er) : "OK")
    
//    if let cb = fetchQueueCompletionBlock {
//      DispatchQueue.global().async {
//        cb(er)
//      }
//    }
    

    fetchQueueCompletionBlock?(er)
    
    entriesBlock = nil
    fetchQueueCompletionBlock = nil
    
    isFinished = true
    
    op?.cancel()
    op = nil
  }
  
  /// Collects a unique list of missing GUIDs.
  private static func missingGuids(
    with entries: [Entry], for guids: [String], respecting error: Error?
  ) -> [String] {
    let found = entries.map { $0.guid }
    let a = Array(Set(guids).subtracting(found))
    
    guard let er = error else {
      return Array(Set(a))
    }
    
    switch er {
    case FeedKitError.missingEntries(let locators):
      return Array(Set(a + locators.flatMap { $0.guid }))
    default:
      return Array(Set(a))
    }
  }
  
  /// Cleans up, if we aren‘t offline and the remote service is OK—make sure
  /// to check this—we can go ahead and remove missing entries. Although, a
  /// specific feed‘s server might have been offline for a minute, while the
  /// remote cache is cold, but well, tough luck.
  ///
  /// - Parameters:
  ///   - entries: The entries we have successfully received.
  ///   - guids: GUIDs of the entries we had requested.
  ///   - error: An optional `FeedKitError.missingEntries` error.
  private func queuedEntries(
    with entries: [Entry], for guids: [String], respecting error: Error?
  ) -> [Entry] {
    let missing = FKFetchQueueOperation.missingGuids(
      with: entries, for: guids, respecting: error)
    
    guard !missing.isEmpty else {
      os_log("queue complete", log: log, type: .debug)
      return user.queue.items
    }
    
    do {
      os_log("remove missing entries: %{public}@", log: log, type: .debug,
             String(reflecting: missing))
      
      for guid in missing {
        try user.queue.removeItem(with: guid.hashValue)
      }
      
      try cache.remove(guids: missing)
    } catch {
      os_log("could not remove missing: %{public}@", log: log, type: .error,
             error as CVarArg)
    }
      
    return user.queue.items
  }
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty,
      let guids = self.sortedIds else {
        return done()
    }
    
    var acc = [Entry]()
    var accError: Error?
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      assert(!Thread.isMainThread)
      guard error == nil else {
        accError = error
        return
      }
      
      guard !entries.isEmpty else {
        os_log("no entries", log: log)
        return
      }
      
      acc = acc + entries
    }) { error in
      defer {
        DispatchQueue.global().async { [weak self] in
          self?.done(but: error)
        }
      }
      
      guard error == nil else {
        return
      }
      
      let sorted: [Entry] = {
        var entriesByGuids = [String : Entry]()
        acc.forEach { entriesByGuids[$0.guid] = $0 }
        return guids.flatMap { entriesByGuids[$0] }
      }()
      
      do {
        os_log("appending: %{public}@", log: log, type: .debug,
               String(reflecting: sorted))
        
        try self.user.queue.append(items: sorted)
      } catch {
        switch error {
        case QueueError.alreadyInQueue:
          os_log("already in queue", log: log)
        default:
          fatalError("unhandled error: \(error)")
        }
      }
      
      let entries = self.queuedEntries(
        with: sorted, for: guids, respecting: accError)
      
      os_log("entries in queue: %{public}@", log: log, type: .debug,
             String(reflecting: entries))
      
      DispatchQueue.global().async { [weak self] in
        guard let cb = self?.entriesBlock else {
          return
        }
        cb(entries, accError)
      }
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  /// The sorted guids of the items in the queue.
  private var sortedIds: [String]? {
    didSet {
      guard let guids = sortedIds else {
        user.queue.removeAll()
        try! cache.removeAll() // redundant
        return
      }
      let queuedGuids = user.queue.map { $0.guid }
      let guidsToRemove = Array(Set(queuedGuids).subtracting(guids))
      
      var queuedEntriesByGuids = [String : Entry]()
      user.queue.forEach { queuedEntriesByGuids[$0.guid] = $0 }
      
      for guid in guidsToRemove {
        if let entry = queuedEntriesByGuids[guid] {
          try! user.queue.remove(entry)
        }
      }
    }
  }
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    var queued: [Queued]!
    do {
      queued = try cache.queued()
    } catch {
      done(but: error)
    }
    
    guard !isCancelled, !queued.isEmpty else {
      return done()
    }
    
    var guids = [String]()
    
    let locators: [EntryLocator] = queued.flatMap {
      switch $0 {
      case .entry(let locator, _):
        guard let guid = locator.guid else {
          fatalError("missing guid")
        }
        guids.append(guid)
        return locator.including
      }
    }
    
    sortedIds = guids
    
    guard !isCancelled, !locators.isEmpty else {
      return done()
    }
    
    fetchEntries(for: locators)
  }
  
}

extension UserLibrary: Queueing {
  
  @discardableResult
  public func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    os_log("fetching", log: log, type: .debug)
    
    let op = FKFetchQueueOperation(browser: browser, cache: cache, user: self)
    op.entriesBlock = entriesBlock
    op.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    
    // Synced data from iCloud might contain additional information, we don’t
    // have yet, and cannot aquire otherwise, like iTunes GUIDs and URLs of
    // pre-scaled images. Especially those smaller images are of interest to us,
    // because they make a palpable difference for the user. With this operation
    // dependency, we are integrating this data into our feed repo.
    
    let dep = FetchFeedsOperation(browser: browser, cache: cache)
    dep.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: log, type: .error, String(describing: er))
      }
    }
    dep.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: log, type: .error, String(describing: er))
      }
    }
    
    op.addDependency(dep)
    
    operationQueue.addOperation(op)
    operationQueue.addOperation(dep)
    
    return op
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil) throws {
    guard !entries.isEmpty else {
      DispatchQueue.global().async {
        enqueueCompletionBlock?(nil)
      }
      return
    }
    
    os_log("enqueueing", log: log, type: .debug)
    
    operationQueue.addOperation {
      do {
        try self.queue.prepend(items: entries)
        let locators = entries.map { EntryLocator(entry: $0) }
        try self.cache.add(entries: locators)
      } catch {
        DispatchQueue.global().async {
          enqueueCompletionBlock?(error)
        }
        return
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: self)
      }
      
      DispatchQueue.global().async {
        enqueueCompletionBlock?(nil)
      }
    }
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    os_log("dequeueing", log: log, type: .debug)
    
    operationQueue.addOperation {
      do {
        try self.queue.remove(entry)
        let guid = entry.guid
        try self.cache.remove(guids: [guid])
      } catch {
        DispatchQueue.global().async {
          dequeueCompletionBlock?(error)
        }
        return
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: self)
      }
      
      DispatchQueue.global().async {
        dequeueCompletionBlock?(nil)
      }
    }
  }
  
  // MARK: Synchronous queue methods

  public func contains(entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
  public var isEmpty: Bool {
    return queue.isEmpty
  }
  
}

