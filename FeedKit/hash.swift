//
//  hash.swift
//  FeedKit
//
//  Created by Michael on 10/17/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

/// Returns 32-bit hash of `string`.
///
/// - [djb2](http://www.cse.yorku.ca/~oz/hash.html)
/// - [Use Your Loaf](https://useyourloaf.com/blog/swift-hashable/)
///
/// - Parameter string: The string to hash.
///
/// - Returns: A 32-bit signed Integer.
public func djb2Hash32(string: String) -> Int32 {
  let unicodeScalars = string.unicodeScalars.map { $0.value }
  return Int32(unicodeScalars.reduce(5381) {
    ($0 << 5) &+ $0 &+ Int32($1)
  })
}
