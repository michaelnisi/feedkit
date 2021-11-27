//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2017 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import os.log
import Ola

private let log = OSLog.disabled

// An operation to get search suggestions.
final class SuggestOperation: SearchRepoOperation {
  
  var perFindGroupBlock: ((Error?, [Find]) -> Void)?
  
  var suggestCompletionBlock: ((Error?) -> Void)?
  
  /// A set of finds that have been dispatched by this operation.
  var dispatched = Set<Find>()
  
  /// Stale suggestions from the cache.
  var stock: [Suggestion]?
  
  /// This is `true` if a remote request is required, the default.
  var requestRequired: Bool = true
  
  fileprivate func done(_ error: Error? = nil) {
    let er = isCancelled ?  FeedKitError.cancelledByUser : error
    suggestCompletionBlock?(er)
    
    perFindGroupBlock = nil
    suggestCompletionBlock = nil
    task = nil
    
    isFinished = true
  }
  
  private func dispatch(_ error: FeedKitError?, finds: [Find]) {
    guard !isCancelled, let cb = perFindGroupBlock else {
      return
    }
    cb(error as Error?, finds.filter { !dispatched.contains($0) })
    dispatched.formUnion(finds)
  }
  
  static func suggestions(from terms: [String]) -> [Suggestion] {
    return terms.map { Suggestion(term: $0, ts: nil) }
  }

  fileprivate func request() throws {
    guard isAvailable else {
      guard let suggestions = stock, !suggestions.isEmpty else {
        os_log("aborting: service unavailable", log: log)
        return done(FeedKitError.serviceUnavailable(nil))
      }
      os_log("falling back on stock: service unavailable", log: log)
      let finds = suggestions.map { Find.suggestedTerm($0) }
      dispatch(nil, finds: finds)
      return done(FeedKitError.serviceUnavailable(nil))
    }
    
    os_log("requesting: %{public}@", log: log, type: .info, term)
    
    task = try svc.suggestions(matching: term, limit: 10) {
      [unowned self] payload, error in
      var er: Error?
      
      defer {
        self.done(er)
      }
      
      guard !self.isCancelled else {
        return
      }
      
      guard error == nil else {
        er = FeedKitError.serviceUnavailable(error!)
        
        os_log("checking stock: service unavailable: %{public}@",
               log: log, type: .info, er! as CVarArg)
        
        if let suggestions = self.stock {
          guard !suggestions.isEmpty else {
            os_log("empty stock", log: log, type: .info)
            return
          }
          let finds = suggestions.map { Find.suggestedTerm($0) }
          self.dispatch(nil, finds: finds)
        } else {
          os_log("no stock", log: log, type: .info)
        }
        return
      }
      
      guard payload != nil else {
        return
      }
      
      do {
        let suggestions = SuggestOperation.suggestions(from: payload!)
        try self.cache.update(suggestions: suggestions, for: self.term)
        guard !suggestions.isEmpty else { return }
        let finds = suggestions.reduce([Find]()) { acc, sug in
          guard acc.count < 4 else {
            return acc
          }
          let find = Find.suggestedTerm(sug)
          guard !self.dispatched.contains(find) else {
            return acc
          }
          return acc + [find]
        }
        guard !finds.isEmpty else { return }
        self.dispatch(nil, finds: finds)
      } catch {
        er = error
      }
    }
  }
  
  private static func recentSearches(
    for term: String,
    fromCache cache: SearchCaching,
    except exceptions: [Find]
  ) throws -> [Find]? {
    if let feeds = try cache.feeds(for: term, limit: 2) {
      return feeds.reduce([Find]()) { acc, feed in
        let find = Find.recentSearch(feed)
        if exceptions.contains(find) {
          return acc
        } else {
          return acc + [find]
        }
      }
    }
    return nil
  }
  
  private static func suggestedFeeds(
    for term: String,
    fromCache cache: SearchCaching,
    except exceptions: [Find]
  ) throws -> [Find]? {
    let limit = 5
    if let feeds = try cache.feeds(matching: term, limit: limit + 2) {
      return feeds.reduce([Find]()) { acc, feed in
        let find = Find.suggestedFeed(feed)
        guard !exceptions.contains(find), acc.count < limit else {
          return acc
        }
        return acc + [find]
      }
    }
    return nil
  }
  
  private static func suggestedEntries(
    for term: String,
    fromCache cache: SearchCaching,
    except exceptions: [Find]
  ) throws -> [Find]? {
    let cached = try cache.entries(matching: term, limit: 5)
    if let entries = cached {
      return entries.reduce([Find]()) { acc, entry in
        let find = Find.suggestedEntry(entry)
        guard !exceptions.contains(find) else {
          return acc
        }
        return acc + [find]
      }
    }
    return nil
  }
  
  fileprivate func resume() {
    var er: Error?
    
    defer {
      if requestRequired {
        do {
          try request()
        } catch {
          done(error)
        }
      } else {
        done(er)
      }
    }
    
    let funs = [
      SuggestOperation.recentSearches,
      SuggestOperation.suggestedFeeds,
      SuggestOperation.suggestedEntries
    ]
    
    for f in funs {
      if isCancelled {
        return requestRequired = false
      }
      do {
        if let finds = try f(term, cache, Array(dispatched)) {
          guard !finds.isEmpty else { return }
          dispatch(nil, finds: finds)
        }
      } catch {
        return er = error
      }
    }
  }
  
  override func start() {
    guard !isCancelled else {
      return done()
    }
    
    guard !term.isEmpty else {
      return done(FeedKitError.invalidSearchTerm(term: term))
    }
    
    os_log("""
           starting suggest operation: {
             term: %{public}@,
             reachable: %i,
             ttl: %{public}@
           }
           """, log: log, type: .info, term, isAvailable, ttl.description)
    
    isExecuting = true
    
    do {
      let sug = Suggestion(term: originalTerm, ts: nil)
      let original = Find.suggestedTerm(sug)
      dispatch(nil, finds: [original]) // resulting in five suggested terms

      guard let cached = try cache.suggestions(for: term, limit: 4) else {
        os_log("nothing cached", log: log, type: .info)
        return resume()
      }
      
      os_log("cached: %{public}@", log: log, type: .info, cached)
      
      if isCancelled {
        return done()
      }
      
      // See timestamp comment in SearchOperation.
      guard let ts = cached.first?.ts else {
        return resume()
      }
      
      if !FeedCache.stale(ts, ttl: recommend(for: ttl).ttl) {
        let finds = cached.map { Find.suggestedTerm($0) }
        dispatch(nil, finds: finds)
        requestRequired = false
      } else {
        stock = cached
      }
      resume()
    } catch {
      done(error)
    }
  }
}
