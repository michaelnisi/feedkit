//
//  FeedKitOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

/// An abstract super class to be extended by **concurrent** FeedKit operations.
class FeedKitOperation: Operation {
  
  /// An internal serial queue for synchronized (thread-safe) property access.
  private let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.FeedKitOperation.\(UUID().uuidString)")
  
  fileprivate var _executing: Bool = false
  
  override final var isExecuting: Bool {
    get {
      return sQueue.sync {
        return _executing
      }
    }

    set {
      sQueue.sync {
        guard newValue != _executing else {
          fatalError("FeedKitOperation: already executing")
        }
      }

      willChangeValue(forKey: "isExecuting")
      
      sQueue.sync {
        _executing = newValue
      }
      
      didChangeValue(forKey: "isExecuting")
    }
  }
  
  fileprivate var _finished: Bool = false
  
  override final var isFinished: Bool {
    get {
      return sQueue.sync {
        return _finished
      }
    }
    
    set {
      sQueue.sync {
        guard newValue != _finished else {
          fatalError("FeedKitOperation: already finished")
        }
      }

      willChangeValue(forKey: "isFinished")
      
      sQueue.sync {
        _finished = newValue
      }
      
      didChangeValue(forKey: "isFinished")
    }
  }
}
