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
  
  var sortOrderBlock: (([String]) -> Void)?
  var entriesBlock: ((Error?, [Entry]) -> Void)?
  var entriesCompletionBlock: ((Error?) -> Void)?
  
  let browser: Browsing
  let cache: QueueCaching
  let target: DispatchQueue
  
  init(browser: Browsing, cache: QueueCaching, target: DispatchQueue) {
    self.browser = browser
    self.cache = cache
    self.target = target
  }
  
  private func done(with error: Error? = nil) {
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
  
  weak var op: Operation?
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard
      let q = OperationQueue.current?.underlyingQueue,
      let entriesBlock = self.entriesBlock else {
      fatalError("queue and entriesBlock required")
    }
    
    print("** \(q.label)")
    
    op = browser.entries(locators, entriesBlock: entriesBlock) { error in
      q.async {
        self.done(with: error)
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
      
      target.async {
        self.sortOrderBlock?(guids)
      }
      
      guard !isCancelled, !locators.isEmpty else {
        return done()
      }

      fetchEntries(for: locators)
    } catch {
      done(with: error)
    }
  }
 
}

// TODO: Consider making EntryQueue into User, organized into extensions
// ... for queueing, subscribing, preferences, etc.

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the queue.
public final class EntryQueue {
  
  let operationQueue: OperationQueue
  let serialQueue: DispatchQueue
  let queueCache: QueueCaching
  let browser: Browsing
  
  /// Creates a fresh EntryQueue object.
  ///
  /// - Parameters:
  ///   - queueCache: The cache to store the queue locallly.
  ///   - browser: The browser to retrieve entries.
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

// MARK: - Queueing

extension EntryQueue: Queueing {
  
  // TODO: Move all sorting into the operation and return entries as whole
  
  /// Fetches the queued entries and provides the populated queue.
  public func entries(
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    assert(Thread.isMainThread)
    
    let cache = self.queueCache
    let target = DispatchQueue.main
    let op = FetchQueueOperation(browser: browser, cache: cache, target: target)
    
    var sortedGuids: [String]?
    
    op.sortOrderBlock = { guids in
      assert(Thread.isMainThread)
      
      sortedGuids = guids
    }
    
    var dispatched = [Entry]()

    op.entriesBlock = { error, entries in
      assert(Thread.isMainThread)
      
      self.serialQueue.async {
        guard let guids = sortedGuids else {
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

        target.async {
          assert(Thread.isMainThread)
          entriesBlock(error, queuedEntries)
        }
        
        dispatched = dispatched + queuedEntries
      }
    }
    
    op.entriesCompletionBlock = { error in
      print("** entriesCompletionBlock")
      assert(Thread.isMainThread)
      
      self.serialQueue.async {
        target.async {
          entriesCompletionBlock(error)
        }
      }
    }
    
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
  public func add(_ entry: Entry) {
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
  public func remove(_ entry: Entry) {
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
  
  public func contains(_ entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
}

