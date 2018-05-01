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
  
  // Keeps track of forced updates per URL.
  private let forcedLog = DateCache()
  
  /// Returns `true` if a request to `uri` is OK to be forced. This has to be
  /// thread-safe, might get called from operations.
  func isEnforceable(_ uri: String) -> Bool {
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

    /// Creates a new service idea.
    ///
    /// - Parameters:
    ///   - reachability: The network reachability status of the remote service.
    ///   - ttl: The expected maximum time-to-live for cached data.
    ///   - status: The status of of the remote service, optionally.
    init(
      reachability: OlaStatus,
      expecting ttl: CacheTTL,
      status: (Int, TimeInterval)? = nil
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
  
}
