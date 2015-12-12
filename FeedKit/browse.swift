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

func feedsFromCache(cache: FeedCaching, withURLs urls: [String]) throws -> ([Feed], [Feed], [String]?) {
  guard let items = try cache.feedsWithURLs(urls) else {
    return ([], [], urls)
  }
  return subtractItems(items, fromURLs: urls, withTTL: cache.ttl.long)
}

func entriesFromCache(cache: FeedCaching, withIntervals intervals: [EntryInterval]) throws -> ([Entry], [Entry], [String]?) {
  let urls = intervals.map { $0.url }
  guard let items = try cache.entriesOfIntervals(intervals) else {
    return ([], [], urls)
  }
  return subtractItems(items, fromURLs: urls, withTTL: cache.ttl.short)
}

// TODO: Make this operation concurrent

class FeedRepoOperation: NSOperation {
  let cache: FeedCaching
  let svc: MangerService

  var task: NSURLSessionTask?
  var error: ErrorType?

  init(cache: FeedCaching, svc: MangerService) {
    self.cache = cache
    self.svc = svc
  }

  var sema: dispatch_semaphore_t?

  func lock() {
    if !cancelled && sema == nil {
      sema = dispatch_semaphore_create(0)
      dispatch_semaphore_wait(sema!, DISPATCH_TIME_FOREVER)
    }
  }

  func unlock() {
    if let sema = self.sema {
      dispatch_semaphore_signal(sema)
    }
  }

  override func cancel() {
    error = FeedKitError.CancelledByUser
    task?.cancel()
    unlock()
    super.cancel()
  }
}

extension EntryInterval: MangerQuery {}

class EntriesOperation: FeedRepoOperation {
  var entries: [Entry]?
  let intervals: [EntryInterval]

  init (cache: FeedCaching, svc: MangerService, intervals: [EntryInterval]) {
    self.intervals = intervals
    super.init(cache: cache, svc: svc)
  }

  override func main () {
    if cancelled {
      return
    }
    do {
      let cache = self.cache
      let svc = self.svc
      let (c, s, required) = try entriesFromCache(cache, withIntervals: intervals)
      if cancelled {
        entries = [Entry]()
        return
      }
      guard required != nil else {
        return entries = c
      }
      
      // TODO: Remove when https://openradar.appspot.com/23499056 got fixed
      let queries: [MangerQuery] = intervals.map { $0 }
      
      task = try svc.entries(queries) { error, payload in
        defer {
          self.unlock()
        }
        if self.cancelled {
          return
        }
        guard error == nil else {
          self.error = FeedKitError.ServiceUnavailable(
            error: error!,
            urls: required!
          )
          self.entries = c + s
          return
        }
        guard payload != nil else {
          return
        }
        do {
          let entries = try entriesFromPayload(payload!)
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
    lock()
  }
}

func subtractStrings(a: [String], fromStrings b:[String]) -> [String] {
  let setA = Set(a)
  let setB = Set(b)
  let diff = setB.subtract(setA)
  return Array(diff)
}

class FeedsOperation: FeedRepoOperation {
  var feeds: [Feed]?
  let urls: [String]

  init (cache: FeedCaching, svc: MangerService, urls: [String]) {
    self.urls = urls
    super.init(cache: cache, svc: svc)
  }

  override func main () {
    if cancelled {
      return
    }
    do {
      let cache = self.cache
      let (cachedFeeds, staleFeeds, urlsToRequest) = try feedsFromCache(cache, withURLs: urls)
      if cancelled {
        return
      }
      guard urlsToRequest != nil else {
        return feeds = cachedFeeds
      }
      
      let queries: [MangerQuery] = urlsToRequest!.map { EntryInterval(url: $0) }
      
      task = try svc.feeds(queries) { error, payload in
        defer {
          self.unlock()
        }
        if self.cancelled {
          return
        }
        guard error == nil else {
          self.error = FeedKitError.ServiceUnavailable(
            error: error!,
            urls: urlsToRequest!
          )
          self.feeds = cachedFeeds + staleFeeds
          return
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
    lock()
  }
}

public class FeedRepository: Browsing {
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
    op.completionBlock = { [unowned op] in
      cb(op.error, op.feeds ?? [Feed]())
    }
    return op
  }

  // TODO: Make entries method thread safe
  
  public func entries (intervals: [EntryInterval], cb: (ErrorType?, [Entry]) -> Void) -> NSOperation {
    let urls = intervals.map { $0.url }
    let dep = FeedsOperation(cache: cache, svc: svc, urls: urls)
    var error: ErrorType?
    dep.completionBlock = { [unowned dep] in
      error = dep.error
    }
    let op = EntriesOperation(cache: cache, svc: svc, intervals: intervals)
    op.completionBlock = { [unowned op] in
      cb(op.error ?? error, op.entries ?? [Entry]())
    }
    op.addDependency(dep)
    queue.addOperation(dep)
    queue.addOperation(op)
    return op
  }
}
