//
//  UserLibrary.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

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
  
  
  fileprivate var  _subscriptions = Set<FeedURL>()
  /// A synchronized list of subscribed URLs for quick in-memory access.
  fileprivate var subscriptions:Set<FeedURL> {
    get {
      return serialQueue.sync {
        return _subscriptions
      }
    }
    set {
      serialQueue.sync {
        _subscriptions = newValue
      }
    }
  }
  
  /// Internal serial queue.
  fileprivate let serialQueue = DispatchQueue(label: "ink.codes.feedkit.user.library")
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
  
  public func synchronize(completionBlock: ((Error?) -> Void)? = nil) {
    // Copy...
    var subscriptions = self.subscriptions
    
    DispatchQueue.global(qos: .background).async {
      do {
        let subscribed = try self.cache.subscribed()
        
        let urls = Set(subscribed.map { $0.url })
        let unsubscribed = subscriptions.subtracting(urls)
        subscriptions.subtract(unsubscribed)
        subscriptions.formUnion(urls)
        // ...and replace.
        self.subscriptions = subscriptions
        completionBlock?(nil)
      } catch {
        os_log("failed to reload subscriptions", log: User.log, type: .error,
               error as CVarArg)
        completionBlock?(error)
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
    os_log("updating", log: User.log,  type: .info)
    
    let prepare = PrepareUpdateOperation(cache: cache)
    
    let fetch = browser.makeEntriesOperation()
    fetch.addDependency(prepare)
    // TODO: fetch.addDependency(reach)
    
    let enqueue = EnqueueOperation(user: self, cache: cache)
    enqueue.addDependency(fetch)
    
    operationQueue.addOperation(prepare)
    operationQueue.addOperation(fetch)
    operationQueue.addOperation(enqueue)
    
    // TODO: Add proper completion block
    // ... make sure errors get propagated
    enqueue.completionBlock = {
      DispatchQueue.global().async {
        updateComplete(false, nil)
      }
    }
  }
  
}

// MARK: - Queueing

extension UserLibrary: Queueing {
  
  @discardableResult
  public func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
    ) -> Operation {
    os_log("fetching", log: User.log, type: .debug)
    
    let op = FetchQueueOperation(browser: browser, cache: cache, user: self)
    op.entriesBlock = entriesBlock
    op.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    
    let dep = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    dep.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: User.log, type: .error, String(describing: er))
      }
    }
    dep.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: User.log, type: .error, String(describing: er))
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
    let op = EnqueueOperation(user: self, cache: cache, entries: entries)
    op.enqueueCompletionBlock = enqueueCompletionBlock
    User.queue.addOperation(op)
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    os_log("dequeueing", log: User.log, type: .debug)
    
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
      
      DispatchQueue.global().async {
        dequeueCompletionBlock?(nil)
        DispatchQueue.main.async {
          NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
        }
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
