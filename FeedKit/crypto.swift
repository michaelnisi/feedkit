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
func md5Digest(_ str: String) -> String {
  var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
  if let data = str.data(using: String.Encoding.utf8) {
    CC_MD5((data as NSData).bytes, CC_LONG(data.count), &digest)
  }
  var digestHex = ""
  for index in 0..<Int(CC_MD5_DIGEST_LENGTH) {
    digestHex += String(format: "%02x", digest[index])
  }
  return digestHex
}
