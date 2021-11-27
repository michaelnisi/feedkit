//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2017 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "EnqueueOperation")

/// Enqueues `entries` or entries found in `ProvidingEntries` dependencies.
final class EnqueueOperation: Operation, ProvidingEntries {
  private(set) var error: Error?
  private(set) var entries = Set<Entry>()
  
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
  }
  
  override func main() {
    os_log("starting EnqueueOperation", log: log, type: .info)

    do {
      guard error == nil else {
        // Although redundant, passing the error again for clarity.
        return done([], error)
      }

      let qualifieds: [Entry] = try {
        let notQueued = try candidates.filter {
          try !cache.isQueued($0.guid)
        }
        
        switch owner {
        case .user:
          return notQueued
          
        case .nobody:
          // For automatic updates, enqueueing not directly initiated by users,
          // we are only accepting the latest, not previously enqueued, entry
          // per feed.
          return try notQueued.latest().filter {
            try !cache.isPrevious($0.guid)
          }
          
        case .subscriber:
          return notQueued.latest()
        }
      }()
      
      guard !qualifieds.isEmpty else {
        os_log("nothing to enqueue", log: log, type: .info)
        return done([])
      }
      
      os_log("enqueueing: %@", log: log, type: .info, qualifieds)

      let prepended = user.queue.prepend(items: qualifieds)
      entries.formUnion(prepended)
      
      let prependedQueued: [Queued] = prepended.map {
        let loc = EntryLocator(entry: $0)
        switch owner {
        case .nobody, .subscriber:
          return .temporary(loc, Date(), $0.iTunes)
        case .user:
          return .pinned(loc, Date(), $0.iTunes)
        }
      }
      
      try cache.add(queued: prependedQueued)
      try cache.trim()

      let queued = try cache.queued()
      let diff = Set(queued).intersection(Set(prependedQueued))
      let diffGuids = diff.compactMap(\.entryLocator.guid)
      let newlyEnqueued = qualifieds.filter { diffGuids.contains($0.guid) }

      os_log("enqueued: %@", log: log, type: .info, newlyEnqueued)

      done(newlyEnqueued)
    } catch {
      os_log("enqueueing failed: %{public}@", log: log, type: .info, error as CVarArg)
      return done([], error)
    }
  }
}

extension Array where Element == Entry {
  /// Returns the latest entries per feed.
  func latest() -> [Entry] {
    let latestEntriesByFeeds = reduce([String: Entry]()) { acc, entry in
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
}
