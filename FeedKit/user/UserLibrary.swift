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
  private let cache: UserCaching
  private let browser: Browsing
  private let operationQueue: OperationQueue
  
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
    
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    precondition(queue.maxConcurrentOperationCount == 1)

    synchronize()
  }
  
  /// The actual queue data structure. Starting off with an empty queue.
  internal var queue = Queue<Entry>()
  
  /// Internal serial queue.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.user.UserLibrary-\(UUID().uuidString).serial")
  
  private var  _subscriptions = Set<FeedURL>()
  
  /// A synchronized list of subscribed URLs for quick in-memory access.
  private var subscriptions:Set<FeedURL> {
    get {
      return sQueue.sync {
        return _subscriptions
      }
    }
    set {
      sQueue.sync {
        _subscriptions = newValue
      }
    }
  }
  
  private var _queuedGUIDs =  Set<EntryGUID>()
  
  /// A synchronized list of enqueued entry GUIDs for quick in-memory access.
  private var queuedGUIDs: Set<EntryGUID> {
    get {
      return sQueue.sync {
        return _queuedGUIDs
      }
    }
    set {
      sQueue.sync {
        _queuedGUIDs = newValue
      }
    }
  }

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
    let urls = self.subscriptions
    
    operationQueue.addOperation {
      do {
        try cache.add(subscriptions: subscriptions)
        self.subscriptions = urls.union(subscriptions.map { $0.url })
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
    let subscriptions = self.subscriptions
    
    operationQueue.addOperation {
      do {
        try cache.remove(urls: urls)
        self.subscriptions = subscriptions.subtracting(urls)
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
    DispatchQueue.global().async {
      do {
        // First we are reloading the subscribed feed URLs.
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })
        
        // Reloading and unpacking the GUIDs currently in the queue is a bit
        // more elaborate.
        let queued = try self.cache.queued()
        
        let queuedGUIDs: [EntryGUID] = queued.compactMap {
          switch $0 {
          case .pinned(let loc, _, _), .temporary(let loc, _, _):
            guard let guid = loc.guid else {
              return nil
            }
            return guid
          case .previous:
            return nil
          }
        }
        
        self.queuedGUIDs = Set(queuedGUIDs)
        
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
    return previous.compactMap {
      if case .temporary(let loc, _, _) = $0 {
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
    updateComplete: ((_ newData: Bool, _ error: Error?) -> Void)?) {
    os_log("updating queue", log: User.log,  type: .info)
    
    let cache = self.cache
    let operationQueue = self.operationQueue
    let browser = self.browser

    // Synchronizing first to assure we are including the latest subscriptions.
    
    synchronize { error in
      if error != nil {
        os_log("continuing update despite error", log: User.log)
      }
      
      let preparing = PrepareUpdateOperation(cache: cache)
      let fetching = browser.entries(satisfying: preparing)
      
      // Enqueueing
      
      let enqueuing = EnqueueOperation(user: self, cache: cache)
      
      let queuedGUIDs = self.queuedGUIDs
      
      enqueuing.enqueueCompletionBlock = { enqueued, error in
        if let er = error {
          os_log("enqueue warning: %{public}@", log: User.log, er as CVarArg)
        }
        self.queuedGUIDs = queuedGUIDs.union(enqueued.map { $0.guid })
      }
      
      // Trimming
      
      let trimming = TrimQueueOperation(cache: cache)
      
      trimming.trimQueueCompletionBlock = { newData, error in
        if let er = error {
          os_log("trim error: %{public}@", log: User.log, type: .error,
                 er as CVarArg)
        }
        updateComplete?(newData, error)
      }
      
      // After configuring our individual operations, we are now composing them
      // into a dependency graph, for sequential execution.
      
      // The dependency of fetching on preparing has been satisfied by browser.
      enqueuing.addDependency(fetching)
      trimming.addDependency(enqueuing)
      
      operationQueue.addOperation(preparing)
      // Fetching is already executing.
      operationQueue.addOperation(enqueuing)
      operationQueue.addOperation(trimming)
    }
  }
  
}

// MARK: - Queueing

extension UserLibrary: Queueing {
  
  public var isForwardable: Bool {
    return queue.validIndexAfter != nil
  }
  
  public var isBackwardable: Bool {
    return queue.validIndexBefore != nil
  }
  
  @discardableResult
  public func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    os_log("fetching queue", log: User.log, type: .debug)
    
    let fetchingQueue = FetchQueueOperation(browser: browser, cache: cache, user: self)
    fetchingQueue.entriesBlock = entriesBlock
    fetchingQueue.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    
    let fetchingFeeds = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    
    fetchingFeeds.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: User.log, type: .error, String(describing: er))
      }
    }
    
    fetchingFeeds.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: User.log, type: .error, String(describing: er))
      }
    }
    
    fetchingQueue.addDependency(fetchingFeeds)
    
    operationQueue.addOperation(fetchingQueue)
    operationQueue.addOperation(fetchingFeeds)
    
    return fetchingQueue
  }
  
  public func enqueue(
    entries: [Entry],
    belonging owner: QueuedOwner,
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil) throws {
    let op = EnqueueOperation(user: self, cache: cache, entries: entries)
    op.owner = owner
    
    let queuedGUIDs = self.queuedGUIDs
    
    op.enqueueCompletionBlock = { enqueued, error in
      self.queuedGUIDs = queuedGUIDs.union(enqueued.map { $0.guid })
      enqueueCompletionBlock?(error)
    }

    operationQueue.addOperation(op)
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil) throws {
    try enqueue(entries: entries,
                belonging: .nobody,
                enqueueCompletionBlock: enqueueCompletionBlock)
  }
  
  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    os_log("dequeueing: %{public}@",
           log: User.log, type: .debug, entry.description)

    operationQueue.addOperation {
      do {
        try self.queue.remove(entry)
        let guids = [entry.guid]
        try self.cache.removeQueued(guids)
        self.queuedGUIDs.subtract(guids)
      } catch {
        dequeueCompletionBlock?(error)
        return
      }
      
      dequeueCompletionBlock?(nil)
      NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
    }
  }

  public func dequeue(
    feed url: FeedURL,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    os_log("dequeueing: %{public}@", log: User.log, type: .debug, url)

    operationQueue.addOperation {
      var guids = [EntryGUID]()
      for entry in self.queue {
        if entry.url == url {
          do {
            try self.queue.remove(entry)
            guids.append(entry.guid)
          } catch {
            os_log("removing from queue failed: %{public}@",
                   log: User.log, error as CVarArg)
            continue
          }
        }
      }

      do {
        try self.cache.removeQueued(feed: url)
      } catch {
        dequeueCompletionBlock?(error)
        return
      }

      // Keeping all these structure in sync isn’t fun.
      self.queuedGUIDs.subtract(guids)

      dequeueCompletionBlock?(nil)
      NotificationCenter.default.post(name: .FKQueueDidChange, object: nil)
    }
  }
  
  // MARK: Synchronous queue methods
  
  public func contains(entry: Entry) -> Bool {
    return queuedGUIDs.contains(entry.guid)
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
  
  public func skip(to entry: Entry) throws {
    try queue.skip(to: entry)
  }
  
}
