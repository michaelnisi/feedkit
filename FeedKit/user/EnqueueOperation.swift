//
//  EnqueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

/// Enqueues `entries` or entries found in `ProvidingEntries` dependencies.
final class EnqueueOperation: Operation, ProvidingEntries {
  
  // MARK: ProvidingEntries
  
  private(set) var error: Error?
  private(set) var entries = Set<Entry>()
  
  // MARK: -
  
  private func findEntries() throws -> [Entry] {
    var found = Set<Entry>()
    for dep in dependencies {
      if case let req as ProvidingEntries = dep {
        guard req.error == nil else {
          throw req.error!
        }
        found.formUnion(req.entries)
      }
    }
    return Array(found)
  }
  
  private var _candidates: [Entry]?
  
  /// Initially passed or dependently provided entries to enqueue.
  private var candidates: [Entry] {
    get {
      guard let c = _candidates else {
        do {
          _candidates = try findEntries()
        } catch {
          self.error = error
          _candidates = []
        }
        return _candidates!
      }
      return c
    }
  }
  
  private var user: EntryQueueHost
  private let cache: QueueCaching
  
  var owner = QueuedOwner.nobody
  
  init(user: EntryQueueHost, cache: QueueCaching, entries: [Entry]? = nil) {
    self.user = user
    self.cache = cache
    self._candidates = entries
    
    super.init()
  }
  
  var enqueueCompletionBlock: ((_ enqueued: [Entry], _ error: Error?) -> Void)?
  
  private func done(_ enqueued: [Entry], _ error: Error? = nil) {
    self.error = error
    
    enqueueCompletionBlock?(enqueued, error)
    
    guard !enqueued.isEmpty else {
      return os_log("nothing to enqueue", log: User.log)
    }

    let nc = NotificationCenter.default
    nc.post(name: .FKQueueDidChange, object: nil)
    for entry in enqueued {
      nc.post(name: .FKQueueDidEnqueue, object: nil, userInfo: [
        "entryGUID": entry.guid,
        "enclosureURL": entry.enclosure?.url as Any
      ])
    }
  }
  
  /// Returns the latest entries per feed in `entries`.
  static func latest(entries: [Entry]) -> [Entry] {
    let latestEntriesByFeeds = entries.reduce([String: Entry]()) { acc, entry in
      let feed = entry.feed
      guard let prev = acc[feed], prev.updated > entry.updated else {
        var tmp = acc
        tmp[feed] = entry
        return tmp
      }
      
      return acc
    }

    return Array(latestEntriesByFeeds.values)
  }
  
  override func main() {
    os_log("starting EnqueueOperation", log: User.log, type: .debug)
    
    var enqueued = [Entry]()
    
    do {
      guard error == nil else {
        // Although redundant, passing the error again for clarity.
        return done([], error)
      }
      
      let qualifieds: [Entry] = try {
        let notEnqueuedYet = try candidates.filter {
          try !cache.isQueued($0.guid)
        }
        
        // For automatic updates, not directly initiated by users, we are
        // only accepting the latest entry per feed.
        
        if case .nobody = owner {
          return EnqueueOperation.latest(entries: notEnqueuedYet)
        }
        
        return notEnqueuedYet
      }()
      
      guard !qualifieds.isEmpty else {
        return done([])
      }
      
      os_log("enqueueing: %{public}@", log: User.log, type: .debug, qualifieds)

      entries.formUnion(user.queue.prepend(items: qualifieds))
      
      let queued: [Queued] = qualifieds.map {
        enqueued.append($0)
        let loc = EntryLocator(entry: $0)
        switch owner {
        case .nobody:
          return Queued.temporary(loc, Date(), $0.iTunes)
        case .user:
          return Queued.pinned(loc, Date(), $0.iTunes)
        }
      }
      
      try cache.add(queued: queued)
    } catch {
      os_log("enqueueing failed: %{public}@",
             log: User.log, type: .debug, error as CVarArg)
      return done([], error)
    }
    
    done(enqueued)
  }
  
}
