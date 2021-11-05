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

protocol LocatorsDependent {}

extension LocatorsDependent where Self: Operation {
  
  /// Returns locators of the **first** locator providing dependency. Note that
  /// these are not accumulated from all providers, but only from the first one.
  ///
  /// - Throws: If no dependency provides locators, this throws
  /// `ProvidingError.missingLocators`.
  func findLocators() throws -> [EntryLocator] {
    for dep in dependencies {
      if case let prov as ProvidingLocators = dep {
        guard prov.error == nil else {
          throw prov.error!
        }
        return prov.locators
      }
    }
    throw ProvidingError.missingLocators
  }
}
