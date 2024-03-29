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

/// An abstract super class to be extended by **concurrent** FeedKit operations.
///
/// Access to any data variables in the operation must be synchronized to
/// prevent potential data corruption. You can use the `sQueue` DispatchQueue
/// to achieve that.
class ConcurrentOperation: Operation {

  /// An internal serial queue for synchronized (thread-safe) property access.
  let sQueue = DispatchQueue(
    label: "ink.codes.feedkit.ConcurrentOperation.\(UUID().uuidString)",
    target: .global(qos: .userInitiated)
  )

  private var _executing: Bool = false

  override final var isExecuting: Bool {
    get { sQueue.sync { _executing } }

    set {
      sQueue.sync {
        guard newValue != _executing else {
          fatalError("ConcurrentOperation: already executing")
        }
      }

      willChangeValue(forKey: "isExecuting")

      sQueue.sync {
        _executing = newValue
      }

      didChangeValue(forKey: "isExecuting")
    }
  }

  private var _finished: Bool = false

  override final var isFinished: Bool {
    get { sQueue.sync { _finished } }

    set {
      sQueue.sync {
        guard newValue != _finished else {
          fatalError("ConcurrentOperation: already finished")
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
