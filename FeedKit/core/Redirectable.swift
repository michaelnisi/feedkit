//
//  Redirectable.swift
//  FeedKit
//
//  Created by Michael Nisi on 05.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation

public protocol Redirectable {
  var url: String { get }
  var originalURL: String? { get }
}

extension Redirectable {
  
  /// Filters and returns `items` with redirected URLs.
  static func redirects(in items: [Redirectable]) -> [Redirectable] {
    return items.filter {
      guard let originalURL = $0.originalURL, originalURL != $0.url else {
        return false
      }
      return true
    }
  }
  
}

