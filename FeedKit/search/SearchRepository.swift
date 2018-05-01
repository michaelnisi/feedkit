//
//  SearchRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit
import Ola
import os.log

/// The search repository provides a search API orchestrating remote services
/// and persistent caching.
public final class SearchRepository: RemoteRepository, Searching {
  let cache: SearchCaching
  let svc: FanboyService
  let browser: Browsing

  /// Initializes and returns a new search repository object.
  ///
  /// - Parameters:
  ///   - cache: The search cache.
  ///   - svc: The fanboy service to handle remote queries.
  ///   - browser: The browser to fetch feeds.
  ///   - queue: An operation queue to run the search operations.
  ///   - probe: The probe object to probe reachability.
  public init(
    cache: SearchCaching,
    svc: FanboyService,
    browser: Browsing,
    queue: OperationQueue,
    probe: Reaching
  ) {
    self.browser = browser
    self.cache = cache
    self.svc = svc

    super.init(queue: queue, probe: probe)
  }
  
  /// Configures and adds `operation` to the queue, returns executing operation.
  private func execute(_ operation: SearchRepoOperation) -> Operation {
    let idea = RemoteRepository.ServiceIdea(
      reachability: probe.reach(),
      expecting: .long,
      status: svc.client.status
    )
    
    operation.isOffline = idea.isOffline
    operation.isAvailable = idea.isAvailable
    operation.ttl = idea.ttl
    
    queue.addOperation(operation)
    
    return operation
  }
  
  public func search(
    _ term: String,
    perFindGroupBlock: ((Error?, [Find]) -> Void)?,
    searchCompletionBlock: ((Error?) -> Void)?
  ) -> Operation {
    let searching = SearchOperation(cache: cache, svc: svc, term: term)
    searching.perFindGroupBlock = perFindGroupBlock
    searching.searchCompletionBlock = searchCompletionBlock
    
    if let url = FeedID.urlString(string: term) {
      searching.addDependency(browser.feeds([url]))
    }

    return execute(searching)
  }
  
  public func suggest(
    _ term: String,
    perFindGroupBlock: ((Error?, [Find]) -> Void)?,
    suggestCompletionBlock: ((Error?) -> Void)?
  ) -> Operation {
    let op = SuggestOperation(cache: cache, svc: svc, term: term)
    op.perFindGroupBlock = perFindGroupBlock
    op.suggestCompletionBlock = suggestCompletionBlock
    return execute(op)
  }
}
