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

public struct SearchResult: Equatable, Printable {
  public let author: String
  public let cat: SearchCategory
  public let feed: NSURL

  public var description: String {
    return "SearchResult: \(feed) by \(author)"
  }
}

public func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
  return lhs.feed == rhs.feed
}

public struct Suggestion: Equatable, Printable {
  let cat: SearchCategory
  let term: String

  public var description: String {
    return "Suggestion: \(term)"
  }
}

public func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

typealias Suggestions = (NSError?, [Suggestion]?) -> Void

class Suggest: NSOperation {
  let cache: SearchCache?
  let cb: Suggestions
  let svc: SearchService
  let term: String
  var error: NSError?
  var task: NSURLSessionTask?

  init (
    term: String
  , cb: Suggestions
  , svc: SearchService
  , cache: SearchCache? = nil) {
    self.term = term
    self.cb = cb
    self.svc = svc
    self.cache = cache
  }

  override func main () {
    let cancelled = self.cancelled
    if cancelled {
      return
    }
    let cb = self.cb
    let sema = dispatch_semaphore_create(0)
    task = svc.suggest(term) { error, suggestions in
      if !cancelled {
        cb(error, suggestions)
      }
      dispatch_semaphore_signal(sema)
    }
    wait(sema)
  }

  override func cancel () {
    task?.cancel()
    super.cancel()
  }
}

public class SearchRepository {
  let queue: NSOperationQueue
  let svc: SearchService
  let cache: SearchCache?

  public init (
    queue: NSOperationQueue
  , svc: SearchService
  , cache: SearchCache? = nil) {
    self.queue = queue
    self.svc = svc
    self.cache = cache
  }

  deinit {
    queue.cancelAllOperations()
  }

  public func suggest (
    term: String
  , cb: (NSError?, [Suggestion]?) -> Void // eventually called multiple times
  , end: (NSError?) -> Void)
    -> NSOperation {
    queue.cancelAllOperations() // There can be only one!
    let suggest = Suggest(term: term, cb: cb, svc: svc, cache: cache)
    suggest.qualityOfService = .UserInitiated
    suggest.completionBlock = {
      end(suggest.error)
    }
    queue.addOperation(suggest)
    return suggest
  }
}
