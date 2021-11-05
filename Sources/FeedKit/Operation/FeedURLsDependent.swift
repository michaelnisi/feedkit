//===----------------------------------------------------------------------===//
//
// This source file is part of the Podest open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/podest/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

import Foundation

protocol FeedURLsDependent {}

extension FeedURLsDependent where Self: Operation {
  func findFeedURLs() throws -> [FeedURL] {
    for dep in dependencies {
      if case let prov as ProvidingLocators = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        return prov.locators.map { $0.url }
      }
    }
    throw ProvidingError.missingLocators
  }
}
