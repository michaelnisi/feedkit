//
//  SearchRepoOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import FanboyKit

/// An abstract class to be extended by search repository operations.
class SearchRepoOperation: SessionTaskOperation {
  
  let cache: SearchCaching
  let originalTerm: String
  let svc: FanboyService
  let term: String
  let target: DispatchQueue
  
  /// Returns an initialized search repo operation.
  ///
  /// - Parameters:
  ///   - cache: A persistent search cache.
  ///   - svc: The remote search service to use.
  ///   - term: The term to search—or get suggestions—for; it can be any
  ///   string.
  init(cache: SearchCaching, svc: FanboyService, term: String) {
    self.cache = cache
    self.originalTerm = term
    self.svc = svc
    
    let trimmed = replaceWhitespaces(in: term.lowercased(), with: " ")
    
    self.term = trimmed
    self.target = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
  }
  
}
