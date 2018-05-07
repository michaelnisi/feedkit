//
//  EnqueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

enum EnqueueOperationError: Error {
  
  /// Using an error here to internally signal questionable usage and for
  /// preventing ourselves from dispatching redundant queue change events.
  /// This error isn’t critical, in fact, not knowing the queue state at call
  /// site might be reasonable.
  case nothingToEnqueue
  
}

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
  
  private var _owner: QueuedOwner?
  var owner: QueuedOwner {
    get { return _owner ?? .nobody }
    set { _owner = newValue }
  }
  
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
    
    // TODO: Remove EnqueueOperationError.nothingToEnqueue
    
    if let er = error, case EnqueueOperationError.nothingToEnqueue = er {
      return os_log("nothing to enqueue", log: User.log)
    }
    
    DispatchQueue.main.async {
      let nc = NotificationCenter.default
      
      nc.post(name: .FKQueueDidChange, object: nil)
      
      for entry in enqueued {
        nc.post(name: .FKQueueDidEnqueue, object: nil, userInfo: [
          "entryGUID": entry.guid,
          "enclosureURL": entry.enclosure?.url as Any
        ])
      }
    }
  }
  
  override func main() {
    os_log("starting EnqueueOperation", log: User.log, type: .debug)
    
    var enqueued = [Entry]()
    
    do {
      guard error == nil else {
        // Although redundant, passing the error again for clarity.
        return done([], error)
      }

      let candidates = try self.candidates.filter {
        try !cache.isQueued($0.guid)
      }

      guard !candidates.isEmpty else {
        return done([], EnqueueOperationError.nothingToEnqueue)
      }
      
      os_log("enqueueing: %{public}@", log: User.log, type: .debug, candidates)

      entries.formUnion(user.queue.prepend(items: candidates))
      
      let queued: [Queued] = candidates.map {
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
