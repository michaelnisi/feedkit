//
//  FetchQueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

final class FetchQueueOperation: FeedKitOperation {
  let browser: Browsing
  let cache: QueueCaching
  var user: UserLibrary
  
  init(browser: Browsing, cache: QueueCaching, user: UserLibrary) {
    self.browser = browser
    self.cache = cache
    self.user = user
  }
  
  var entriesBlock: (([Entry], Error?) -> Void)?
  var fetchQueueCompletionBlock: ((Error?) -> Void)?
  
  private func submit(resulting entries: [Entry], error: Error? = nil) {
    entriesBlock?(entries, error)
  }
  
  /// The browser operation, fetching the entries.
  weak var op: Operation?
  
  private func done(but error: Error? = nil) {
    let er = isCancelled ? FeedKitError.cancelledByUser : error
    
    os_log("done: %{public}@", log: User.log, type: .debug,
           er != nil ? String(reflecting: er) : "OK")
    
    fetchQueueCompletionBlock?(er)

    isFinished = true
    
    entriesBlock = nil
    fetchQueueCompletionBlock = nil
    
    op?.cancel()
    op = nil
  }
  
  /// Collects a list of unique GUIDs that should be removed from the queue.
  private static func guidsToDequeue(
    with entries: [Entry], for guids: [String], respecting error: Error?
  ) -> [String] {
    let found = entries.map { $0.guid }
    let a = Array(Set(guids).subtracting(found))
    
    guard let er = error else {
      return Array(Set(a))
    }
    
    switch er {
    case FeedKitError.serviceUnavailable:
      os_log("service unavailable: kept missing: %{public}@", log: User.log, a)
      return []
    case FeedKitError.missingEntries(let locators):
      return Array(Set(a + locators.compactMap { $0.guid }))
    default:
      return Array(Set(a))
    }
  }
  
  /// Returns currently enqueued entries, after dequeuing missing entries, not
  /// caused by service errors. Although, a specific feed‘s server might have
  /// been offline for a minute, while the remote cache was cold, but well,
  /// tough luck.
  ///
  /// - Parameters:
  ///   - entries: The entries we have successfully received.
  ///   - guids: GUIDs of the entries we had requested.
  ///   - error: An optional error to take into consideration.
  private func queuedEntries(
    with entries: [Entry], for guids: [String], respecting error: Error?
    ) -> [Entry] {
    let missing = FetchQueueOperation.guidsToDequeue(
      with: entries, for: guids, respecting: error)
    
    guard !missing.isEmpty else {
      os_log("queue complete", log: User.log, type: .debug)
      return user.queue.items
    }
    
    do {
      os_log("removing missing entries: %{public}@",
             log: User.log, type: .debug, String(reflecting: missing))
      
      for guid in missing {
        try user.queue.removeItem(with: guid.hashValue)
      }
      
      try cache.removeQueued(missing)
    } catch {
      os_log("could not remove missing: %{public}@", log: User.log, type: .error,
             error as CVarArg)
    }
    
    return user.queue.items
  }
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty,
      let guids = self.sortedIds else {
        return done()
    }
    
    var acc = [Entry]()
    var accError: Error?
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      // TODO: Handle missing entries correctly, no need to abort
//      guard error == nil else {
//        accError = error
//        return
//      }
      
      guard !entries.isEmpty else {
        os_log("no entries", log: User.log)
        return
      }
      
      acc = acc + entries
    }) { error in
      if let er = error {
        guard !acc.isEmpty else {
          os_log("fetching entries failed: %{public}@",
                 log: User.log, type: .error, String(describing: er))
          return self.done(but: error)
        }
        os_log("got entries and error: %{public}@",
               log: User.log, type: .error, String(describing: er))
      }

      let sorted: [Entry] = {
        var entriesByGuids = [String : Entry]()
        acc.forEach { entriesByGuids[$0.guid] = $0 }
        return guids.compactMap { entriesByGuids[$0] }
      }()
      
      do {
        os_log("appending: %{public}@", log: User.log, type: .debug,
               String(reflecting: sorted))
        
        try self.user.queue.append(items: sorted)
      } catch {
        switch error {
        case QueueError.alreadyInQueue:
          os_log("already in queue", log: User.log)
        default:
          fatalError("unhandled error: \(error)")
        }
      }
      
      let entries = self.queuedEntries(
        with: sorted, for: guids, respecting: accError ?? error)
      
      os_log("entries in queue: %{public}@", log: User.log, type: .debug,
             String(reflecting: entries))
      
      func leave(_ error: Error? = nil) {
        self.submit(resulting: entries, error: accError)
        self.done(but: error)
      }
      
      guard let metadata = self.iTunesItems else {
        return leave()
      }
      
      let notSubscribed = metadata.filter {
        !self.user.has(subscription: $0.url)
      }
      
      // Assuming subscriptions’ metadata has been integrated already.
      guard !notSubscribed.isEmpty else {
        return leave()
      }
   
      do {
        try self.browser.integrate(iTunesItems: notSubscribed)
      } catch {
        return leave(error)
      }
      
      leave()
    }
  }
  
  // MARK: FeedKitOperation
  
  override func cancel() {
    super.cancel()
    op?.cancel()
  }
  
  /// The sorted guids of the items in the queue.
  private var sortedIds: [String]? {
    didSet {
      guard let guids = sortedIds else {
        user.queue.removeAll()
        try! cache.removeQueued() // redundant
        return
      }
      let queuedGuids = user.queue.map { $0.guid }
      let guidsToRemove = Array(Set(queuedGuids).subtracting(guids))
      
      var queuedEntriesByGuids = [String : Entry]()
      user.queue.forEach { queuedEntriesByGuids[$0.guid] = $0 }
      
      for guid in guidsToRemove {
        if let entry = queuedEntriesByGuids[guid] {
          try! user.queue.remove(entry)
        }
      }
    }
  }
  
  /// User metadata, preloaded with the queued items, for merging into the
  /// browser cache after entries have been fetched. In this order, for
  /// receiving the feeds, parents of queued entries, first, or else we had
  /// nothing to merge with, obviously.
  private var iTunesItems: [ITunesItem]?
  
  override func start() {
    os_log("starting FetchQueueOperation", log: User.log, type: .debug)
    
    guard !isCancelled else {
      return done()
    }
    
    isExecuting = true
    
    var queued: [Queued]!
    do {
      queued = try cache.queued()
    } catch {
      done(but: error)
    }
    
    guard !isCancelled, !queued.isEmpty else {
      return done()
    }
    
    var guids = [String]()
    
    let locators: [EntryLocator] = queued.compactMap {
      let loc = $0.entryLocator
      guard let guid = loc.guid else {
        fatalError("missing guid")
      }
      guids.append(guid)
      return loc.including
    }
    
    sortedIds = guids
    
    guard !isCancelled, !locators.isEmpty else {
      return done()
    }
    
    // Keeping metadata around, for merging it later.
    self.iTunesItems = queued.compactMap {
      switch $0 {
      case .pinned(_, _, let iTunes), .temporary(_, _, let iTunes):
        return iTunes
      case .previous:
        return nil
      }
    }
    
    fetchEntries(for: locators)
  }
  
}
