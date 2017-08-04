//
//  hash.swift
//  FeedKit
//
//  Created by Michael on 6/16/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation

/// Hashes a `string` using [djb2](http://www.cse.yorku.ca/~oz/hash.html), one 
/// of the best string hash functions, it has excellent distribution and speed 
/// on many different sets of keys and table sizes. 
/// [Use Your Loaf](https://useyourloaf.com/) has 
/// [this](https://useyourloaf.com/blog/swift-hashable/) to say about it.
///
/// - Parameter string: The string to hash.
///
/// - Returns: The hash of the string. Note that this might a negative value.
public func djb2Hash(string: String) -> Int {
  let unicodeScalars = string.unicodeScalars.map { $0.value }
  return unicodeScalars.reduce(5381) {
    ($0 << 5) &+ $0 &+ Int($1)
  }
}

// TODO: Type entry GUID Int

func entryGUID(for item: String, at url: String) -> String {
  return String(djb2Hash(string: url) ^ djb2Hash(string: item))
}
