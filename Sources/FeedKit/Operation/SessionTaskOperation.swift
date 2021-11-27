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
import os.log
import Ola
import Patron

private let log = OSLog.disabled

/// A generic concurrent operation providing a URL session task. This abstract
/// class is to be extended.
class SessionTaskOperation: ConcurrentOperation, ReachabilityDependent {

  struct CachePolicy {
    let ttl: TimeInterval
    let http: NSURLRequest.CachePolicy
  }
  
  /// Availability of a service.
  enum Availability {
    case offline
    case presumably
    case no
  }

  let client: JSONService
  
  init(client: JSONService) {
    self.client = client
  }

  /// Detailed availability of the remote service extending reachability with
  /// service health.
  lazy var availability: Availability = {
    switch status {
    case .cellular, .reachable:
      if let (_, ts) = client.status {
        return Date().timeIntervalSince1970 - ts > 300 ? .presumably : .no
      } else {
        return .presumably
      }
    case .unknown:
      return .offline
    }
  }()
  
  /// Returns `true` if the remote `service` is reachable – and OK or if its
  /// last known error occured longer than 300 seconds ago.
  ///
  /// Combining reachability and service health in one property is incorrect,
  /// we have to be more explicit here. That’s why I have added `availability`
  /// which should eventually replace this `Bool`.
  lazy var isAvailable: Bool = {
    switch availability {
    case .presumably: 
      return true
    case .no, .offline:
      return false
    }
  }()
  
  /// The maximal age, `CacheTTL.long` by default, of cached items.
  var ttl: CacheTTL = .long

  final var task: URLSessionTask? {
    willSet {
      os_log("cancelling task", log: log, type: .info)
      task?.cancel()
    }

    didSet {
      guard oldValue != task else {
        return
      }

      guard task != nil else {
        return NetworkActivityCounter.shared.decrease()
      }
      NetworkActivityCounter.shared.increase()
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

