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
  
  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?
  
  let browser: Browsing
  let cache: QueueCaching
  var queue: Queue<Entry>
  let target: DispatchQueue
  
  init(browser: Browsing, cache: QueueCaching, queue: Queue<Entry>) {
    self.browser = browser
    self.cache = cache
    self.queue = queue
    self.target = OperationQueue.current!.underlyingQueue!
  }
  
  private func done(but error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    if let cb = entriesCompletionBlock {
      target.async {
        cb(er)
      }
    }
    
    entriesCompletionBlock = nil
    isFinished = true
    op?.cancel()
    op = nil
  }
  
  /// The browser operation, fetching the entries.
  weak var op: Operation?
  
  private func fetchEntries(for locators: [EntryLocator]) {
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
        try self.queue.append(items: sorted)
      } catch {
        if #available(iOS 10.0, *) {
          os_log("already in queue: %{public}@", log: log,  type: .error,
                 String(describing: error))
        }
      }
      
      let queuedEntries: [Entry] = self.queue.items.filter {
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
      // TODO: Handle error
      
      // Why does FeedKit.missingEntries appear in entriesBlock, instead of 
      // here, as I would have expected?
      
      // TODO: Define remove missing flag
      
      // If we aren‘t offline and the service is OK, we can remove missing
      // entries.
      let shouldRemoveMissing = true
      
      if shouldRemoveMissing {
        let found = dispatched.map { $0.guid }
        let wanted = locators.flatMap { $0.guid }
        let missing = wanted.filter { !found.contains($0) }
        
        print("** removing missing: \(missing)")
        
        do {
          try self.cache.remove(guids: missing)
        } catch {
          print("** \(error)")
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
  
  let operationQueue: OperationQueue
  let serialQueue: DispatchQueue
  let queueCache: QueueCaching
  let browser: Browsing
  
  /// Creates a fresh EntryQueue object.
  ///
  /// - Parameters:
  ///   - queueCache: The cache to store the queue locallly.
  ///   - browser: The browser to access feeds and entries.
  ///   - queue: The operation queue to execute operations on.
  public init(queueCache: QueueCaching, browser: Browsing, queue: OperationQueue) {
    self.queueCache = queueCache
    self.browser = browser
    self.operationQueue = queue
    self.serialQueue = queue.underlyingQueue!
  }
  
  /// The actual queue data structure. Starting off with an empty queue.
  fileprivate var queue = Queue<Entry>()
  
  public var delegate: QueueDelegate?
}

// MARK: - Subscribing

extension UserLibrary: Subscribing {
  public func subscribe(to urls: [String]) throws {
    throw FeedKitError.niy
  }
  
  public func unsubscribe(from urls: [String]) throws {
    throw FeedKitError.niy
  }
  
  public func feeds(feedsBlock: @escaping (Error?, [Feed]) -> Void,
    feedsCompletionBlock: @escaping (Error?) -> Void) -> Operation {
    return Operation()
  }
  
  public func has(subscription feedID: Int, cb: @escaping (Bool, Error?) -> Void) {
    
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
  
  /// Fetches the queued entries and provides the populated queue.
  public func entries(
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FetchQueueOperation(browser: browser, cache: queueCache, queue: queue)
    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  private func postDidChangeNotification() {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: FeedKitQueueDidChangeNotification),
      object: self
    )
  }
  
  /// Adds `entry` to the queue. This is an asynchronous function returning
  /// immediately. Uncritically, if it fails, an error is logged.
  public func enqueue(entry: Entry) {
    serialQueue.async {
      do {
        try self.queue.append(entry)
        let locator = EntryLocator(entry: entry)
        try self.queueCache.add(entries: [locator])
      } catch {
        if #available(iOS 10.0, *) {
          os_log("could not add %{public}@ to queue: %{public}@", log: log,
                 type: .error, entry.title, String(describing: error))
        }
        return
      }
      
      DispatchQueue.main.async {
        self.delegate?.queue(self, added: entry)
        self.postDidChangeNotification()
      }
    }
  }
  
  /// Removes `entry` from the queue. This is an asynchronous function returning
  /// immediately. Uncritically, if it fails, an error is logged.
  public func dequeue(entry: Entry) {
    serialQueue.async {
      do {
        try self.queue.remove(entry)
        let guid = entry.guid
        try self.queueCache.remove(guids: [guid])
      } catch {
        if #available(iOS 10.0, *) {
          os_log("could not remove %{public}@ from queue: %{public}@", log: log,
                 type: .error, entry.title, String(describing: error))
        }
        return
      }
      
      DispatchQueue.main.async {
        self.delegate?.queue(self, removedGUID: entry.guid)
        self.postDidChangeNotification()
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

