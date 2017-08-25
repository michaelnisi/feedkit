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

public class UserCache: LocalCache {}

// MARK: - QueueCaching

extension UserCache: QueueCaching {
  
  public func _queued(sql: String) throws -> [Queued] {
    var er: Error?
    var locators = [Queued]()
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        try db.query(sql) { skullError, row -> Int in
          guard skullError == nil else {
            er = skullError
            return 1
          }
          guard let r = row else {
            return 0
          }
          let locator = fmt.queuedLocator(from: r)
          locators.append(locator)
          return 0
        }
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
    
    return locators
  }
  
  /// The user‘s queued entries, sorted by time queued.
  public func queued() throws -> [Queued] {
    return try _queued(sql: SQLFormatter.SQLToSelectAllQueued)
  }
  
  /// Returns previously queued entries, limited to the most recent 25.
  public func previous() throws -> [Queued] {
    return try _queued(sql: SQLFormatter.SQLToSelectAllPrevious)
  }
  
  /// The queued entries, which not have been synced and are only locally
  /// cached, hence the name.
  public func local() throws -> [Queued] {
    return try _queued(sql: SQLFormatter.SQLToSelectLocallyQueuedEntries)
  }
  
  /// CloudKit record names of abandoned records by record zone names.
  public func zombieRecords() throws -> [String : String] {
    var er: Error?
    var records = [String : String]()
    
    let db = self.db
    
    try queue.sync {
      // TODO: Update SQL to include zones
      let sql = SQLFormatter.SQLToSelectAbandonedRecords
      try db.query(sql) { error, row -> Int in
        guard error == nil else {
          er = error
          return 1
        }
        guard
          let r = row,
          let record = r["record_name"] as? String,
          let zone = r["zone_name"] as? String else {
          er = FeedKitError.unexpectedDatabaseRow
          return 1
        }
        
        records[zone] = record
        
        return 0
      }
    }
    
    if let error = er  { throw error }
    
    return records
  }
  
  public func remove(guids: [String]) throws {
    var er: Error?
    
    queue.sync {
      guard let sql = SQLFormatter.SQLToUnqueue(guids: guids) else {
        return
      }
      do {
        try db.exec(sql)
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
  public func remove(recordNames: [String]) throws {
    guard !recordNames.isEmpty else {
      return
    }
    
    var er: Error?
    
    queue.sync {
      guard let sql = SQLFormatter.SQLToDeleteRecords(with: recordNames) else {
        return
      }
      do {
        try db.exec(sql)
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
  public func add(_ entries: [EntryLocator]) throws {
    var er: Error?
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        let sql = entries.reduce([String]()) { acc, loc in
          guard er == nil else {
            return acc
          }
          guard let guid = loc.guid else {
            er = FeedKitError.invalidEntry(reason: "missing guid")
            return acc
          }
          let sql = fmt.SQLToQueue(entry: loc, with: guid)
          return acc + [sql]
        }.joined(separator: "\n")
        
        try db.exec(sql)
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
  // TODO: Switch on the type of synced item
  
  public func add(synced: [Synced]) throws {
    guard !synced.isEmpty else {
      return
    }
    
    var er: Error?
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        let sql = try synced.reduce([String]()) { acc, loc in
          let sql = try fmt.SQLToQueueSynced(locator: loc)
          return acc + [sql]
        }.joined(separator: "\n")
        
        try db.exec(["BEGIN;", sql, "COMMIT;"].joined(separator: "\n"))
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
}

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
      let entriesBlock = self.entriesBlock,
      let entriesCompletionBlock = self.entriesCompletionBlock else {
      return
    }
    
    op = browser.entries(
      locators,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
    
    op?.completionBlock = {
      self.done()
    }
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
          try self.queue.add(items: sorted)
        } catch {
          if #available(iOS 10.0, *) {
            os_log("already in queue: %{public}@", log: log,  type: .error,
                   String(describing: error))
          }
        }

        target.async {
          assert(Thread.isMainThread)
          entriesBlock(error, sorted)
        }
      }
    }
    
    op.entriesCompletionBlock = { error in
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
        try self.queue.add(entry)
        let locator = EntryLocator(entry: entry)
        try self.queueCache.add([locator])
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

