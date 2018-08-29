//
//  UserLibrary.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "user.library")

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
    dispatchPrecondition(condition: .onQueue(.main))
    precondition(queue.maxConcurrentOperationCount == 1)

    self.cache = cache
    self.browser = browser
    self.operationQueue = queue

    synchronize()
  }

  public weak var libraryDelegate: LibraryDelegate?

  /// Internal serial queue.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.user.UserLibrary-\(UUID().uuidString).serial")

  var _queue = Queue<Entry>()

  var queue: Queue<Entry> {
    get {
      return sQueue.sync {
        return _queue
      }
    }

    set {
      sQueue.sync {
        _queue = newValue
      }
    }
  }

  private var  _subscriptions = Set<FeedURL>()
  
  /// A synchronized list of subscribed URLs for quick in-memory access.
  private var subscriptions: Set<FeedURL> {
    get {
      return sQueue.sync {
        return _subscriptions
      }
    }
    set {
      sQueue.sync {
        let subscribed = newValue.subtracting(_subscriptions)
        let unsubscribed = _subscriptions.subtracting(newValue)

        _subscriptions = newValue

        guard !subscribed.isEmpty || !unsubscribed.isEmpty else {
          return
        }

        for s in subscribed {
          self.libraryDelegate?.library(self, didSubscribe: s)
        }

        for s in unsubscribed {
          self.libraryDelegate?.library(self, didUnsubscribe: s)
        }

        DispatchQueue.global().async {
          os_log("posting: FKSubscriptionsDidChange", log: log, type: .debug)
          NotificationCenter.default.post(
            name: .FKSubscriptionsDidChange, object: self)
        }
      }
    }
  }

  /// We are keeping an extra cache for enclosure URLs, enabling us include
  /// these URLs in our notifications, receivers might want to begin
  /// downloading.
  private var enclosureURLs = NSCache<NSString, NSString>()

  private func updateEnclosureURLs(_ entries: [Entry]) {
    for entry in entries {
      guard let url = entry.enclosure?.url else {
        continue
      }

      enclosureURLs.setObject(url as NSString, forKey: entry.guid as NSString)
    }
  }

  public weak var queueDelegate: QueueDelegate?

  private var _queuedGUIDs = Set<EntryGUID>()
  
  /// A synchronized list of enqueued entry GUIDs for quick in-memory access.
  private var queuedGUIDs: Set<EntryGUID> {
    get {
      return sQueue.sync {
        return _queuedGUIDs
      }
    }

    set {
      sQueue.sync {
        let enqueued = newValue.subtracting(_queuedGUIDs)
        let dequeued = _queuedGUIDs.subtracting(newValue)

        _queuedGUIDs = newValue

        guard !enqueued.isEmpty || !dequeued.isEmpty else {
          return
        }

        func post(_ guid: String, _ n: Notification.Name) {
          var i = ["entryGUID": guid]
          if let url = enclosureURLs.object(forKey: guid as NSString) {
            i["enclosureURL"] = url as String
          } 

          DispatchQueue.global().async {
            os_log("posting: ( %@, %@ )", log: log, type: .debug, n.rawValue, i)
            NotificationCenter.default.post(name: n, object: self, userInfo: i)
          }
        }

        for guid in dequeued {
          self.queueDelegate?.queue(self, didDequeue: guid)
          post(guid, .FKQueueDidDequeue)
        }

        for guid in enqueued {
          self.queueDelegate?.queue(self, didEnqueue: guid)
          post(guid, .FKQueueDidEnqueue)
        }

        self.queueDelegate?.queue(self, didChangeEnqueued: _queuedGUIDs)

        DispatchQueue.global().async {
          os_log("posting: FKQueueDidChange", log: log, type: .debug)
          NotificationCenter.default.post(name: .FKQueueDidChange, object: self)
        }
      }
    }
  }

}

// MARK: - Subscribing

extension UserLibrary: Subscribing {
  
