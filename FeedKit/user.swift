//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

private final class FetchQueueOperation: FeedKitOperation {
  
  let browser: Browsing
  let cache: QueueCaching
  var user: UserLibrary
  
  let target: DispatchQueue
  
  init(browser: Browsing, cache: QueueCaching, user: UserLibrary) {
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
    guard !isCancelled, locators.isEmpty else {
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

/// The `UserLibrary` manages the user‘s data, for example, feed subscriptions 
/// and queue.
public final class UserLibrary {
  
  let cache: UserCaching
  let browser: Browsing
  let operationQueue: OperationQueue
  
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

  fileprivate func postDidChangeNotification(name rawValue: String) {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: rawValue),
      object: self
    )
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
    postDidChangeNotification(name: FeedKitSubscriptionsDidChangeNotification)
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
    postDidChangeNotification(name: FeedKitSubscriptionsDidChangeNotification)
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
  
  // Updates subscribed feeds.
  //
  // - Parameters:
  //   - updateComplete: The block to execute when updating completes.
  //   - newData: `true` if new data has been received.
  //   - error: An error if something went wrong.
  public func update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    if #available(iOS 10.0, *) {
      os_log("updating", log: log,  type: .info)
    }
    updateComplete(true, nil)
  }
}

// MARK: - Queueing

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the queue.
extension UserLibrary: Queueing {
  
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
  public func entries(
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FetchQueueOperation(browser: browser, cache: cache, user: self)
    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  /// Adds `entry` to the queue. This is an asynchronous function returning
  /// immediately. Uncritically, if it fails, an error is logged.
  public func enqueue(entry: Entry) {
    operationQueue.addOperation {
      do {
        try self.queue.prepend(entry)
        let locator = EntryLocator(entry: entry)
        try self.cache.add(entries: [locator])
      } catch {
        if #available(iOS 10.0, *) {
          os_log("could not add %{public}@ to queue: %{public}@", log: log,
                 type: .error, entry.title, String(describing: error))
        }
        return
      }
      
      DispatchQueue.main.async {
        self.queueDelegate?.queue(self, added: entry)
        self.postDidChangeNotification(name: FeedKitQueueDidChangeNotification)
      }
    }
  }
  
  /// Removes `entry` from the queue. This is an asynchronous function returning
  /// immediately. Uncritically, if it fails, an error is logged.
  public func dequeue(entry: Entry) {
    operationQueue.addOperation {
      do {
        try self.queue.remove(entry)
        let guid = entry.guid
        try self.cache.remove(guids: [guid])
      } catch {
        if #available(iOS 10.0, *) {
          os_log("could not remove %{public}@ from queue: %{public}@", log: log,
                 type: .error, entry.title, String(describing: error))
        }
        return
      }
      
      DispatchQueue.main.async {
        self.queueDelegate?.queue(self, removedGUID: entry.guid)
        self.postDidChangeNotification(name: FeedKitQueueDidChangeNotification)
      }
    }
  }
  
  public func isQueued(entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
}

