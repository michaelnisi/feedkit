//
//  user.swift
//  FeedKit
//
//  Created by Michael Nisi on 31/01/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import AVFoundation
import Foundation
import Skull
import os.log

// TODO: Integrate HTTP redirects
// TODO: Review update

struct UserLog {
  static let log = OSLog(subsystem: "ink.codes.feedkit", category: "user")
}

/// The `UserLibrary` manages the user‘s data, for example, feed subscriptions
/// and queue.
public final class UserLibrary: EntryQueueHost {
  fileprivate let cache: UserCaching
  fileprivate let browser: Browsing
  fileprivate let operationQueue: OperationQueue
  
  /// Makes a fresh `UserLibrary` object.
  ///
  /// - Parameters:
  ///   - cache: The cache to store user data locallly.
  ///   - browser: The browser to access feeds and entries.
  ///   - queue: A serial operation queue to execute operations in order.
  public init(cache: UserCaching, browser: Browsing, queue: OperationQueue) {
    self.cache = cache
    self.browser = browser
    self.operationQueue = queue
    
    synchronize()
  }
  
  /// The actual queue data structure. Starting off with an empty queue.
  internal var queue = Queue<Entry>()
  
  /// A synchronized list of subscribed URLs for quick in-memory access.
  fileprivate var subscriptions = Set<FeedURL>()
}

// MARK: - Subscribing

extension UserLibrary: Subscribing {
  
  public func add(
    subscriptions: [Subscription],
    addComplete: ((_ error: Error?) -> Void)? = nil) throws {
    guard !subscriptions.isEmpty else {
      DispatchQueue.global().async {
        addComplete?(nil)
      }
      return
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      do {
        try cache.add(subscriptions: subscriptions)
        self.subscriptions.formUnion(subscriptions.map { $0.url })
      } catch {
        DispatchQueue.global().async {
          addComplete?(error)
        }
        return
      }

      DispatchQueue.global().async {
        addComplete?(nil)
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: self)
      }
    }

  }
  
  public func unsubscribe(
    from urls: [FeedURL],
    unsubscribeComplete: ((_ error: Error?) -> Void)? = nil) throws {
    func done(_ error: Error? = nil) -> Void {
      DispatchQueue.global().async {
        unsubscribeComplete?(error)
      }
    }
    
    guard !urls.isEmpty else {
      return done()
    }
    
    let cache = self.cache
    
    operationQueue.addOperation {
      do {
        try cache.remove(urls: urls)
        self.subscriptions.subtract(urls)
      } catch {
        return done(error)
      }
      
      done()
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKSubscriptionsDidChange, object: self)
      }
    }
  }
  
  @discardableResult
  public func fetchFeeds(
    feedsBlock: @escaping (_ feeds: [Feed], _ feedsError: Error?) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    operationQueue.addOperation(op)
    return op
  }
  
  public func has(subscription url: FeedURL) -> Bool {
    return subscriptions.contains(url)
  }
  
  public func synchronize() {
    DispatchQueue.global(qos: .background).async {
      do {
        let subscribed = try self.cache.subscribed()
        
        let urls = Set(subscribed.map { $0.url })
        let unsubscribed = self.subscriptions.subtracting(urls)
        self.subscriptions.subtract(unsubscribed)
        self.subscriptions.formUnion(urls)
      } catch {
        os_log("failed to reload subscriptions", log: UserLog.log, type: .error,
               error as CVarArg)
      }
    }
  }

}

// MARK: - Updating

extension UserLibrary: Updating {
  
  private static func previousGUIDs(from cache: QueueCaching) throws -> [String] {
    let previous = try cache.previous()
    return previous.flatMap {
      if case .entry(let loc, _) = $0 {
        return loc.guid
      }
      return nil
    }
  }
  
  private static func locatorsForUpdating(
    from cache: QueueCaching,
    with subscriptions: [Subscription]) throws -> [EntryLocator] {
    let latest = try cache.newest()
    let urls = subscriptions.map { $0.url }
    return latest.filter { urls.contains($0.url) }
  }
  
  /// Returns entries in `entries` of `subscriptions`, which are newer than
  /// the subscription date of their containing feed.
  ///
  /// - Parameters:
  ///   - entries: The source entries to use.
  ///   - subscriptions: A set of subscriptions to compare against.
  ///
  /// - Returns: A subset of `entries` with entries newer than their according
  /// subscriptions. Entries of missing subscriptions are not included.
  static func newer(
    from entries: [Entry],
    than subscriptions: Set<Subscription>) -> [Entry] {
    // A dictionary of dates by subscription URLs for quick lookup.
    var datesByURLs = [FeedURL: Date]()
    for s in subscriptions {
      datesByURLs[s.url] = s.ts
    }

    return entries.filter {
      guard let ts = datesByURLs[$0.url] else {
        return false
      }
      return $0.updated > ts
    }
  }
  
