//
//  hash.swift
//  FeedKit
//
//  Created by Michael on 6/16/17.
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
public func djb2Hash(string: String) -> Int {
  let unicodeScalars = string.unicodeScalars.map { $0.value }
  return Int(unicodeScalars.reduce(5381) {
    ($0 << 5) &+ $0 &+ Int32($1)
  })
}

// TODO: Type entry GUID Int

/// Creates a globally unique identifier by combining an element `guid`, as
/// specified by RSS or atom:id, unique within their respective feeds, with its 
/// feed `url`. Combined with the URL, we can assume *fair* global uniqueness.
func entryGUID(for guid: String, at url: String) -> String {
  return String(djb2Hash(string: url) ^ djb2Hash(string: guid))
}
