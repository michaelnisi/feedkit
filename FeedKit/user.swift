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

/// Same as QueuedLocator, just adds properties for syncing.
public struct SyncedLocator {
  public let locator: EntryLocator
  public let ts: Date
  public let recordName: String
  public let recordChangeTag: String
  
  public init(locator: EntryLocator, ts: Date, recordName: String, recordChangeTag: String) {
    self.locator = locator
    self.ts = ts
    self.recordName = recordName
    self.recordChangeTag = recordChangeTag
  }
}

public protocol UserSyncing {
  func synchronize()
}

public struct QueuedEntry {
  public let entry: Entry
  public let ts: TimeInterval
}

/// Wraps an entry locator, adding a timestamp for sorting. The queue is sorted
/// by timestamp. The timestamp is added here, in the application level, not in
/// the database, so we can receive these objects from anywhere: from iCloud,
/// say.
public struct QueuedLocator {
  public let locator: EntryLocator
  public let ts: Date // TODO: Change ts from Date to TimeInterval
  
  /// Creates a new queued locator adding a timestamp, for storage.
  ///
  /// - Parameters:
  ///   - locator: The entry locator to store.
  ///   - ts: Optionally, the timestamp, defaulting to now.
  public init(locator: EntryLocator, ts: Date? = nil) {
    self.locator = locator
    self.ts = ts ?? Date()
  }
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
        try db.query(SQL.toSelectQueue) { skullError, row -> Int in
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
    
    queue.sync {
      guard let sql = SQL.toUnqueue(guids: guids) else {
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
          let sql = fmt.SQLToQueue(entry: QueuedLocator(locator: loc, ts: Date()))
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
    entriesBlock: @escaping ([QueuedLocator], Error?) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    
    DispatchQueue.global(qos: .userInitiated).async {
      let locators = try! self.queueCache.entries()
      DispatchQueue.main.async {
        entriesBlock(locators, nil)
        entriesCompletionBlock(nil)
      }
    }
    
    // TODO: Return FetchQueueOperation depending on CKFetchRecordsOperation
    
    return FetchQueueOperation()
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