  public func update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    os_log("updating", log: UserLog.log,  type: .info)
    
    let op = PrepareUpdateOperation(cache: cache)
    operationQueue.addOperation(op)
    op.completionBlock = {
      DispatchQueue.global().async {
        updateComplete(false, nil)
      }
    }
  }
  
  public func old_update(
    updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void) {
    os_log("updating", log: UserLog.log,  type: .info)
    
    let cache = self.cache
    
    /// Results of the locating operation: subscriptions, locators, and ignored
    /// (GUIDs); where subscriptions are used for the request and to filter
    /// the fetched entries before enqueuing them in the completion block below.
    struct LocatingResult {
      let subscriptions: [Subscription]
      let locators: [EntryLocator]
      let ignored: [String]
      
      init(cache: UserCaching) throws {
        self.subscriptions = try cache.subscribed()
        self.locators = try UserLibrary.locatorsForUpdating(
          from: cache, with: subscriptions)
        self.ignored = try UserLibrary.previousGUIDs(from: cache)
      }
    }
    
    var locatingError: Error?
    var locatingResult: LocatingResult?
    
    let locating = BlockOperation {
      do {
        locatingResult = try LocatingResult(cache: cache)
      } catch {
        locatingError = error
      }
    }
    
    func fetchEntries() {
      guard locatingError == nil,
        let locators = locatingResult?.locators,
        !locators.isEmpty,
        let ignored = locatingResult?.ignored,
        let subscriptions = locatingResult?.subscriptions else {
        return DispatchQueue.global().async {
          updateComplete(false, locatingError)
        }
      }
      
      var acc = [Entry]()
      browser.entries(locators, force: true, entriesBlock: { error, entries in
        guard error == nil else {
          os_log("faulty entries: %{public}@", log: UserLog.log, type: .error,
                 String(describing: error))
          return
        }
        
        guard !ignored.isEmpty else {
          return acc.append(contentsOf: entries)
        }
        
        acc = acc + entries.filter { !ignored.contains($0.guid) }
      }) { error in
        guard error == nil else {
          return DispatchQueue.global().async {
            updateComplete(false, error)
          }
        }
        
        let latest = UserLibrary.newer(from: acc, than: Set(subscriptions))
        
        do {
          try self.enqueue(entries: latest) { error in
            DispatchQueue.global().async {
              updateComplete(true, error)
            }
          }
        } catch {
          DispatchQueue.global().async {
            updateComplete(false, error)
          }
        }
      }
    }
    
    let q = operationQueue.underlyingQueue!
    assert(q.label == "ink.codes.feedkit.user")
    
    locating.completionBlock = {
      q.async {
        fetchEntries()
      }
    }
    
    operationQueue.addOperation(locating)
  }
  
}

// MARK: - Queueing

extension UserLibrary: Queueing {
  
  @discardableResult
  public func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    os_log("fetching", log: UserLog.log, type: .debug)
    
    let op = FetchQueueOperation(browser: browser, cache: cache, user: self)
    op.entriesBlock = entriesBlock
    op.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    
    let dep = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    dep.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: UserLog.log, type: .error, String(describing: er))
      }
    }
    dep.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: UserLog.log, type: .error, String(describing: er))
      }
    }
    
    op.addDependency(dep)
    
    operationQueue.addOperation(op)
    operationQueue.addOperation(dep)
    
    return op
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil) throws {
    guard !entries.isEmpty else {
      DispatchQueue.global().async {
        enqueueCompletionBlock?(nil)
      }
      return
    }
    
    os_log("enqueueing", log: UserLog.log, type: .debug)
    
    operationQueue.addOperation {
      do {
        try self.queue.prepend(items: entries)
        let locators = entries.map { EntryLocator(entry: $0) }
        try self.cache.add(entries: locators)
      } catch {
        DispatchQueue.global().async {
          enqueueCompletionBlock?(error)
        }
        return
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
      }
      
      DispatchQueue.global().async {
        enqueueCompletionBlock?(nil)
      }
    }
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    os_log("dequeueing", log: UserLog.log, type: .debug)
    
    operationQueue.addOperation {
      do {
        try self.queue.remove(entry)
        let guids = [entry.guid]
        try self.cache.removeQueued(guids)
      } catch {
        DispatchQueue.global().async {
          dequeueCompletionBlock?(error)
        }
        return
      }
      
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
      }
      
      DispatchQueue.global().async {
        dequeueCompletionBlock?(nil)
      }
    }
  }
  
  // TODO: Review synchronous user queue methods
  
  // MARK: Synchronous queue methods

  public func contains(entry: Entry) -> Bool {
    return queue.contains(entry)
  }
  
  public func next() -> Entry? {
    return queue.forward()
  }
  
  public func previous() -> Entry? {
    return queue.backward()
  }
  
  public var isEmpty: Bool {
    return queue.isEmpty
  }
  
}
