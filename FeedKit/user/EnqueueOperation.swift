//
//  EnqueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

class EnqueueOperation: Operation, Providing {
  
  var user: EntryQueueHost
  let cache: QueueCaching
  
  var _entries: [Entry]?
  lazy var entries: [Entry] = {
    guard let e = _entries else {
      do {
        _entries = try findEntries()
      } catch {
        self.error = error
      }
      return _entries!
    }
    return e
  }()
  
  var enqueueCompletionBlock: ((_ enqueued: [Entry], _ error: Error?) -> Void)?

  // MARK: Providing
  
  private(set) var error: Error?
  
  private func findEntries() throws -> [Entry] {
    var found = Set<Entry>()
    for dep in dependencies {
      if case let req as ProvidingEntries = dep {
        guard req.error == nil else {
          throw req.error!
        }
        os_log("found entry provider", log: User.log, type: .debug)
        found.formUnion(req.entries)
      }
    }
    return Array(found)
  }
  
  init(user: EntryQueueHost, cache: QueueCaching, entries: [Entry]? = nil) {
    self.user = user
    self.cache = cache
    
    self._entries = entries
    
    super.init()
  }
  
  private func done(_ error: Error? = nil) {
    self.error = error
    
    enqueueCompletionBlock?(enqueued ?? [], error)

    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
    }
  }
  
  // TODO: Use entries properety for result
  private var enqueued: [Entry]?
  
  override func main() {
    do {
      guard error == nil else {
        // Although redundant, passing the error again for clarity.
        return done(error)
      }
      
      guard !entries.isEmpty else {
        os_log("nothing new to enqueue", log: User.log, type: .debug)
        return done()
      }
      
      os_log("enqueueing: %{public}@", log: User.log, type: .debug, entries)

      enqueued = user.queue.prepend(items: entries)
      let locators = entries.map { EntryLocator(entry: $0) }
      try cache.add(entries: locators)
    } catch {
      os_log("enqueueing failed: %{public}@",
             log: User.log, type: .debug, error as CVarArg)
      return done(error)
    }
    
    done()
  }
  
}
