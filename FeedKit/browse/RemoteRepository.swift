//
//  RemoteRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 19.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

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
  
}
