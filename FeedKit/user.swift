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

/// Wraps an entry locator, adding a timestamp for sorting. The queue is sorted
/// by timestamp.
public struct QueuedLocator {
  let locator: EntryLocator
  let ts: Date
}

extension QueuedLocator: Equatable {
  public static func ==(lhs: QueuedLocator, rhs: QueuedLocator) -> Bool {
    return lhs.locator == rhs.locator
  }
}

public protocol QueueCaching {
  func add(_ entries: [EntryLocator]) throws
  func remove(guids: [String]) throws
  func entries() throws -> [QueuedLocator]
}

// MARK: - Internals

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

public class UserCache: LocalCache {}

extension UserCache: QueueCaching {
  
  public func entries() throws -> [QueuedLocator] {
    var er: Error?
    var locators = [QueuedLocator]()
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        try db.query(fmt.SQLToSelectQueue) { skullError, row -> Int in
          guard skullError == nil else {
            er = skullError
            return 1
          }
          guard let r = row else {
            return 0
          }
          let locator = fmt.entryLocator(from: r)
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
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      guard let sql = fmt.SQLToUnqueue(guids: guids) else {
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
          let sql = fmt.SQLToQueue(entry: loc)
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
  
}

class FetchQueueOperation: Operation {
  
}

// TODO: Update queue after redirects
// TODO: Produce actual entries from thin air
// TODO: Sync with iCloud

/// EntryQueue persists our user’s queued up entries to consume.
public final class EntryQueue {
  
  public var delegate: QueueDelegate?
  
  let feedCache: FeedCaching
  let queueCache: QueueCaching
  
  /// Creates a fresh EntryQueue object.
  public init(feedCache: FeedCaching, queueCache: QueueCaching) {
    self.feedCache = feedCache
    self.queueCache = queueCache
  }
  
  fileprivate var queue = Queue<Entry>()
}

extension EntryQueue: Queueing {
  
  public func entries(
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    DispatchQueue.global(qos: .default).async {
      let locators = try! self.queueCache.entries().map { $0.locator }
      let entries = try! self.feedCache.entries(locators)
      DispatchQueue.main.async {
        entriesBlock(nil, entries)
        entriesCompletionBlock(nil)
      }
    }
    return Operation() // TODO: Wrap into FetchQueueOperation and return
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


