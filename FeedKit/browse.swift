//
//  browse.swift
//  FeedKit
//
//  Created by Michael Nisi on 11.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit

func subtractItems<T: Cachable>
  (items: [T], fromURLs urls: [String], withTTL ttl: NSTimeInterval)
  -> ([T], [T], [String]?) {
    var cachedItems = [T]()
    var staleItems = [T]()
    let cachedURLs = items.reduce([String]()) { acc, item in
      if !stale(item.ts!, ttl: ttl) {
        cachedItems.append(item)
        return acc + [item.url]
      } else {
        staleItems.append(item)
        return acc
      }
    }
    let notCachedURLs = subtractStrings(cachedURLs, fromStrings: urls)
    if notCachedURLs.isEmpty {
      return (cachedItems, [], nil)
    } else {
      return (cachedItems, staleItems, notCachedURLs)
    }
}

func feedsFromCache(
  cache: FeedCaching,
  withURLs urls: [String]) throws -> ([Feed], [Feed], [String]?) {
    
  guard let items = try cache.feedsWithURLs(urls) else {
    return ([], [], urls)
  }
  return subtractItems(items, fromURLs: urls, withTTL: cache.ttl.long)
}

func entriesFromCache(
  cache: FeedCaching,
  withIntervals intvls: [EntryInterval]) throws -> ([Entry], [Entry], [String]?) {
    
  let urls = intvls.map { $0.url }
  guard let items = try cache.entriesOfIntervals(intvls) else {
    return ([], [], urls)
  }
  return subtractItems(items, fromURLs: urls, withTTL: cache.ttl.short)
}

class FeedRepoOperation: NSOperation {
  let cache: FeedCaching
  let svc: MangerService

  var task: NSURLSessionTask?
  var error: ErrorType?
  
  private var _executing: Bool = false
  
  override var executing: Bool {
    get { return _executing }
    set {
      guard newValue != _executing else {
        return
      }
      willChangeValueForKey("isExecuting")
      _executing = newValue
      didChangeValueForKey("isExecuting")
    }
  }
  
  private var _finished: Bool = false
  
  override var finished: Bool {
    get { return _finished }
    set {
      guard newValue != _finished else {
        return
      }
      willChangeValueForKey("isFinished")
      _finished = newValue
      didChangeValueForKey("isFinished")
    }
  }

  init(cache: FeedCaching, svc: MangerService) {
    self.cache = cache
    self.svc = svc
  }
  
  override func cancel() {
    error = FeedKitError.CancelledByUser
    task?.cancel()
    super.cancel()
  }
}

extension EntryInterval: MangerQuery {}

final class EntriesOperation: FeedRepoOperation {
  var entries: [Entry]?
  let intervals: [EntryInterval]
  
  init (cache: FeedCaching, svc: MangerService, intervals: [EntryInterval]) {
    self.intervals = intervals
    super.init(cache: cache, svc: svc)
  }

  override func start() {
    if cancelled {
      return finished = true
    }
    executing = true
    do {
      // TODO: Move functionalities to separate methods with clear APIs
      
      let cache = self.cache
      let svc = self.svc
      let (c, s, required) = try entriesFromCache(cache, withIntervals: intervals)
      if cancelled {
        entries = [Entry]()
        return finished = true
      }
      guard required != nil else {
        entries = c
        return finished = true
      }
      
      // TODO: Only request required URLs
      
      let queries: [MangerQuery] = intervals.map { $0 }
      
      task = try svc.entries(queries) { error, payload in
        defer {
          self.finished = true
        }
        if self.cancelled {
          return
        }
        guard error == nil else {
          self.error = FeedKitError.ServiceUnavailable(
            error: error!,
            urls: required!
          )
          return self.entries = c + s
        }
        guard payload != nil else {
          return
        }
        do {
          let entries = try entriesFromPayload(payload!)
          
          // TODO: Merge with cached entries
          
          self.entries = entries
          try cache.updateEntries(entries)
        } catch FeedKitError.FeedNotCached {
          fatalError("feedkit: cannot update entries of uncached feeds")
        } catch let er {
          self.error = er
        }
      }
    } catch let er {
      return self.error = er
    }
  }
}

func subtractStrings(a: [String], fromStrings b:[String]) -> [String] {
  let setA = Set(a)
  let setB = Set(b)
  let diff = setB.subtract(setA)
  return Array(diff)
}

final class FeedsOperation: FeedRepoOperation {
  var feeds: [Feed]?
  let urls: [String]

  init (cache: FeedCaching, svc: MangerService, urls: [String]) {
    self.urls = urls
    super.init(cache: cache, svc: svc)
  }

  override func start() {
    if cancelled {
      return finished = true
    }
    executing = true
    do {
      // TODO: Move functionalities to separate methods with clear APIs
      
      let cache = self.cache
      let (cachedFeeds, staleFeeds, urlsToRequest) = try feedsFromCache(cache, withURLs: urls)
      if cancelled {
        return finished = true
      }
      guard urlsToRequest != nil else {
        feeds = cachedFeeds
        return finished = true
      }
      
      let queries: [MangerQuery] = urlsToRequest!.map { EntryInterval(url: $0) }
      
      task = try svc.feeds(queries) { error, payload in
        defer {
          self.finished = true
        }
        if self.cancelled {
          return
        }
        guard error == nil else {
          self.error = FeedKitError.ServiceUnavailable(
            error: error!,
            urls: urlsToRequest!
          )
          return self.feeds = cachedFeeds + staleFeeds
        }
        guard payload != nil else {
          return
        }
        do {
          let feeds = try feedsFromPayload(payload!)
          try cache.updateFeeds(feeds)
          self.feeds = feeds + cachedFeeds
        } catch let er {
          self.error = er
        }
      }
    } catch let er {
      return self.error = er
    }
  }
}

public final class FeedRepository: Browsing {
  let cache: FeedCaching
  let svc: MangerService
  let queue: NSOperationQueue
  
  let feedQueue = NSOperationQueue()

  public init(cache: FeedCaching, svc: MangerService, queue: NSOperationQueue) {
    self.cache = cache
    self.svc = svc
    self.queue = queue
  }

  deinit {
    queue.cancelAllOperations()
  }

  public func feeds (urls: [String], cb: (ErrorType?, [Feed]) -> Void) -> NSOperation {
    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)
    queue.addOperation(op)
    op.completionBlock = { [weak op] in
      cb(op?.error, op?.feeds ?? [Feed]())
    }
    return op
  }
  
  public func entries (intervals: [EntryInterval], cb: (ErrorType?, [Entry]) -> Void) -> NSOperation {
    let urls = intervals.map { $0.url }
    let dep = FeedsOperation(cache: cache, svc: svc, urls: urls)
    var error: ErrorType?
    dep.completionBlock = { [weak dep] in
      error = dep?.error
    }
    let op = EntriesOperation(cache: cache, svc: svc, intervals: intervals)
    op.completionBlock = { [weak op] in
      cb(op?.error ?? error, op?.entries ?? [Entry]())
    }
    op.addDependency(dep)
    queue.addOperation(dep)
    queue.addOperation(op)
    return op
  }
}
