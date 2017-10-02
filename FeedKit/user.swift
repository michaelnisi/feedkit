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

@available(iOS 10.0, *)
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
  
  public var queueDelegate: QueueDelegate?
  
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
  
  public func subscribe(to urls: [String]) throws {
    guard !urls.isEmpty else {
      return
    }
    
    let subscriptions = urls.map { Subscription(url: $0) }
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
  
  public func has(subscription feedID: Int, cb: @escaping (Bool, Error?) -> Void) {
    assert(Thread.isMainThread)

    operationQueue.addOperation {
      do {
        let yes = try self.cache.has(feedID)
        DispatchQueue.main.async { cb(yes, nil) }
      } catch {
        DispatchQueue.main.async { cb(false, error) }
      }
    }
  }

}

// MARK: - Updating

extension UserLibrary: Updating {
  
  /// Updates subscribed feeds.
  ///
  /// - Parameters:
  ///   - updateComplete: The block to execute when updating completes.
  ///   - newData: `true` if new data has been received.
  ///   - error: An error if something went wrong.
  public func update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    if #available(iOS 10.0, *) {
      os_log("updating", log: log,  type: .info)
    }
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
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty else {
      return done()
    }
    
    var dispatched = [Entry]()
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      assert(!Thread.isMainThread)
      guard let guids = self.sortedIds else {
        fatalError("sorted guids required")
      }
      
      var dict = [String : Entry]()
      entries.forEach { dict[$0.guid] = $0 }
      
      let sorted: [Entry] = guids.flatMap { dict[$0] }
      
      do {
        try self.user.queue.append(items: sorted)
      } catch {
        if #available(iOS 10.0, *) {
          os_log("already in queue: %{public}@", log: log,  type: .error,
                 String(describing: error))
        }
      }
      
      let queuedEntries: [Entry] = self.user.queue.items.filter {
        !dispatched.contains($0)
      }
      
      self.target.async { [weak self] in
        guard let cb = self?.entriesBlock else {
          return
        }
        cb(error, queuedEntries)
      }
      
      dispatched = dispatched + queuedEntries
    }) { error in
      if error == nil {
        // If we aren‘t offline and the service is OK, we can remove missing
        // entries.
        
        // TODO: Browser should expose service health
        
        let found = dispatched.map { $0.guid }
        let wanted = locators.flatMap { $0.guid }
        let missing = wanted.filter { !found.contains($0) }
        
        print("** missing: \(missing)")
        
        do {
          try self.cache.remove(guids: missing)
        } catch {
          if #available(iOS 10.0, *) {
            os_log("failed to remove missing: %{public}@", log: log,
                   type: .error, String(describing: error))
          }
        }
      }
      
      self.target.async { [weak self] in
        self?.done(but: error)
      }
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  /// The sorted guids of the items in the queue.
  private var sortedIds: [String]?
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    do {
      let queued = try cache.queued()
      
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
    } catch {
      done(but: error)
    }
  }
  
}

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the queue.
extension UserLibrary: Queueing {
  
  public var isEmpty: Bool {
    return queue.isEmpty
  }
  
  /// Fetches entries in a user‘s queue populating the `queue` object of this
  /// `UserLibrary` instance. The `entriesBlock` receives the entries sorted, 
  /// according to the queue, with best effort. Queue order may vary, dealing
  /// with latency and unavailable entries.
  ///
  /// - Parameters:
  ///   - entriesBlock: Applied zero, one, or two times passing fetched
  /// and/or cached entries. The error is currently not in use.
  ///   - entriesError: An optional error, specific to these entries.
  ///   - entries: All or some of the requested entries.
  ///
  ///   - entriesCompletionBlock: The completion block is applied when
  /// all entries have been dispatched.
  ///   - error: The, optional, final error of this operation, as a whole.
  ///
  /// - Returns: Returns an executing `Operation`.
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
  
  /// Adds `entry` to the queue.
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
  
  /// Removes `entry` from the queue.
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
  
  // MARK: Drafts
  
  /// An event handler for when an episode was paused, or finished, during 
  /// playback.
  private func played(entry: Entry, until time: CMTime) {
    // TODO: Write
  }
  
  // TODO: Fetch entry (maybe queued) at once (to replace contains)
  
  /// Fetch `entries` for `locators`, queued or not. If an entry is in the queue
  /// its callback receives a timestamp `ts` of when it was enqueued.
  private func entries(
    for locators: [EntryLocator],
    entryBlock: ((_ entry: Entry, _ ts: Date?) -> Void),
    entryCompletionBlock: ((_ error: Error?) -> Void)) -> Operation {
    return Operation()
  }
  
  // MARK: Queue
  
  // These synchronous methods are super fast (AP), but may not be consistent.
  // https://en.wikipedia.org/wiki/CAP_theorem
  
  /// Returns `true` if `entry` has been enqueued, but unreliably, only looking
  /// at the queue, this may fail if the queue hasn‘t been populated.
  public func contains(entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
}

