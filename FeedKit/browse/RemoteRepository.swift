//
//  RemoteRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

/// The common super class repositories of the browse category. Assuming one
/// service host per repository.
public class RemoteRepository: NSObject {
  let queue: OperationQueue
  
  public init(queue: OperationQueue) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    self.queue = queue
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
  
}
