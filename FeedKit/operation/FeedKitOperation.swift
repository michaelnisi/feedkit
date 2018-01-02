//
//  FeedKitOperation.swift
//  FeedKit
//
//  Created by Michael Nisi on 18.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Ola

protocol Providing {
  var error: Error? { get }
}

protocol ProvidingReachability: Providing {
  var status: OlaStatus { get }
}

protocol ProvidingLocators: Providing {
  var locators: [EntryLocator]  { get }
}

protocol ProvidingEntries: Providing {
  var entries: Set<Entry> { get }
}

/// An abstract super class to be extended by concurrent FeedKit operations.
class FeedKitOperation: Operation {
  
  /// Queue for synchronized property access.
  private let access = DispatchQueue(
    label: "ink.codes.feedkit.\(UUID().uuidString)")
  
  fileprivate var _executing: Bool = false
  
  override final var isExecuting: Bool {
    get {
      return access.sync {
        return _executing
      }
    }

    set {
      access.sync {
        guard newValue != _executing else {
          fatalError("FeedKitOperation: already executing")
        }
      }

      willChangeValue(forKey: "isExecuting")
      
      access.sync {
        _executing = newValue
      }
      
      didChangeValue(forKey: "isExecuting")
    }
  }
  
  fileprivate var _finished: Bool = false
  
  override final var isFinished: Bool {
    get {
      return access.sync {
        return _finished
      }
    }
    
    set {
      access.sync {
        guard newValue != _finished else {
          // Just to be extra annoying.
          fatalError("FeedKitOperation: already finished")
        }
      }

      willChangeValue(forKey: "isFinished")
      
      access.sync {
        _finished = newValue
      }
      
      didChangeValue(forKey: "isFinished")
    }
  }
}
