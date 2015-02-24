//
//  common.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import XCTest

typealias AnyFrom = NSDictionary -> (NSError?, AnyObject?)

func schemaForClass (aClass: AnyClass!) -> String {
  let bundle = NSBundle(forClass: aClass)
  return bundle.pathForResource("schema", ofType: "sql")!
}

func shouldError (from: AnyFrom, dict: NSDictionary, wanted: NSError) {
  let (er, result: AnyObject?) = from(dict)
  if let found = er {
    XCTAssertEqual(found, wanted)
  } else {
    XCTAssert(false, "should error")
  }
  XCTAssertNil(result)
}
