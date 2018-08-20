//
//  TrimQueueOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 25.01.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import os.log

private let log = OSLog.disabled

/// Trims users’ queue, keeping latest and explicitly enqueued items.
class TrimQueueOperation: Operation, Providing {
  
  private let sQueue = DispatchQueue(
    label: "ink.codes.podest.TrimQueueOperation-\(UUID().uuidString).serial")
  
  // Theoretically, all public properties of operation have to be synchronized
  // to work correctly in all circumstances. Otherwise users have to be careful
  // in which order they’re doing stuff.
  
  private
  var _trimQueueCompletionBlock: ((_ newData: Bool, _ error: Error?) -> Void)?
  
  /// The block to use to process the trim result. Accessing this block is
  /// thread-safe.
  ///
  /// - Parameters:
  ///   - newData: If we are dependent on an enqueue operation, `true` if new
  /// items have been enqueued.
  ///   - error: An optional error.
  var trimQueueCompletionBlock: ((_ newData: Bool, _ error: Error?) -> Void)? {
    get {
      return sQueue.sync {
        return _trimQueueCompletionBlock
      }
    }
    set {
      sQueue.sync {
        _trimQueueCompletionBlock = newValue
      }
    }
  }
  
  // MARK: Providing
  
  private(set) var error: Error?
  
  // MARK: Internals

  private func done(_ error: Error? = nil) {
    let (newData, error): (Bool, Error?) = {
      for dep in dependencies {
        if case let enqueue as EnqueueOperation = dep {
          return (!enqueue.entries.isEmpty, enqueue.error ?? error)
        }
      }
      return (false, error)
    }()
    
    self.error = error
    
    trimQueueCompletionBlock?(newData, error)
  }
  
  let cache: QueueCaching
  
  init(cache: QueueCaching) {
    self.cache = cache
  }
  
  override func main() {
    os_log("starting TrimQueueOperation", log: log, type: .debug)
    
    do {
      try cache.trim()
      done()
    } catch {
      done(error)
    }
  }

}
