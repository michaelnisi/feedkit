//
//  search.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Ola

// Return (optional but maximal `max`) search items from searchable
// objects `a` which are not contained in searchable objects `b`
// where `b` is optional.
func reduceSearchables <T: Searchable>
(a: [T], b: [T]?, max: Int, item: (T) -> SearchItem) -> [SearchItem]? {
  let count = b?.count ?? 0
  var n = max - count
  if n <= 0 {
    return nil
  }
  return reduce(a, [SearchItem]()) { items, s in
    if n-- > 0 {
      if let c = b {
        if !contains(c, s) {
          return items + [item(s)]
        } else {
          return items
        }
      } else {
        return items + [item(s)]
      }
    } else {
      return items
    }
  }
}

func reduceSuggestions (a: [Suggestion], b: [Suggestion]?, max: Int = 5)
-> [SearchItem]? {
  return reduceSearchables(a, b, max) { sug in
    SearchItem.Sug(sug)
  }
}

func reduceResults (a: [SearchResult], b: [SearchResult]?, max: Int = 50)
-> [SearchItem]? {
  return reduceSearchables(a, b, max) { res in
    SearchItem.Res(res)
  }
}

public enum SearchItem: Equatable {
  case Sug(Suggestion)
  case Res(SearchResult)
  var ts: NSDate? {
    switch self {
    case .Res(let it): return it.ts
    case .Sug(let it): return it.ts
    }
  }
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
  var baseURL: NSURL { get }
  var conf: NSURLSessionConfiguration { get set }

  func suggest (term: String, cb: (NSError?, [Suggestion]?) -> Void)
    -> NSURLSessionDataTask?

  func search (term: String, cb: (NSError?, [SearchResult]?) -> Void)
    -> NSURLSessionDataTask?
}

public protocol SearchCache {
  var ttl: NSTimeInterval { get }
  func setSuggestions(suggestions: [Suggestion], forTerm: String)
    -> NSError?
  func suggestionsForTerm(term: String)
    -> (NSError?, [Suggestion]?)

  func setResults(results: [SearchResult], forTerm: String) -> NSError?
  func resultsForTerm(term: String) -> (NSError?, [SearchResult]?)
  func resultsMatchingTerm(term: String) -> (NSError?, [SearchResult]?)
}

public struct ITunesImages {
  public let img100: String
  public let img30: String
  public let img600: String
  public let img60: String
}


// A marker protocol for search items.
protocol Searchable: Equatable {}

public struct SearchResult: Searchable {
  public let author: String
  public let feed: String
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

public struct Suggestion: Searchable {
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

private func cancelledByUser (error: NSError) -> Bool {
  return error.code == -999
}

private func reachable (status: OlaStatus, cell:  Bool) -> Bool {
  return status == .Reachable || cell && status == .Cellular
}

private class SearchBaseOperation: NSOperation {
  struct Constants {
    static let TIME_MAX = 10.0
  }

  let cache: SearchCache
  let svc: SearchService
  let term: String

  init (
    cache: SearchCache
  , svc: SearchService
  , term: String) {
    self.cache = cache
    self.svc = svc
    self.term = sanitizeString(term)
  }

  lazy var dispatched: [SearchItem] = {
    return []
  }()

  var dispatch: SearchCallback = nop

  // TODO: Rename to callback
  var cb: SearchCallback? {
    didSet {
      if let callback = cb {
        self.dispatch = { error, items in
          let undispatched = items.filter {
            !contains(self.dispatched, $0)
          }
          dispatch_async(dispatch_get_main_queue(), {
            callback(error, undispatched)
          })
          self.dispatched += undispatched
        }
      } else {
        self.dispatch = nop
      }
    }
  }

  var sema: dispatch_semaphore_t?

  func lock () {
    if !cancelled && sema == nil {
      sema = dispatch_semaphore_create(0)
      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER)
    }
  }

  func unlock () {
    if let sema = self.sema {
      dispatch_semaphore_signal(sema)
    }
    if let timer = self.timer {
      dispatch_source_cancel(timer)
    }
  }

  func request () {
    assert(false, "not implemented")
  }

  weak var task: NSURLSessionTask?

  override func cancel () {
    task?.cancel()
    unlock()
    super.cancel()
  }

  var indicationTimer: dispatch_source_t?

  // Show and hide network activity indicator.
  func indicate (visible: Bool) {
    let queue = dispatch_get_main_queue()
    let app = UIApplication.sharedApplication()
    if let timer = indicationTimer {
      dispatch_source_cancel(timer)
    }
    if visible {
      indicationTimer = createTimer(queue, 0.1) { [weak self] in
        app.networkActivityIndicatorVisible = visible
      }
    } else {
      dispatch_async(queue) { [weak self] in
        app.networkActivityIndicatorVisible = visible
      }
    }
  }

