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

/// Returns a consistent 32-bit hash of `string`.
///
/// - [djb2](http://www.cse.yorku.ca/~oz/hash.html)
/// - [Use Your Loaf](https://useyourloaf.com/blog/swift-hashable/)
///
/// - Parameter string: The string to hash.
///
/// - Returns: A pure 32-bit signed Integer.
public func djb2Hash32(string: String) -> Int32 {
  let unicodeScalars = string.unicodeScalars.map { $0.value }
  
  return Int32(unicodeScalars.reduce(5381) {
    ($0 << 5) &+ $0 &+ Int32($1)
  })
}
