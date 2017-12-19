//
//  RemoteRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Ola

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
  
  private var forced = [String : Date]()
  
  private func forceable(_ uri: String) -> Bool {
    if let prev = forced[uri] {
      if prev.timeIntervalSinceNow < CacheTTL.short.seconds {
        return false
      }
    }
    forced[uri] = Date()
    return true
    
  }
  
  /// Return the momentary maximal age for cached items of a specific resource
  /// incorporating reachability and service status. This method's parameters
  /// are all optional.
  ///
  /// - Parameters:
  ///   - uri: The unique resource identifier.
  ///   - force: Force refreshing of cached items.
  ///   - status: The current status of the service, a tuple containing
  /// the latest error code and its timestamp.
  ///   - ttl: Override the default, `CacheTTL.Long`, to return.
  func timeToLive(
    _ uri: String? = nil,
    force: Bool = false,
    reachable: Bool = true,
    status: (Int, TimeInterval)? = nil,
    ttl: CacheTTL = CacheTTL.long
  ) -> CacheTTL {
    guard reachable else {
      return CacheTTL.forever
    }
    
    if force, let k = uri {
      if forceable(k) {
        return CacheTTL.none
      }
    }
    
    // TODO: Check if this catches timeouts as well
    
    if let (code, ts) = status {
      let date = Date(timeIntervalSince1970: ts)
      if code != 0 && !FeedCache.stale(date, ttl: CacheTTL.short.seconds) {
        return CacheTTL.forever
      }
    }
    
    return ttl
  }
}
