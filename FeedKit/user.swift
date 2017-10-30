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
  }
  
  /// The actual queue data structure. Starting off with an empty queue.
  fileprivate var queue = Queue<Entry>()
  
  // TODO: Replace with notifications
  public var subscribeDelegate: SubscribeDelegate?
  
  fileprivate func post(name: NSNotification.Name) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: name, object: self)
    }
  }
  
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
  
  var feedsBlock: ((Error?, [Feed]) -> Void)?
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
          cb(error, feeds)
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
  
  public func add(subscriptions: [Subscription]) throws {
    guard !subscriptions.isEmpty else {
      return
    }
    
    try cache.add(subscriptions: subscriptions)
    
    for subscription in subscriptions {
      subscribeDelegate?.queue(self, added: subscription)
    }
    post(name: Notification.Name.FKQueueDidChange)
  }
  
  public func unsubscribe(from urls: [String]) throws {
    guard !urls.isEmpty else {
      return
    }
    
    let subscriptions = urls.map { Subscription(url: $0) }
    try cache.remove(subscriptions: subscriptions)
    
    for subscription in subscriptions {
      subscribeDelegate?.queue(self, removed: subscription)
    }
    post(name: Notification.Name.FKSubscriptionsDidChange)
  }
  
  /// The subscribed feeds of the user.
  @discardableResult public func feeds(
    feedsBlock: @escaping (Error?, [Feed]) -> Void,
    feedsCompletionBlock: @escaping (Error?) -> Void) -> Operation {
    let op = FetchFeedsOperation(browser: browser, cache: cache)
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  public func has(subscription url: String, cb: @escaping (Bool, Error?) -> Void) {
    assert(Thread.isMainThread)

    operationQueue.addOperation {
      do {
        let yes = try self.cache.has(url)
        DispatchQueue.main.async { cb(yes, nil) }
      } catch {
        DispatchQueue.main.async { cb(false, error) }
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

private final class FetchQueueOperation: FeedKitOperation {
  
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
  
  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?
  
  /// The browser operation, fetching the entries.
  weak var op: Operation?
  
  private func done(but error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    os_log("done: %{public}@", log: log, type: .debug,
           er != nil ? String(reflecting: er) : "OK")
    
    if let cb = entriesCompletionBlock {
      target.async {
        cb(er)
      }
    }
    
    entriesCompletionBlock = nil
    entriesBlock = nil
    
    isFinished = true
    op?.cancel()
    op = nil
  }
  
  // Identifiers of entries that already have been dispatched.
  var dispatched = [String]() {
    didSet {
      os_log("dispatched: %@", log: log, type: .debug, dispatched)
    }
  }
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty,
      let guids = self.sortedIds else {
      return done()
    }
    
    // TODO: Accumulate entries deliver them in order
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      assert(!Thread.isMainThread)

      let sorted: [Entry] = {
        var entriesByGuids = [String : Entry]()
        entries.forEach { entriesByGuids[$0.guid] = $0 }
        return guids.flatMap { entriesByGuids[$0] }
      }()
      
      do {
        try self.user.queue.append(items: sorted)
      } catch {
        switch error {
        case QueueError.alreadyInQueue(let entry as Entry):
          os_log("already enqueued: %@", log: log, entry.title)
        default:
          fatalError("unhandled error: \(error)")
        }
      }
      
      var queuedGuids = [String]()
      let queuedEntries: [Entry] = self.user.queue.filter {
        let guid = $0.guid
        queuedGuids.append(guid)
        return !self.dispatched.contains(guid)
      }
      
      guard !queuedGuids.isEmpty else {
        return
      }
      
      self.target.async { [weak self] in
        guard let cb = self?.entriesBlock else {
          return
        }
        cb(error, queuedEntries)
      }
      
      self.dispatched = self.dispatched + queuedGuids
    }) { error in
      defer {
        self.target.async { [weak self] in
          self?.done(but: error)
        }
      }
      
      guard error == nil else {
        return
      }
      
      // Cleaning up, if we aren‘t offline and the remote service is OK, as
      // indicated by having no error here, we can go ahead and remove missing
      // entries. Although, a specific feed‘s server might be offline for a
      // second, while the remote cache is cold, but well, tough luck. If no
      // entries are missing, we are done.

      let missing = Array(Set(guids).subtracting(self.dispatched))
      guard !missing.isEmpty else {
        return
      }
      
      do {
        os_log("remove missing entries: %{public}@", log: log, type: .debug,
               String(reflecting: missing))
        try self.cache.remove(guids: missing)
      } catch {
        os_log("could not remove missing: %{public}@", log: log, type: .error,
               error as CVarArg)
        
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
        // TODO: Remove all items from queue
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
  
  var page: FKPage?
  
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
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty,
      let guids = self.sortedIds else {
        return done()
    }
    
    var acc = [Entry]()
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      assert(!Thread.isMainThread)
      guard error == nil else {
        fatalError("unhandled error: \(error!)")
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
        try self.user.queue.append(items: sorted)
      } catch {
        switch error {
        case QueueError.alreadyInQueue(let entry as Entry):
          os_log("already enqueued: %@", log: log, entry.title)
        default:
          fatalError("unhandled error: \(error)")
        }
      }

      self.target.async { [weak self] in
        guard let cb = self?.entriesBlock else {
          return
        }
        cb(sorted, error)
      }
      
      // Cleaning up, if we aren‘t offline and the remote service is OK, as
      // indicated by having no error here, we can go ahead and remove missing
      // entries. Although, a specific feed‘s server might be offline for a
      // second, while the remote cache is cold, but well, tough luck. If no
      // entries are missing, we are done.
      
      let found = sorted.map { $0.guid }
      let missing = Array(Set(guids).subtracting(found))
      guard !missing.isEmpty else {
        return
      }
      
      do {
        os_log("remove missing entries: %{public}@", log: log, type: .debug,
               String(reflecting: missing))
        try self.cache.remove(guids: missing)
      } catch {
        os_log("could not remove missing: %{public}@", log: log, type: .error,
               error as CVarArg)
        
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
        // TODO: Remove all items from queue
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
  
  @discardableResult public func fetchQueue(
    page: FKPage,
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FKFetchQueueOperation(browser: browser, cache: cache, user: self)
    op.page = page
    op.entriesBlock = entriesBlock
    op.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  @discardableResult public func queued(
    queuedBlock: @escaping (_ queued: [Queued], _ queuedError: Error?) -> Void,
    queuedCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let cache = self.cache
    
    let op = BlockOperation {
      var queued: [Queued]!
      let target = OperationQueue.current!.underlyingQueue!
      
      do {
        queued = try cache.queued()
      } catch {
        return target.async {
          queuedCompletionBlock(error)
        }
      }
      
      var entries = [Queued]()
      
      for q in queued {
        switch q {
        case .entry:
          entries.append(q)
        }
      }
      
      target.async {
        queuedBlock(entries, nil)
      }
      
      target.async {
        queuedCompletionBlock(nil)
      }
    }
    
    operationQueue.addOperation(op)
    
    return op
  }
  
  @discardableResult public func entries(
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FetchQueueOperation(browser: browser, cache: cache, user: self)
    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: @escaping ((_ error: Error?) -> Void)) {
    guard !entries.isEmpty else {
      return enqueueCompletionBlock(nil)
    }
    
    operationQueue.addOperation {
      do {
        try self.queue.prepend(items: entries)
        let locators = entries.map { EntryLocator(entry: $0) }
        try self.cache.add(entries: locators)
      } catch {
        return enqueueCompletionBlock(error)
      }
      
      enqueueCompletionBlock(nil)
      
      self.post(name: Notification.Name.FKQueueDidChange)
    }
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: @escaping ((_ error: Error?) -> Void)) {
    operationQueue.addOperation {
      do {
        try self.queue.remove(entry)
        let guid = entry.guid
        try self.cache.remove(guids: [guid])
      } catch {
        return dequeueCompletionBlock(error)
      }
      
      dequeueCompletionBlock(nil)
      
      self.post(name: Notification.Name.FKQueueDidChange)
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

