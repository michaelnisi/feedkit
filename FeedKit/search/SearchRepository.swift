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

/// The search repository provides a search API orchestrating remote services
/// and persistent caching.
public final class SearchRepository: RemoteRepository, Searching {
  let cache: SearchCaching
  let svc: FanboyService

  /// Initializes and returns a new search repository object.
  ///
  /// - Parameters:
  ///   - cache: The search cache.
  ///   - queue: An operation queue to run the search operations.
  ///   - svc: The fanboy service to handle remote queries.
  ///   - probe: The probe object to probe reachability.
  public init(
    cache: SearchCaching,
    svc: FanboyService,
    queue: OperationQueue,
    probe: Reaching
    ) {
    self.cache = cache
    self.svc = svc
    
    super.init(queue: queue, probe: probe)
  }
  
  /// Configures and adds `operation` to the queue, returns executing operation.
  fileprivate func execute(_ operation: SearchRepoOperation) -> Operation {
    let r = reachable()
    let term = operation.term
    let status = svc.client.status
    
    operation.reachable = r
    operation.ttl = timeToLive(term, force: false, reachable: r, status: status)
    
    queue.addOperation(operation)
    
    return operation
  }
  
  public func search(
    _ term: String,
    perFindGroupBlock: ((Error?, [Find]) -> Void)?,
    searchCompletionBlock: ((Error?) -> Void)?
  ) -> Operation {
    let op = SearchOperation(cache: cache, svc: svc, term: term)
    op.perFindGroupBlock = perFindGroupBlock
    op.searchCompletionBlock = searchCompletionBlock
    return execute(op)
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
