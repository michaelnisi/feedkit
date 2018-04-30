//
//  RemoteRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Ola
import os.log

/// The common super class repositories of the browse category. Assuming one
/// service host per repository.
public class RemoteRepository: NSObject {
  let queue: OperationQueue
  let probe: Reaching
  
  public init(queue: OperationQueue, probe: Reaching) {
    self.queue = queue
    self.probe = probe
  }
  
  deinit {
    queue.cancelAllOperations()
  }
  
  func reachable() -> Bool {
    let r = probe.reach()
    return r == .reachable || r == .cellular
  }
  
  // Keeps track of forced updates per URL.
  private let forcedLog = DateCache()
  
  /// Returns `true` if a request to `uri` is OK to be forced. This has to be
  /// thread-safe, might get called from operations.
  private func forceable(_ uri: String) -> Bool {
    return forcedLog.update(uri)
  }
  
  /// A momentary idea of how to optimally approach requests involving the
  /// underlying remote service.
  struct ServiceIdea {
    let isAvailable: Bool
    let reachability: OlaStatus
    let ttl: CacheTTL
    
    var isOffline: Bool {
      if case .unknown = reachability {
        return true
      }
      return false
    }
    
    /// - Parameters:
    ///   - reachability: The network reachability status of the remote service.
    ///   - ttl: The expected maximum time-to-live for cached data.
    ///   - status: The status of of the remote service, optionally.
    ///   - forcing: The forcing tuple of log and URI, optionally.
    init(
      reachability: OlaStatus,
      expecting ttl: CacheTTL,
      status: (Int, TimeInterval)? = nil,
      forcing: (DateCache, String)? = nil
    ) {
      self.reachability = reachability
      
      switch reachability {
      case .cellular, .reachable:
        if let (_, ts) = status {
          if Date().timeIntervalSince1970 - ts < 300 {
            self.isAvailable = false
            self.ttl = .forever
          } else {
            self.isAvailable = true
            self.ttl = ttl
          }
        } else if let (log, url) = forcing, log.update(url) {
          self.isAvailable = true
          self.ttl = .forever
        } else {
          self.isAvailable = true
          self.ttl = ttl
        }
      case .unknown:
        self.isAvailable = false
        self.ttl = .forever
      }
    }
  }
  
  /// Returns availablility tuple containing network reachability and
  /// reasonable cache time-to-live. An error leaves the service stigmatized
  /// for five minutes, enough breathing room for the server to recover, saving
  /// redundant request response cycles.
  ///
  /// Paramters are all optional.
  ///
  /// - Parameters:
  ///   - uri: The unique resource identifier.
  ///   - force: Force refreshing of cached items.
  ///   - reachable: Pass `true` if the service is reachable over the network.
  ///   - status: The current status of the service, a tuple containing
  /// the latest error code and its timestamp.
  ///   - ttl: Override the default, `CacheTTL.Long`, to return.
  ///
  /// - Returns: The availablility tuple `(available, ttl)`.
  func makeAvailablilityTuple(
    uri: String? = nil,
    force: Bool = false,
    reachable: Bool = true,
    status: (Int, TimeInterval)? = nil,
    ttl: CacheTTL = .long)
  -> (Bool, CacheTTL) {
    guard reachable else {
      return (false, .forever)
    }
    
    if force, let k = uri {
      if forceable(k) {
        return (true, .none)
      }
    }
    
    guard let (err, ts) = status else {
      return (true, ttl)
    }
    
    os_log("service has been marked unreachable: %{public}i", err)
    
    let stigmatized = Date().timeIntervalSince1970 - ts < 300
    return stigmatized ? (false, .forever) : (true, ttl)
  }
  
  /// Returns the momentary maximal age for cached items of a specific resource
  /// incorporating reachability and service status. This method's parameters
  /// are all optional.
  ///
  /// - Parameters:
  ///   - uri: The unique resource identifier.
  ///   - force: Force refreshing of cached items.
  ///   - reachable: Pass `true` if the service is reachable over the network.
  ///   - status: The current status of the service, a tuple containing
  /// the latest error code and its timestamp.
  ///   - ttl: Override the default, `CacheTTL.Long`, to return.
  @available(*, deprecated: 8.1.0, message: "Use makeAvailablilityTuple")
  func timeToLive(
    _ uri: String? = nil,
    force: Bool = false,
    reachable: Bool = true,
    status: (Int, TimeInterval)? = nil,
    ttl: CacheTTL = .long
  ) -> CacheTTL {
    guard reachable else {
      return .forever
    }
    
    if force, let k = uri {
      if forceable(k) {
        return .none
      }
    }

    if let (code, ts) = status {
      let date = Date(timeIntervalSince1970: ts)
      if code != 0 && !FeedCache.stale(date, ttl: CacheTTL.short.seconds) {
        return .forever
      }
    }
    
    return ttl
  }
}