  // MARK: Reachability

  lazy var queue: dispatch_queue_t = {
    return dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
  }()

  var allowsCellularAccess: Bool { get {
    return self.svc.conf.allowsCellularAccess }
  }

  func reachable (status: OlaStatus) -> Bool {
    return status == .Reachable || (status == .Cellular
      && allowsCellularAccess)
  }

  lazy var ola: Ola? = { [unowned self] in
    Ola(host: self.svc.baseURL.host, queue: self.queue)
  }()

  var time = 1.0 // Retry after 1.0, 3.0, and 9.0 seconds.
  var timer: dispatch_source_t!

  func check () {
    if let ola = self.ola {
      if reachable(ola.reach()) {
        if let timer = self.timer {
          dispatch_source_cancel(timer)
        }
        self.timer = createTimer(queue, time) { [unowned self] in
          self.request()
          dispatch_source_cancel(self.timer)
        }
        time *= 3
      } else {
        ola.reachWithCallback() { [unowned self] status in
          if self.cancelled == false
          && self.reachable(status) == true {
            self.request()
          }
        }
      }
    }
  }
}

private class SearchOperation: SearchBaseOperation {
  var cached: [SearchResult]?

  override func request () {
    if cancelled {
      return
    }
    task?.cancel()
    let term = self.term
    indicate(true)
    task = svc.search(term) { [weak self] error, results in
      self?.indicate(false)
      if let er = error {
        if let res = results {
          self?.cache.setResults(res, forTerm: term)
        }
        if self?.cancelled == true || cancelledByUser(er) {
          return
        }
        if self?.time < Constants.TIME_MAX {
          self?.check()
        } else {
          self?.unlock()
        }
      } else if let res = results {
        self?.cache.setResults(res, forTerm:term)
        if self?.cancelled == true {
          return
        }
        if let items = reduceResults(res, self?.cached, max: 50) {
          if items.count > 0 {
            self?.dispatch(nil, items)
          }
        }
        self?.unlock()
      }
    }
  }

  override func main () {
    if cancelled { return }

    let cache = self.cache
    let dispatch = self.dispatch
    let term = self.term

    let (error, results) = cache.resultsForTerm(term)
    if cancelled { return }
    var items = [SearchItem]()
    if let er = error {
      dispatch(er, items)
    } else if let res = results {
      if res.count == 0 {
        return dispatch(nil, items)
      }
      items += res.map {
        // If one is stale, we will do the request.
        if self.cached == nil {
          if stale($0.ts!, cache.ttl) {
            self.cached = res
          }
        }
        return SearchItem.Res($0)
      }
      dispatch(nil, items)
      if self.cached == nil {
        return
      }
    } else {
      dispatch(nil, items)
    }

    // OK then.
    request()
    lock()
  }
}

private class SuggestOperation: SearchBaseOperation {
  var cached: [Suggestion]?

  override func request () {
    if cancelled {
      return
    }
    task?.cancel()
    let term = self.term
    indicate(true)
    task = svc.suggest(term) { [weak self] error, suggestions in
      self?.indicate(false)
      if let er = error {
        if let sugs = suggestions {
          self?.cache.setSuggestions(sugs, forTerm:term)
        }
        if self?.cancelled == true || cancelledByUser(er) {
          return
        }
        if self?.time < Constants.TIME_MAX {
          self?.check()
        } else {
          self?.unlock()
        }
      } else if let sugs = suggestions {
        self?.cache.setSuggestions(sugs, forTerm:term)
        if self?.cancelled == true {
          return
        }
        if let items = reduceSuggestions(sugs, self?.cached) {
          if items.count > 0 {
            self?.dispatch(nil, items)
          }
        }
        self?.unlock()
      }
    }
  }

  override func main () {
    if cancelled { return }

    let cache = self.cache
    let dispatch = self.dispatch
    let term = self.term

    let (resError, results) = cache.resultsMatchingTerm(term)
    if cancelled { return }
    var items = [SearchItem]()
    if let er = resError {
      dispatch(er, [])
    } else if let res = results {
      // Aggregating items to minimize number of callbacks.
      items += res.map { SearchItem.Res($0) }
    }

    let (sugError, cachedSuggestions) = cache.suggestionsForTerm(term)
    if cancelled { return }
    if let er = sugError {
      dispatch(er, items)
    } else if let sugs = cachedSuggestions {
      if sugs.count == 0 {
        return dispatch(nil, items)
      }
      items += sugs.map {
        // If one is stale, we will do the request.
        if self.cached == nil {
          if stale($0.ts!, cache.ttl) {
            self.cached = sugs
          }
        }
        return SearchItem.Sug($0)
      }
      dispatch(nil, items)
      if self.cached == nil {
        return
      }
    } else {
      dispatch(nil, items)
    }

    // OK then.
    request()
    lock()
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
