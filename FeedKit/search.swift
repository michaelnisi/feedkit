//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

public enum SearchItem: Equatable {
  case Sug(Suggestion)
  case Res(SearchResult)
}

public func == (lhs: SearchItem, rhs: SearchItem) -> Bool {
  var lhsRes: SearchResult?
  var lhsSug: Suggestion?
  switch lhs {
  case .Res(let res):
    lhsRes = res
  case .Sug(let sug):
    lhsSug = sug
  }
  var rhsRes: SearchResult?
  var rhsSug: Suggestion?
  switch rhs {
  case .Res(let res):
    rhsRes = res
  case .Sug(let sug):
    rhsSug = sug
  }
  if lhsRes != nil && rhsRes != nil {
    return lhsRes == rhsRes
  } else if lhsSug != nil && rhsSug != nil {
    return lhsSug == rhsSug
  }
  return false
}

public typealias SearchCallback = (NSError?, [SearchItem]) -> Void

// A lowercase, space-separated representation of the string.
public func sanitizeString (s: String) -> String {
  return trimString(s.lowercaseString, joinedByString: " ")
}

public protocol SearchService {
  func suggest (term: String, cb: (NSError?, [Suggestion]?) -> Void)
    -> NSURLSessionDataTask?

  func search (term: String, cb: (NSError?, [SearchResult]?) -> Void)
    -> NSURLSessionDataTask?
}

public protocol SearchCache {
  func setSuggestions(suggestions: [Suggestion], forTerm: String)
    -> NSError?

  func suggestionsForTerm(term: String)
    -> (NSError?, [Suggestion]?)

  func setResults(results: [SearchResult], forTerm: String)
    -> NSError?

  func resultsForTerm(term: String, orderBy: CacheResultOrder, limitTo: Int)
    -> (NSError?, [SearchResult]?)

  func resultsMatchingTitle(
    title: String
  , orderBy order: CacheResultOrder
  , limitTo limit: Int) -> (NSError?, [SearchResult]?)
}

public struct ITunesImages {
  public let img100: NSURL
  public let img30: NSURL
  public let img600: NSURL
  public let img60: NSURL
}

public struct SearchResult: Equatable {
  public let author: String
  public let feed: NSURL
  public let guid: Int
  public let images: ITunesImages?
  public let title: String
  public let ts: NSDate?
}

extension SearchResult: Printable {
  public var description: String {
    return "SearchResult: \(title) by \(author)"
  }
}

public func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
  return lhs.feed == rhs.feed
}

public struct Suggestion: Equatable {
  public let term: String
  public var ts: NSDate? // if cached
}

extension Suggestion: Printable {
  public var description: String {
    return "Suggestion: \(term) \(ts)"
  }
}

public func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

private class SearchBaseOperation: NSOperation {
  let cache: SearchCache
  let svc: SearchService
  let term: String
  var task: NSURLSessionTask?

  init (
    cache: SearchCache
  , svc: SearchService
  , term: String) {
    self.cache = cache
    self.svc = svc
    self.term = term
  }

  override func cancel () {
    task?.cancel()
    super.cancel()
  }
}

private class SearchOperation: SearchBaseOperation {
  var cb: SearchCallback?

  override func main () {
    if self.cancelled { return }
    var dispatch: SearchCallback
    if let cb = self.cb {
      dispatch = { error, items in
        dispatch_async(dispatch_get_main_queue(), {
          cb(error, items)
        })
      }
    } else {
      dispatch = nop
    }
    let cache = self.cache
    let term = self.term
    let (error, results) = cache.resultsForTerm(term, orderBy: .Desc, limitTo: 50)
    if self.cancelled { return }
    var dispatched: [SearchItem]?
    if let cached = results {
      let items = cached.map { SearchItem.Res($0) }
      dispatch(error, items)
      return
    } else if error != nil {
      dispatch(error, [])
    }
    // If we reach this point, we finally have to make an request.
    let sema = dispatch_semaphore_create(0)
    task = svc.search(term) { error, results in
      if let res = results {
        cache.setResults(res, forTerm:term)
        if res.count > 0 {
          let sugs = [Suggestion(term: term, ts: nil)]
          cache.setSuggestions(sugs, forTerm: term)
        }
        let items = res.map { SearchItem.Res($0) }
        dispatch(error, items)
      } else if error != nil {
        dispatch(error, [])
      }
      dispatch_semaphore_signal(sema)
    }
    if !wait(sema) {
      dispatch(NSError(domain: domain, code: 504, userInfo: [
        "message": "timeout occurred"
      ]), [])
    }
  }
}

private class SuggestOperation: SearchBaseOperation {
  var cb: SearchCallback?

  override func main () {
    if self.cancelled { return }
    var dispatch: SearchCallback
    if let cb = self.cb {
      dispatch = { error, items in
        dispatch_async(dispatch_get_main_queue(), {
          cb(error, items)
        })
      }
    } else {
      dispatch = nop
    }
    let cache = self.cache
    let term = self.term

    // Aggregating callbacks to make things easier for the UI.
    var items = [SearchItem]()

    let (resError, results) = cache.resultsMatchingTitle(
      term, orderBy: .Desc, limitTo: 3)
    if let res = results {
      items += res.map { SearchItem.Res($0) }
    } else if resError != nil {
      dispatch(resError, [])
    }

    let (sugError, suggestions) = cache.suggestionsForTerm(term)
    if self.cancelled { return }
    if let sugs = suggestions {
      items += sugs.map { SearchItem.Sug($0) }
      dispatch(sugError, items)
      return
    } else if sugError != nil || items.count > 0 {
      dispatch(sugError, items)
    }

    // If we reach this point, we have to make the request.
    let sema = dispatch_semaphore_create(0)
    task = svc.suggest(term) { error, suggestions in
      if let sugs = suggestions {
        cache.setSuggestions(sugs, forTerm:term)
        let csugs = sugs.count > 5 ? Array(sugs[0...4]) : sugs
        let items = csugs.map { SearchItem.Sug($0) }
        dispatch(error, items)
      } else if error != nil {
        // TODO: Fall back to cache
        dispatch(error, [])
      }
      dispatch_semaphore_signal(sema)
    }
    if !wait(sema) {
      dispatch(NSError(domain: domain, code: 504, userInfo: [
        "message": "timeout occurred"
      ]), [])
    }
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

  public func suggest (term: String, cb: SearchCallback) -> NSOperation {
    let op = SuggestOperation(cache: cache, svc: svc, term: term)
    op.cb = cb
    op.qualityOfService = .UserInitiated
    queue.addOperation(op)
    return op
  }

  public func search (term: String, cb: SearchCallback) -> NSOperation {
    let op = SearchOperation(cache: cache, svc: svc, term: term)
    op.cb = cb
    op.qualityOfService = .UserInitiated
    queue.addOperation(op)
    return op
  }
}
