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
public final class UserLibrary {
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

  /// Internal serial queue.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.user.UserLibrary-\(UUID().uuidString).serial")

  private var  _subscriptions = Set<FeedURL>()
  
  /// The currently subscribed URLs. Reload with `synchronize()`. Fires a
  /// `.FKSubscriptionsDidChange` notification.
  private var subscriptions: Set<FeedURL> {
    get {
      return sQueue.sync {
        return _subscriptions
      }
    }
    set {
      sQueue.sync {
        guard _subscriptions != newValue else {
          return
        }

        _subscriptions = newValue

        DispatchQueue.main.async {
          NotificationCenter.default.post(
            name: .FKSubscriptionsDidChange, object: self)
        }
      }
    }
  }

  private var _guids = Set<EntryGUID>()

  /// GUIDs of entries currently in the queue. Reload with `synchronize()`.
  private var guids: Set<EntryGUID> {
    get {
      return sQueue.sync {
        return _guids
      }
    }

    set {
      sQueue.sync {
        _guids = newValue
      }
    }
  }

  private var _queue = Queue<Entry>()

}

// MARK: - EntryQueueHost

extension UserLibrary: EntryQueueHost {

  /// The actual queue of entries.
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
        let subscribed = try self.cache.subscribed()
        self.subscriptions = Set(subscribed.map { $0.url })

        let queued = try self.cache.queued()
        self.guids = Set(queued.compactMap { $0.entryLocator.guid })

        completionBlock?(nil)
      } catch {
        os_log("failed to synchronize: %@",
               log: log, type: .error, error as CVarArg)

        completionBlock?(error)
      }
    }
  }
  
}

// MARK: - Queue Notifications

extension UserLibrary {

  private static func makeUserInfo(entry: Entry) -> [String: Any] {
    return [
      "entryGUID": entry.guid,
      "enclosureURL": entry.enclosure?.url as Any
    ]
  }

  private func queueChanged(enqueued: Set<Entry>, deqeueud: Set<Entry>) {
    for e in enqueued {
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKQueueDidEnqueue,
          object: self,
          userInfo: UserLibrary.makeUserInfo(entry: e)
        )
      }
    }

    for e in deqeueud {
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .FKQueueDidDequeue,
          object: self,
          userInfo: UserLibrary.makeUserInfo(entry: e)
        )
      }
    }

    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .FKQueueDidChange, object: self)
    }

    guids = Set(queue.map { $0.guid} )
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

      enqueuing.enqueueCompletionBlock = { enqueued, error in
        if let er = error {
          os_log("enqueue warning: %{public}@", log: log, er as CVarArg)
        }

        self.queueChanged(enqueued: Set(enqueued), deqeueud: Set())
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

    op.enqueueCompletionBlock = { enqueued, error in
      self.queueChanged(enqueued: Set(enqueued), deqeueud: Set())

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

    let old = Set(queue)

    let guids = entries.map { $0.guid }
    try cache.removeQueued(guids)

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
    }

    let dequeued = old.subtracting(queue)

    queueChanged(enqueued: [], deqeueud: dequeued)
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
  
  public func contains(entry: Entry) -> Bool {
    guard !queue.isEmpty else {
      return guids.contains(entry.guid)
    }

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
  
  public func skip(to entry: Entry) throws {
    try queue.skip(to: entry)
  }
  
}
