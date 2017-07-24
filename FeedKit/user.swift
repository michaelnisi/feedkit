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

public class UserCache: LocalCache {}

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

extension UserCache: QueueCaching {
  
  public func entries() throws -> [Queued] {
    var er: Error?
    var locators = [Queued]()
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        try db.query(SQLFormatter.SQLToSelectAllQueued) { skullError, row -> Int in
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
            // TODO: Remove fatalError
            fatalError("not queueable: missing GUID")
//            er = FeedKitError.invalidEntry(reason: "missing guid")
//            return acc
          }
          let sql = fmt.SQLToQueueEntry(locator: QueueEntryLocator(
            url: loc.url, guid: guid, since: loc.since
          ))
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
  
  public func add(synced: [Synced]) throws {
    var er: Error?
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        let sql = synced.reduce([String]()) { acc, loc in
          let sql = fmt.SQLToQueueSynced(locator: loc)
          return acc + [sql]
        }.joined(separator: "\n")
        
        try db.exec(["BEGIN TRANSACTION;", sql, "COMMIT;"].joined(separator: "\n"))
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
  }
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard
      let entriesBlock = self.entriesBlock,
      let entriesCompletionBlock = self.entriesCompletionBlock else {
      return
    }
    let op = browser.entries(
      locators, entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
    // TODO: Sort entries by queue order
    
    op.completionBlock = {
      self.done()
    }
  }
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    do {
      // TODO: Rename cache.entries() to cache.queued()
      let queued = try cache.entries()
      
      let locators: [EntryLocator] = queued.flatMap {
        switch $0 {
        case .locator(let locator, _):
          return locator.including
        }
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

// TODO: Update queue after redirects

public final class EntryQueue {
  
  // TODO: User proper operation queue
  let operationQueue = OperationQueue()
  
  public var delegate: QueueDelegate?
  
  let feedCache: FeedCaching // TODO: Remove
  
  let queueCache: QueueCaching
  let browser: Browsing
  
  /// Creates a fresh EntryQueue object.
  public init(feedCache: FeedCaching, queueCache: QueueCaching, browser: Browsing) {
    self.feedCache = feedCache
    self.queueCache = queueCache
    self.browser = browser
  }
  
  fileprivate var queue = Queue<Entry>()
}

extension EntryQueue: Queueing {

  public func entries(
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let cache = self.queueCache
    let target = DispatchQueue.main
    let op = FetchQueueOperation(browser: browser, cache: cache, target: target)
    op.entriesBlock = entriesBlock
    op.entriesCompletionBlock = entriesCompletionBlock
    operationQueue.addOperation(op)
    
    // TODO: Pass this to browser operationQueue.underlyingQueue
    
    return op
  }
  
  // TODO: Replace with entries
  
  public func locators(
    locatorsBlock: @escaping ([Queued], Error?) -> Void,
    locatorsCompletionBlock: @escaping (Error?) -> Void
  ) {
    
    DispatchQueue.global(qos: .userInitiated).async {
      let locators = try! self.queueCache.entries()
      DispatchQueue.main.async {
        locatorsBlock(locators, nil)
        locatorsCompletionBlock(nil)
      }
    }
  }
  
  private func postDidChangeNotification() {
    NotificationCenter.default.post(
      name: Notification.Name(rawValue: FeedKitQueueDidChangeNotification),
      object: self
    )
  }
  
  public func add(_ entry: Entry) throws {
    try queue.add(entry)
    
    delegate?.queue(self, added: entry)
    postDidChangeNotification()
    
    DispatchQueue.global(qos: .default).async {
      let entries = self.queue.enumerated()
      let locators = entries.map { EntryLocator(entry:  $0.element.value) }
      try! self.queueCache.add(locators)
    }
  }
  
  public func add(entries: [Entry]) throws {
    try queue.add(items: entries)
  }
  
  public func remove(_ entry: Entry) throws {
    try queue.remove(entry)
    
    delegate?.queue(self, removedGUID: entry.guid)
    postDidChangeNotification()
    
    DispatchQueue.global(qos: .default).async {
      let entries = self.queue.enumerated()
      let guids = entries.map { $0.element.value.guid }
      try! self.queueCache.remove(guids: guids)
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


