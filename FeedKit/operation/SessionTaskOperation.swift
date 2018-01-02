//
//  SessionTaskOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

/// A generic concurrent operation providing a URL session task. This abstract
/// class is to be extended.
class SessionTaskOperation: FeedKitOperation {
  
  /// If you know in advance that the remote service is currently not available,
  /// you might set this to `false` to be more effective.
  var reachable: Bool = true
  
  /// The maximal age, `CacheTTL.long`, of cached items.
  var ttl: CacheTTL = CacheTTL.long
  
  func post(name: NSNotification.Name) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: name, object: self)
    }
  }
  
  final var task: URLSessionTask? {
    willSet {
      guard newValue != nil else {
        return
      }
      post(name: Notification.Name.FKRemoteRequest)
    }
  }
  
  deinit {
    task?.cancel()
  }
  
}
