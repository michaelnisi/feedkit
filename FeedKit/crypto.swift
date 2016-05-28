//
//  crypto.swift
//  FeedKit
//
//  Created by Michael Nisi on 29/02/16.
//  Copyright © 2016 Michael Nisi. All rights reserved.
//

import Foundation
import CommonCrypto

/// Create an MD5, 128-bit (16-byte), hash value from the specified string.
///
/// - Parameter str: The string to digest.
/// - Returns: A MD5 digested string.
func md5Digest(str: String) -> String {
  var digest = [UInt8](count: Int(CC_MD5_DIGEST_LENGTH), repeatedValue: 0)
  if let data = str.dataUsingEncoding(NSUTF8StringEncoding) {
    CC_MD5(data.bytes, CC_LONG(data.length), &digest)
  }
  var digestHex = ""
  for index in 0..<Int(CC_MD5_DIGEST_LENGTH) {
    digestHex += String(format: "%02x", digest[index])
  }
  return digestHex
}