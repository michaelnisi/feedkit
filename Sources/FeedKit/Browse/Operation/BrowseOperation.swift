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
import MangerKit
import os.log

/// Comply with MangerKit API to enable using the remote service.
extension EntryLocator: MangerQuery {}

/// Although, I despise inheritance, this is an abstract `Operation` to be
/// extended by operations of the browse category. It provides common
/// properties for the, currently two: feed and entries; operations of the
/// browsing API.
class BrowseOperation: SessionTaskOperation {
  let cache: FeedCaching
  let svc: MangerService
  
  /// Initialize and return a new feed repo operation.
  ///
  /// - Parameters:
  ///   - cache: The persistent feed cache.
  ///   - svc: The remote service to fetch feeds and entries.
  init(cache: FeedCaching, svc: MangerService) {
    self.cache = cache
    self.svc = svc
    super.init(client: svc.client)
  }

}

