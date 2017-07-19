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
  
  // TODO: Replace EntryLocator with QueueEntryLocator
  
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
    dump(synced)
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
    entriesBlock: @escaping ([Queued], Error?) -> Void,
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


