//
//  UserCache.swift
//  FeedKit
//
//  Created by Michael on 9/1/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

public class UserCache: LocalCache, UserCaching {}

// MARK: - SubscriptionCaching

extension UserCache: SubscriptionCaching {
  
  public func add(subscriptions: [Subscription]) throws {
    guard !subscriptions.isEmpty else {
      return
    }
    
    let fmt = sqlFormatter
    
    try queue.sync {
      let sql = [
        "BEGIN;",
        subscriptions.map {
          fmt.SQLToReplace(subscription: $0)
        }.joined(separator: "\n"),
        "COMMIT;"
      ].joined(separator: "\n")
      
      try db.exec(sql)
    }
  }
  
  public func remove(urls: [FeedURL]) throws {
    guard !urls.isEmpty else {
      return
    }
    
    try queue.sync {
      try db.exec(SQLFormatter.SQLToDelete(subscribed: urls))
    }
  }
  
  fileprivate func subscribed(sql: String) throws -> [Subscription] {
    return try queue.sync {
      var er: Error?
      var subscriptions = [Subscription]()
      
      try db.query(sql) { error, row in
        guard error == nil else {
          er = error
          return 1
        }
        guard let r = row else {
          return 1
        }
        
        subscriptions.append(self.sqlFormatter.subscription(from: r))
        
        return 0
      }
      
      if let error = er  { throw error }
      
      return subscriptions
    }
  }
  
  public func subscribed() throws -> [Subscription] {
    return try subscribed(sql: SQLFormatter.SQLToSelectSubscriptions)
  }
  
  public func has(_ url: String) throws -> Bool {
    return try subscribed().map { $0.url }.contains(url)
  }
}

// MARK: - QueueCaching

extension UserCache: QueueCaching {
  
  private func queryForQueued(using sql: String) throws -> [Queued] {
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
  
  public func queued() throws -> [Queued] {
    return try queryForQueued(using: SQLFormatter.SQLToSelectAllQueued)
  }
  
  public func previous() throws -> [Queued] {
    return try queryForQueued(using: SQLFormatter.SQLToSelectAllPrevious)
  }
  
  public func all() throws -> [Queued] {
    let prev = try previous()
    let current = try queued()
    let all = Set(prev + current)
    return Array(all)
  }
  
  public func latest() throws -> [EntryLocator] {
    var latestByFeeds = [FeedURL: EntryLocator]()
    let items = try all()
    for item in items {
      if case .entry(let loc, _) = item {
        if let lhs = latestByFeeds[loc.url], lhs.since > loc.since {
          continue // keep newer
        } else {
          latestByFeeds[loc.url] = loc
        }
      }
    }
    return Array(latestByFeeds.values)
  }
  
  public func removeAll() throws {
    try queue.sync {
      try db.exec(SQLFormatter.SQLToDeleteQueued)
    }
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
        let sql = try entries.reduce([String]()) { acc, loc in
          guard er == nil else {
            return acc
          }
          let sql = try fmt.SQLToQueue(entry: loc)
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
  
  public func hasQueued(guid: EntryGUID) throws -> Bool {
    let guids: [EntryGUID] = try queued().map {
      switch $0 {
      case .entry(let locator, _):
        return locator.guid!
      }
    }
    return guids.contains(guid)
  }
  
}

// MARK: - UserCacheSyncing

extension UserCache: UserCacheSyncing {
  
  public func removeQueue() throws {
    try queue.sync {
      try db.exec(SQLFormatter.SQLToRemoveQueue)
    }
  }
  
  public func removeLibrary() throws {
    try queue.sync {
      try db.exec(SQLFormatter.SQLToRemoveLibrary)
    }
  }
  
  public func deleteZombies() throws {
    try queue.sync {
      try db.exec(SQLFormatter.SQLToDeleteZombies)
    }
  }
  
  public func add(synced: [Synced]) throws {
    os_log("aborting attempt to add empty array", type: .debug)
    guard !synced.isEmpty else {
      return
    }
    
    var er: Error?
    
    let fmt = self.sqlFormatter
    
    queue.sync {
      do {
        let sql = try synced.reduce([String]()) { acc, item in
          let sql = try fmt.SQLToReplace(synced: item)
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
      os_log("aborting attempt to remove empty array", type: .debug)
      return
    }
    
    try queue.sync {
      try db.exec(SQLFormatter.SQLToDeleteRecords(with: recordNames))
    }
  }
  
  public func locallyQueued() throws -> [Queued] {
    return try queryForQueued(using:
      SQLFormatter.SQLToSelectLocallyQueuedEntries)
  }
  
  public func zombieRecords() throws -> [(String, String)] {
    var er: Error?
    var records = [(String, String)]()
    
    let db = self.db
    
    try queue.sync {
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
        
        records.append((zone, record))
        
        return 0
      }
    }
    
    if let error = er  { throw error }
    
    return records
  }
  
  public func locallySubscribed() throws -> [Subscription] {
    return try subscribed(sql: SQLFormatter.SQLToSelectLocallySubscribedFeeds)
  }
  
}
