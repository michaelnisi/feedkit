//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public protocol SearchService {
  func suggest (term: String, cb: (NSError?, [Suggestion]?) -> Void)
  -> NSURLSessionDataTask?

  func search (term: String, cb: (NSError?, [SearchResult]?) -> Void)
  -> NSURLSessionDataTask?
}

public protocol SearchCache {
  func addSuggestions(suggestions: [Suggestion]) -> NSError?
  func suggestionsForTerm(term: String) -> (NSError?, [Suggestion]?)
}

public enum SearchCategory: Int {
  case Entries
  case Feeds
  case Store
  case Recent
}

public struct SearchResult: Equatable {
  public let author: String
  public let cat: SearchCategory
  public let feed: NSURL
}

extension SearchResult: Printable {
  public var description: String {
    return "SearchResult: \(feed) by \(author)"
  }
}

public func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
  return lhs.feed == rhs.feed
}

public struct Suggestion: Equatable {
  public let cat: SearchCategory
  public let term: String
  public var ts: NSDate? // if cached

  public func stale (ttl: NSTimeInterval) -> Bool {
    if let t = ts {
      return ttl + t.timeIntervalSinceNow < 0
    }
    return false
  }
}

extension Suggestion: Printable {
  public var description: String {
    return "Suggestion: \(term) \(ts)"
  }
}

public func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

typealias Suggestions = (NSError?, [Suggestion]?) -> Void
typealias End = (NSError?) -> Void

class SuggestOperation: NSOperation {
  let cache: SearchCache
  let cb: Suggestions
  let svc: SearchService
  let term: String
  let ttl: NSTimeInterval = 86400.0
  var error: NSError?
  var prevTerm: String?
  var task: NSURLSessionTask?

  init (
    cache: SearchCache
  , cb: Suggestions
  , prevTerm: String? = nil
  , svc: SearchService
  , term: String) {
    self.cache = cache
    self.cb = cb
    self.prevTerm = prevTerm
    self.svc = svc
    self.term = term
  }

  deinit {
    task?.cancel()
  }

  override func main () {
    if self.cancelled {
      return
    }
    let cache = self.cache
    let cb = self.cb
    let term = self.term
    var dispatched: [Suggestion]? = nil
    let (error, suggestions) = cache.suggestionsForTerm(self.term)
    if self.cancelled {
      return
    }
    self.error = error
    if let cached = suggestions {
      dispatch_async(dispatch_get_main_queue(), {
        cb(error, cached)
      })
      if let first = cached.first {
        if !first.stale(ttl) {
          return // assuming first is latest cached is fine
        }
      }
      dispatched = cached
    } else {
      if prevTerm <= term || term <= prevTerm {
        return // already checked
      }
    }
    // OK, let's make a request:
    let cancelled = self.cancelled
    let sema = dispatch_semaphore_create(0)
    var er: NSError? = nil
    task = svc.suggest(term) { error, suggestions in
      er = error
      if let sugs = suggestions {
        cache.addSuggestions(sugs) // always add
        if !cancelled {
          var acc = sugs // not dispatched already
          if let d = dispatched {
            acc = sugs.filter({
              contains(d, $0)
            })
          }
          dispatch_async(dispatch_get_main_queue(), {
            cb(error, acc)
          })
        }
      }
      dispatch_semaphore_signal(sema)
    }
    wait(sema)
    self.error = er
  }

  override func cancel () {
    task?.cancel()
    super.cancel()
  }
}

public class SearchRepository {
  let cache: SearchCache
  let queue: NSOperationQueue
  let svc: SearchService
  var prevTerm: String?

  public init (
    cache: SearchCache
  , queue: NSOperationQueue
  , svc: SearchService) {
    self.cache = cache
    self.queue = queue
    self.svc = svc
  }

  deinit {
    queue.cancelAllOperations()
  }

  public func suggest (
    term: String
  , cb: (NSError?, [Suggestion]?) -> Void // might get called multiple times
  , end: (NSError?) -> Void)
    -> NSOperation {
    let op = SuggestOperation(
      cache: cache
    , cb: cb
    , prevTerm: prevTerm
    , svc: svc
    , term: term
    )
    prevTerm = term // TODO: Move to parameters
    op.qualityOfService = .UserInitiated
    unowned let _op = op
    op.completionBlock = {
      end(_op.error)
    }
    queue.addOperation(op)
    return op
  }
}
