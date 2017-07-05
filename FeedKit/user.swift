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
struct QueuedLocator {
  let locator: EntryLocator
  let ts: Date
}

extension QueuedLocator: Equatable {
  static func ==(lhs: QueuedLocator, rhs: QueuedLocator) -> Bool {
    return lhs.locator == rhs.locator
  }
}

protocol QueueCaching {
  func add(_ entries: [EntryLocator]) throws
  func remove(guids: [String]) throws
  func entries() throws -> [QueuedLocator]
}

// MARK: - Internals

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

class UserCache: LocalCache {}

extension UserCache: QueueCaching {
  
  func entries() throws -> [QueuedLocator] {
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
  
  func remove(guids: [String]) throws {
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
  
  func add(_ entries: [EntryLocator]) throws {
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


