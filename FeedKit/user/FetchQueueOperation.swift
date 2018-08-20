//
//  FetchQueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog.disabled

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
    
    os_log("done: %{public}@", log: log, type: .debug,
           er != nil ? String(reflecting: er) : "OK")
    
    fetchQueueCompletionBlock?(er)

    isFinished = true
    
    entriesBlock = nil
    fetchQueueCompletionBlock = nil
    
    op?.cancel()
    op = nil
  }
  
  /// Temporarily counting how often an entry has been missing.
  private static var missingCounter = [EntryGUID : Int]()
  
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
      os_log("service unavailable: kept missing: %{public}@", log: log, a)
      return []
    case FeedKitError.missingEntries(let locators):
      return Array(Set(a + locators.compactMap {
        guard let guid = $0.guid else {
          return nil
        }
        
        let count = missingCounter[guid] ?? 0
        let next = count + 1
        missingCounter[guid] = next
        
        // Giving missing entries five chances to return.
        guard next > 5 else {
          return nil
        }
        
        return guid
      }))
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
      os_log("queue complete", log: log, type: .debug)
      return user.queue.items
    }
    
    do {
      os_log("removing missing entries: %{public}@",
             log: log, type: .debug, String(reflecting: missing))
      
      // Removing queued from cache first, removing items from queue very
      // likely will throw uncritical not-in-queue errors.
      
      try cache.removeQueued(missing)
      for guid in missing {
        try user.queue.removeItem(with: guid.hashValue)
        FetchQueueOperation.missingCounter.removeValue(forKey: guid)
      }
    } catch {
      os_log("could not remove missing: %{public}@", log: log, type: .error,
             error as CVarArg)
    }

    return user.queue.items
  }
  
  private func dequeue(redirected entries: [Entry]) -> [Entry] {
    let guids = entries.compactMap { $0.isRedirected ? $0.guid : nil }
    
    guard !guids.isEmpty else {
      return entries
    }
    
    os_log("dequeuing entries of redirected feeds: %{public}@",
           log: log, entries.filter { guids.contains($0.guid) })
    
    do {
      try cache.removeQueued(guids)
    } catch {
      os_log("could not dequeue: %{public}@", log: log, error as CVarArg)
      
      // Actually, this is undefined, we should crash here, but without
      // proper tests, we can’t do that yet.
      
      return entries
    }
    
    return entries.filter { !guids.contains($0.guid) }
  }
  
  private func fetchEntries(for locators: [EntryLocator]) {
    guard !isCancelled, !locators.isEmpty,
      let guids = self.sortedIds else {
        return done()
    }
    
    var acc = [Entry]()
    var accError: Error?
    
    op = browser.entries(locators, entriesBlock: { error, entries in
      accError = error

      guard !entries.isEmpty else {
        os_log("no entries", log: log)
        return
      }
      
      acc = acc + entries
    }) { error in
      if let er = error {
        guard !acc.isEmpty else {
          os_log("fetching entries failed: %{public}@",
                 log: log, type: .error, String(describing: er))
          return self.done(but: error)
        }
        os_log("got entries and error: %{public}@",
               log: log, type: .error, String(describing: er))
      }
      
      let cleaned = self.dequeue(redirected: acc)

      let sorted: [Entry] = {
        var entriesByGuids = [String : Entry]()
        cleaned.forEach { entriesByGuids[$0.guid] = $0 }
        return guids.compactMap { entriesByGuids[$0] }
      }()
      
      os_log("setting new queue: %{public}@",
             log: log, type: .debug, String(reflecting: sorted))
      
      // Getting current entry first which might be not be enqueued.
      let prevCurrent = self.user.queue.current
      self.user.queue = Queue(items: sorted)
      
      if let entry = prevCurrent {
        do {
          os_log("skipping queue to previous entry: %{public}@",
                 log: log, type: .debug, entry.title)
          
          try self.user.queue.skip(to: entry)
        } catch {
          os_log("could not skip queue to previous entry %{public}@",
                 log: log, error as CVarArg)
          
          // Not sure what could be done here.
        }
      }

      let entries = self.queuedEntries(
        with: sorted, for: guids, respecting: accError ?? error)
      
      os_log("entries in queue: %{public}@", log: log, type: .debug,
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
  private var sortedIds: [EntryGUID]? {
    didSet {
      guard let guids = sortedIds else {
        try! cache.removeQueued()
        user.queue.removeAll()
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
    os_log("starting FetchQueueOperation", log: log, type: .debug)
    
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
