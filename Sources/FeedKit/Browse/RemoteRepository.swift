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

/// The common super class repositories of the browse category. Assuming one
/// service host per repository.
public class RemoteRepository: NSObject {
  let queue: OperationQueue
  
  public init(queue: OperationQueue) {
    dispatchPrecondition(condition: .onQueue(.main))
    
    self.queue = queue
  }
  
  deinit {
    queue.cancelAllOperations()
  }
}
