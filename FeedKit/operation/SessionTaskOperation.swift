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
  
  var _isOffline: Bool = false
  
  /// No network reachability. If this is false, operation dependencies are
  /// tried. Use `isAvailable` as general check, probe `isOffline` for more
  /// details. Are we offline?
  var isOffline: Bool {
    get {
      guard _isOffline else {
        do {
          let s = try findStatus()
          _isOffline = s != .reachable && s != .cellular
          if _isOffline {
            isAvailable = false
          }
        } catch {
          _isOffline = false
        }
        return _isOffline
      }
      return _isOffline
    }
    
    set {
      _isOffline = newValue
    }
  }
  
  /// If you know in advance that the remote service is currently not available,
  /// you may set this to `false` to be more effective.
  var isAvailable: Bool = true
  
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
