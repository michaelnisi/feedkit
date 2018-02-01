//
//  EnqueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

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
  
  private func done(_ error: Error? = nil) {
    self.error = error
    
    enqueueCompletionBlock?(Array(entries), error)

    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
    }
  }
  
  override func main() {
    do {
      guard error == nil else {
        // Although redundant, passing the error again for clarity.
        return done(error)
      }
      
      guard !candidates.isEmpty else {
        os_log("nothing to enqueue", log: User.log, type: .debug)
        return done()
      }
      
      os_log("enqueueing: %{public}@", log: User.log, type: .debug, candidates)

      entries.formUnion(user.queue.prepend(items: candidates))
      let locators = candidates.map { EntryLocator(entry: $0) }
      try cache.add(entries: locators, belonging: owner)
    } catch {
      os_log("enqueueing failed: %{public}@",
             log: User.log, type: .debug, error as CVarArg)
      return done(error)
    }
    
    done()
  }
  
}
