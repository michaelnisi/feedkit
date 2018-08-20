//
//  SessionTaskOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log
import Ola
import Patron

private let log = OSLog.disabled

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

  struct CachePolicy {
    let ttl: TimeInterval
    let http: NSURLRequest.CachePolicy
  }
  
  let client: JSONService
  
  init(client: JSONService) {
    self.client = client
  }
  
  /// Returns `true` if the remote `service` is reachable – and OK or if its
  /// last known error occured longer than 300 seconds ago,
  lazy var isAvailable: Bool = {
    switch status {
    case .cellular, .reachable:
      if let (_, ts) = client.status {
        return Date().timeIntervalSince1970 - ts > 300
      } else {
        return true
      }
    case .unknown:
      return false
    }
  }()
  
  /// The maximal age, `CacheTTL.long` by default, of cached items.
  var ttl: CacheTTL = .long
  
  /// Posts `name` to the default notifcation center.
  func post(name: NSNotification.Name) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: name, object: nil)
    }
  }
  
  final var task: URLSessionTask? {
    willSet {
      os_log("cancelling task", log: log, type: .debug)
      task?.cancel()
    }

    didSet {
      os_log("posting notification", log: log, type: .debug)
      post(name: task != nil ? .FKRemoteRequest : .FKRemoteResponse)
    }
  }
  
  deinit {
    task = nil
  }
  
  lazy var status: OlaStatus = {
    do {
      return try findStatus()
    } catch {
      return Ola(host: client.host)?.reach() ?? .unknown
    }
  }()
  
  /// Recommends a relative cache policy for `ttl`.
  ///
  /// - Parameter ttl: The cache wanted caching time-to-live.
  ///
  /// - Returns: The recommended cache policy.
  func recommend(for ttl: CacheTTL) -> CachePolicy {
    switch status {
    case .cellular:
      switch ttl {
      case .none:
        return CachePolicy(ttl: 0, http: .useProtocolCachePolicy)
      case .short:
        return CachePolicy(ttl: 3600 * 3, http: .returnCacheDataElseLoad)
      case .medium:
        return CachePolicy(ttl: 28800 * 3, http: .returnCacheDataElseLoad)
      case .long:
        return CachePolicy(ttl: 86400 * 3, http: .returnCacheDataElseLoad)
      case .forever:
        return CachePolicy(ttl: Double.infinity, http: .returnCacheDataElseLoad)
      }
    case .reachable:
      switch ttl {
      case .none:
        return CachePolicy(ttl: 0, http: .reloadIgnoringLocalCacheData)
      case .short:
        return CachePolicy(ttl: 3600, http: .useProtocolCachePolicy)
      case .medium:
        return CachePolicy(ttl: 28800, http: .useProtocolCachePolicy)
      case .long:
        return CachePolicy(ttl: 86400, http: .useProtocolCachePolicy)
      case .forever:
        return CachePolicy(ttl: Double.infinity, http: .returnCacheDataElseLoad)
      }
    case .unknown:
      return CachePolicy(ttl: Double.infinity, http: .useProtocolCachePolicy)
    }
  }
  
}

