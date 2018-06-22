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

  let client: JSONService
  
  init(client: JSONService) {
    self.client = client
  }
  
  /// Returns `true` if the remote `service` is reachable – and OK or if its
  /// last known error occured longer than 300 seconds ago,
  var isAvailable: Bool {
    let reachability: OlaStatus? = {
      do {
        return try findStatus()
      } catch {
        os_log("checking reachability: could not find status in dependencies")
        return Ola(host: client.host)?.reach()
      }
    }()

    guard let r = reachability else {
      return true
    }
    
    switch r {
    case .cellular, .reachable:
      if let (_, ts) = client.status {
        return Date().timeIntervalSince1970 - ts > 300
      } else {
        return true
      }
    case .unknown:
      return false
    }
  }
  
  private var _ttl = CacheTTL.long

  /// The maximal age, `CacheTTL.long` by default, of cached items.
  var ttl: CacheTTL {
    get {
      return isAvailable ? _ttl : .forever
    }
    set {
      _ttl = newValue
    }
  }
  
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
  
  func makeSeconds(ttl: CacheTTL) -> TimeInterval {
    let status: OlaStatus = {
      do {
        return try findStatus()
      } catch {
        return Ola(host: client.host)?.reach() ?? .unknown
      }
    }()
    
    switch status {
    case .cellular:
      switch ttl {
      case .none:
        return 3600
      case .short:
        return 28800
      case .medium:
        return 86400
      case .long, .forever:
        return Double.infinity
      }
    case .reachable:
      switch ttl {
      case .none:
        return 0
      case .short:
        return 3600
      case .medium:
        return 28800
      case .long:
        return 86400
      case .forever:
        return Double.infinity
      }
    case .unknown:
      return Double.infinity
    }
  }
  
}

