//
//  UserCache.swift
//  FeedKit
//
//  Created by Michael on 9/1/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

public class UserCache: LocalCache {}

// MARK: - SubscriptionCaching

extension UserCache: SubscriptionCaching {
  
  public func add(subscriptions: [Subscription]) throws {
    try queue.sync {
      guard !subscriptions.isEmpty else {
        return
      }
      
      let sql = [
        "BEGIN;",
        subscriptions.map {
          SQLFormatter.SQLToSubscribe(to: $0.url, with: $0.images)
        }.joined(separator: "\n"),
        "COMMIT;"
      ].joined(separator: "\n")
      
      try db.exec(sql)
    }
  }
  
  public func remove(subscriptions: [String]) throws {
    try queue.sync {
      guard let sql = SQLFormatter.SQLToUnsubscribe(from: subscriptions) else {
        return
      }
      
      try db.exec(sql)
    }
  }
  
  fileprivate func _subscribed(sql: String) throws -> [Subscription] {
    return try queue.sync {
      var er: Error?
      var subscriptions = [Subscription]()
      
      try db.query(sql) { error, row in
        guard error == nil else {
          er = error
          return 1
        }
        guard
          let r = row,
          let s = SQLFormatter.subscription(from: r) else {
          return 1
        }
        
        subscriptions.append(s)
        
        return 0
      }
      
      if let error = er  { throw error }
      
      return subscriptions
    }
  }
  
  public func subscribed() throws -> [Subscription] {
    return try _subscribed(sql: SQLFormatter.SQLToSelectSubscriptions)
  }
}

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
  
  public func add(entries: [EntryLocator]) throws {
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
  
}

// MARK: - UserCacheSyncing

extension UserCache: UserCacheSyncing {
  
  public func add(synced: [Synced]) throws {
    guard !synced.isEmpty else {
      return
    }
    
    var er: Error?
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        let sql = try synced.reduce([String]()) { acc, item in
          let sql = try fmt.SQLToQueue(synced: item)
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
  
  public func locallySubscribed() throws -> [Subscription] {
    return try _subscribed(sql: SQLFormatter.SQLToSelectLocallySubscribedFeeds)
  }
  
}
