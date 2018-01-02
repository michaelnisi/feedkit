//
//  BrowseOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 17.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import os.log

/// Although, I despise inheritance, this is an abstract `Operation` to be
/// extended by operations of the browse category. It provides common
/// properties for the, currently two: feed and entries; operations of the
/// browsing API.
class BrowseOperation: SessionTaskOperation {
  let cache: FeedCaching
  let svc: MangerService
  let target: DispatchQueue
  
  /// Initialize and return a new feed repo operation.
  ///
  /// - Parameters:
  ///   - cache: The persistent feed cache.
  ///   - svc: The remote service to fetch feeds and entries.
  init(cache: FeedCaching, svc: MangerService) {
    self.cache = cache
    self.svc = svc
    
    self.target = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
    os_log("** target: %{public}@", type: .debug, self.target)
  }

}
