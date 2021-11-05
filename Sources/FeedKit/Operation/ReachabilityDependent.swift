//===----------------------------------------------------------------------===//
//
// This source file is part of the FeedKit open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/feedkit/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import Ola

protocol ReachabilityDependent {}

extension ReachabilityDependent where Self: Operation {
  /// Finds and returns the first reachability status in operation dependencies,
  /// which implement `ProvidingReachability`.
  ///
  /// - Returns: The first `OlaStatus` found.
  /// - Throws: `ProvidingError.missingStatus` if status hasn’t been provided.
  func findStatus() throws -> OlaStatus {
    var status: OlaStatus?
    for dep in dependencies {
      if case let prov as ProvidingReachability = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        switch prov.status {
        case .cellular, .reachable:
          // Reachable is assumed, so these aren’t relevant.
          continue
        case .unknown:
          status = prov.status
        }
      }
    }
    guard let found = status else {
      throw ProvidingError.missingStatus
    }
    return found
  }
}
