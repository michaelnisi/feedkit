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
  ///   - queue: A serial operation queue to execute operations on.
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
  let target: DispatchQueue
  
  init(browser: Browsing, cache: SubscriptionCaching) {
    self.browser = browser
    self.cache = cache
    
    self.target = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
  }
  
  var feedsBlock: (([Feed], Error?) -> Void)?
  var feedsCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the feeds.
  weak fileprivate var op: Operation?
  
  private func done(_ error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    if let cb = feedsCompletionBlock {
      target.async {
        cb(er)
      }
    }
    
    feedsBlock = nil
    feedsCompletionBlock = nil
    
    isFinished = true
    op?.cancel()
    op = nil
  }
  
  private func fetchFeeds(at urls: [String]) {
    guard !isCancelled, !urls.isEmpty else {
      return done()
    }
    
    op = browser.feeds(urls, feedsBlock: { error, feeds in
      if !self.isCancelled, let cb = self.feedsBlock {
        self.target.async {
          cb(feeds, error)
        }
      }
    }) { error in
      self.done(error)
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
      let urls = subscriptions.map { $0.url }
      fetchFeeds(at: urls)
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
      throw FeedKitError.emptyCollection
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      let target = OperationQueue.current!.underlyingQueue!
      
      do {
        try cache.add(subscriptions: subscriptions)
        self.subscriptions.formUnion(subscriptions.map { $0.url })
      } catch {
        target.async {
          addComplete?(error)
        }
        return
      }

      target.async {
        addComplete?(nil)
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: nil)
      }
    }

  }
  
  public func unsubscribe(
    from urls: [FeedURL],
    unsubscribeComplete: ((_ error: Error?) -> Void)? = nil) throws {
    guard !urls.isEmpty else {
      throw FeedKitError.emptyCollection
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      let target = OperationQueue.current!.underlyingQueue!
      
      do {
        try cache.remove(urls: urls)
        self.subscriptions.subtract(urls)
      } catch {
        target.async {
          unsubscribeComplete?(error)
        }
        return
      }
      
      target.async {
        unsubscribeComplete?(nil)
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: nil)
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
        let s = try self.cache.subscribed()
        let subscribed = Set(s.map { $0.url })
      
        let unsubscribed = self.subscriptions.subtracting(subscribed)
        self.subscriptions.subtract(unsubscribed)
        self.subscriptions.formUnion(subscribed)
      } catch {
        os_log("failed to reload subscriptions", log: log, type: .error,
               error as CVarArg)
      }
    }
  }

}

// MARK: - Updating

extension UserLibrary: Updating {

  public func update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    os_log("updating", log: log,  type: .info)
    // TODO: Implement updating of subscribed feeds
    updateComplete(true, nil)
  }
  
}

// MARK: - Queueing

private final class FKFetchQueueOperation: FeedKitOperation {
  let browser: Browsing
  let cache: QueueCaching
  var user: EntryQueueHost
  
  let target: DispatchQueue
  
  init(browser: Browsing, cache: QueueCaching, user: EntryQueueHost) {
    self.browser = browser
    self.cache = cache
    self.user = user
    
    self.target = OperationQueue.current!.underlyingQueue!
  }
  
  var entriesBlock: (([Entry], Error?) -> Void)?
  var fetchQueueCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the entries.
  weak var op: Operation?
  
  private func done(but error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    os_log("done: %{public}@", log: log, type: .debug,
           er != nil ? String(reflecting: er) : "OK")
    
    if let cb = fetchQueueCompletionBlock {
      target.async {
        cb(er)
      }
    }
    
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
        self.target.async { [weak self] in
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
      
      self.target.async { [weak self] in
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
    operationQueue.addOperation(op)
    return op
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: @escaping ((_ error: Error?) -> Void)) {
    guard !entries.isEmpty else {
      return enqueueCompletionBlock(nil)
    }
    
    os_log("enqueueing", log: log, type: .debug)
    
    operationQueue.addOperation {
      assert(!Thread.isMainThread)
      do {
        try self.queue.prepend(items: entries)
        let locators = entries.map { EntryLocator(entry: $0) }
        try self.cache.add(entries: locators)
      } catch {
        return enqueueCompletionBlock(error)
      }
      
      enqueueCompletionBlock(nil)
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
      }
    }
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: @escaping ((_ error: Error?) -> Void)) {
    os_log("dequeueing", log: log, type: .debug)
    
    operationQueue.addOperation {
      assert(!Thread.isMainThread)
      do {
        try self.queue.remove(entry)
        let guid = entry.guid
        try self.cache.remove(guids: [guid])
      } catch {
        return dequeueCompletionBlock(error)
      }
      
      dequeueCompletionBlock(nil)
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
      }
    }
  }
  
  // MARK: Queue

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