  public func add(
    subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)? = nil
  ) {
    guard !subscriptions.isEmpty else {
      return DispatchQueue.global().async {
        completionBlock?(nil)
      }
    }

    operationQueue.addOperation {
      do {
        try self.cache.add(subscriptions: subscriptions)
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })
      } catch {
        completionBlock?(error)
        return
      }
      
      completionBlock?(nil)
    }
    
  }

  public func subscribe(_ feed: Feed) {
    let s = Subscription(feed: feed)

    add(subscriptions: [s]) { error in
      guard error == nil else {
        return os_log(
          "not subscribed: %{public}@",
          log: log, type: .error, error! as CVarArg
        )
      }

      os_log("subscribed", log: log, type: .debug)

      self.browser.latestEntry(feed.url) { entry, error in
        guard error == nil, let e = entry else {
          return os_log("latest entry not found", log: log)
        }

        self.enqueue(entries: [e], belonging: .nobody) { error in
          guard error == nil else {
            return os_log(
              "not enqueued: %{public}@",
              log: log, type: .error, error! as CVarArg
            )
          }

          os_log("enqueued", log: log, type: .debug)
        }
      }
    }
  }

  public func unsubscribe(
    _ urls: [FeedURL],
    dequeueing: Bool = true,
    unsubscribeComplete: ((_ error: Error?) -> Void)? = nil) {
    guard !urls.isEmpty else {
      return DispatchQueue.global().async {
        unsubscribeComplete?(nil)
      }
    }
    
    operationQueue.addOperation {
      let oldValue = self.subscriptions

      do {
        try self.cache.remove(urls: urls)
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })
      } catch {
        unsubscribeComplete?(error)
        return
      }

      guard dequeueing else {
        unsubscribeComplete?(nil)
        return
      }

      let unsubscribed = oldValue.subtracting(self.subscriptions)
      let children = self.queue.filter { unsubscribed.contains($0.url) }

      do {
        try self.dequeue(entries: children)
      } catch {
        unsubscribeComplete?(error)
        return
      }
      
      unsubscribeComplete?(nil)
    }
  }

  public func unsubscribe(_ url: FeedURL) {
    self.unsubscribe([url])
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
    operationQueue.addOperation {
      os_log("synchronizing", log: log, type: .debug)

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
        os_log("failed to reload subscriptions", log: log, type: .error,
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
    os_log("updating queue", log: log,  type: .info)
    
    let cache = self.cache
    let operationQueue = self.operationQueue
    let browser = self.browser

    // Synchronizing first to assure we are including the latest subscriptions.
    
    synchronize { error in
      if error != nil {
        os_log("continuing update despite error", log: log)
      }
      
      let preparing = PrepareUpdateOperation(cache: cache)
      let fetching = browser.entries(satisfying: preparing)
      
      // Enqueueing
      
      let enqueuing = EnqueueOperation(user: self, cache: cache)
      
      let queuedGUIDs = self.queuedGUIDs
      
      enqueuing.enqueueCompletionBlock = { enqueued, error in
        if let er = error {
          os_log("enqueue warning: %{public}@", log: log, er as CVarArg)
        }

        self.updateEnclosureURLs(enqueued)
        self.queuedGUIDs = queuedGUIDs.union(enqueued.map { $0.guid })
      }
      
      // Trimming
      
      let trimming = TrimQueueOperation(cache: cache)
      
      trimming.trimQueueCompletionBlock = { newData, error in
        if let er = error {
          os_log("trim error: %{public}@", log: log, type: .error,
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
    os_log("fetching queue", log: log, type: .debug)
    
    let fetchingQueue = FetchQueueOperation(browser: browser, cache: cache, user: self)
    fetchingQueue.entriesBlock = entriesBlock
    fetchingQueue.fetchQueueCompletionBlock = fetchQueueCompletionBlock
    
    let fetchingFeeds = FetchSubscribedFeedsOperation(browser: browser, cache: cache)
    
    fetchingFeeds.feedsBlock = { feeds, error in
      if let er = error {
        os_log("problems fetching subscribed feeds: %{public}@",
               log: log, type: .error, String(describing: er))
      }
    }
    
    fetchingFeeds.feedsCompletionBlock = { error in
      if let er = error {
        os_log("failed to integrate metadata %{public}@",
               log: log, type: .error, String(describing: er))
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
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil
  ) {
    let op = EnqueueOperation(user: self, cache: cache, entries: entries)
    op.owner = owner
    
    let queuedGUIDs = self.queuedGUIDs
    
    op.enqueueCompletionBlock = { enqueued, error in
      self.updateEnclosureURLs(enqueued)
      self.queuedGUIDs = queuedGUIDs.union(enqueued.map { $0.guid })

      enqueueCompletionBlock?(error)
    }

    operationQueue.addOperation(op)
  }
  
  public func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)? = nil) {
    enqueue(entries: entries,
            belonging: .nobody,
            enqueueCompletionBlock: enqueueCompletionBlock)
  }

  /// Dequeues `entries`. Trying to dequeue a single entry that’s not enqueued
  /// throws. Lots of ephemeral state to update here, after writing to the
  /// database.
  private func dequeue(entries: [Entry]) throws {
    os_log("dequeueing: %{public}@", log: log, type: .debug, entries)
    dispatchPrecondition(condition: .notOnQueue(.main))

    let guids = entries.map { $0.guid }
    try cache.removeQueued(guids)

    let queued = try cache.queued().compactMap { $0.entryLocator.guid }

    for entry in entries {
      do {
        try queue.remove(entry)
      } catch {
        os_log("not removed: %{public}@", log: log, error as CVarArg)
        guard entries.count > 1 else {
          throw error
        }
        continue
      }

      // Purging URLs.

      guard let url = entry.enclosure?.url else {
        continue
      }
      enclosureURLs.removeObject(forKey: url as NSString)
    }

    queuedGUIDs = Set(queued)
  }

  public func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    operationQueue.addOperation {
      let entries = [entry]
      do {
        try self.dequeue(entries: entries)
      } catch {
        dequeueCompletionBlock?(error)
        return
      }
      
      dequeueCompletionBlock?(nil)
    }
  }

  public func dequeue(
    feed url: FeedURL,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?) {
    operationQueue.addOperation {
      let children = self.queue.filter { $0.url == url }

      do {
        try self.dequeue(entries: children)
      } catch {
        dequeueCompletionBlock?(error)
        return
      }

      dequeueCompletionBlock?(nil)
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
