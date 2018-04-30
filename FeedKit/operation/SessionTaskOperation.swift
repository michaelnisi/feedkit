//
//  SessionTaskOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

public extension Notification.Name {
  
  /// Posted when a remote request has been started.
  static var FKRemoteRequest =
    NSNotification.Name("FeedKitRemoteRequest")
  
  /// Posted when a remote response has been received.
  static var FKRemoteResponse =
    NSNotification.Name("FeedKitRemoteResponse")
  
}

/// A generic concurrent operation providing a URL session task. This abstract
/// class is to be extended.
class SessionTaskOperation: FeedKitOperation, ReachabilityDependent {
  
  var _reachable: Bool?
  
  /// If you know in advance that the remote service is currently not available,
  /// you may set this to `false` to be more effective. If this is not set, when
  /// a request is about to be issued, operation dependencies are tried. If no
  /// dependency provides a status, optimistically, it is assumed that the
  /// service might as well be reachable.
  var reachable: Bool {
    get {
      guard let r = _reachable else {
        do {
          let s = try findStatus()
          _reachable = s == .reachable || s == .cellular
        } catch {
          os_log("depending on status failed: assuming reachable")
          _reachable = true
        }
        return _reachable!
      }
      return r
    }
    set {
      _reachable = newValue
    }
  }
  
  /// The maximal age, `CacheTTL.long`, of cached items.
  var ttl = CacheTTL.long
  
  /// Posts `name` to the default notifcation center.
  func post(name: NSNotification.Name) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: name, object: nil)
    }
  }
  
  final var task: URLSessionTask? {
    didSet {
      if task != nil {
        post(name: .FKRemoteRequest)
      } else if oldValue != nil {
        oldValue?.cancel()
        post(name: .FKRemoteResponse)
      }
    }
  }
  
  deinit {
    task = nil
  }
  
}
