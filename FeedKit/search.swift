//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit

/// Returns a limited number of search items from searchable objects `a`, which
/// are not contained in searchable objects `b`.
/// - Parameter a: Searchable objects to reduce.
/// - Parameter b: An optional array of searchable objects to probe.
/// - Parameter max: The maximum number of returned items.
/// - Returns:  A limited number of search items from `a`, not contained in `b`.
func reduceSearchables <T: Searchable>
(a: [T], b: [T]?, max: Int, item: (T) -> SearchItem) -> [SearchItem]? {
  let count = b?.count ?? 0
  var n = max - count
  if n <= 0 {
    return nil
  }
  return a.reduce([SearchItem]()) { items, s in
    n -= 1
    guard n >= 0 else { return items }
    if let c = b {
      if !c.contains(s) {
        return items + [item(s)]
      } else {
        return items
      }
    } else {
      return items + [item(s)]
    }
  }
}

class SearchRepoOperation: SessionTaskOperation {
  let cache: SearchCaching
  let svc: FanboyService
  let term: String
  
  init(cache: SearchCaching, svc: FanboyService, term: String) {
    self.cache = cache
    self.svc = svc
    self.term = term
  }
}

final class SearchOperation: SearchRepoOperation {
  var feeds: [Feed]?
  
  override func start() {
    if cancelled {
      return finished = true
    }
    executing = true
    do {
      let cache = self.cache
      let term = self.term
      
      let cached = try cache.feedsForTerm(term)
      if cancelled {
        return finished = true
      }
      if let c = cached {
        if c.isEmpty {
          feeds = c
          return finished = true
        } else {
          if let ts = c.first!.ts {
            if !stale(ts, ttl: cache.ttl.long) {
              feeds = c
              return finished = true
            }
          }
        }
      }
      
      task = try svc.search(term) { error, payload in
        defer {
          self.finished = true
        }
        if self.cancelled {
          return
        }
        guard error == nil else {
          self.error = FeedKitError.ServiceUnavailable(error: error!)
          self.feeds = cached
          return
        }
        guard payload != nil else {
          return
        }
        do {
          let feeds = try feedsFromPayload(payload!)
          try cache.updateFeeds(feeds, forTerm: term)
          self.feeds = feeds
        } catch let er {
          self.error = er
        }
      }
    } catch let er {
      self.error = er
      return finished = true
    }
  }
}

final class SuggestOperation: SearchRepoOperation {
  var suggestions: [Suggestion]?
  
  override func start() {
    if cancelled {
      return finished = true
    }
    executing = true
    do {
      defer {
        finished = true
      }
      let cached = try cache.suggestionsForTerm(term)
      suggestions = cached
    } catch let er {
      error = er
    }
  }
}

public final class SearchRepository: Searching {
  
  let cache: SearchCaching
  let svc: FanboyService
  let queue: NSOperationQueue
  
  public init(cache: SearchCaching, queue: NSOperationQueue, svc: FanboyService) {
    self.cache = cache
    self.queue = queue
    self.svc = svc
  }
  
  public func search(
    term: String, cb: (ErrorType?, [Feed]?) -> Void) -> NSOperation {
    let op = SearchOperation(cache: cache, svc: svc, term: term)
    queue.addOperation(op)
    op.completionBlock = { [weak op] in
      cb(op?.error, op?.feeds ?? [Feed]())
    }
    return op
  }
  
  public func suggest(
    term: String, cb: (ErrorType?, [SearchItem]?) -> Void) -> NSOperation {
    let op = SuggestOperation(cache: cache, svc: svc, term: term)
    queue.addOperation(op)
    return op
  }
}

func reduceSuggestions (a: [Suggestion], b: [Suggestion]?, max: Int = 5) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { sug in
    SearchItem.Sug(sug)
  }
}

func reduceResults (a: [Feed], b: [Feed]?, max: Int = 50) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { res in
    SearchItem.Res(res)
  }
}

func reduceFeeds (a: [Feed], b: [Feed]?, max: Int = 50) -> [SearchItem]? {
  return reduceSearchables(a, b: b, max: max) { res in
    SearchItem.Fed(res)
  }
}

/// A lowercase, space-separated representation of the string.
private func sanitizeString (s: String) -> String {
  return trimString(s.lowercaseString, joinedByString: " ")
}

private func cancelledByUser (error: NSError) -> Bool {
  return error.code == -999
}
