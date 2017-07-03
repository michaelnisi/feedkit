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

// MARK: - Logging

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")

protocol UserCaching {
  func queue(entries: [EntryLocator]) throws
}

struct QueuedLocator {
  let locator: EntryLocator
  let ts: Date
}

class UserCache: LocalCache {
}

extension UserCache: UserCaching {
  
  func queue(entries: [EntryLocator]) throws {
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
  
  // TODO: Return QueuedLocators instead, because we need the timestamp
  
  func queuedEntryLocators() throws -> [EntryLocator] {
    var er: Error?
    var locators = [EntryLocator]()
    
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
  
}


