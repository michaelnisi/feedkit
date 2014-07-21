//
//  EntryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 25.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest

import FeedKit

class EntryTests: XCTestCase {
  
  func testInitializers () {
    let enc = Enclosure(href: "a", length:0, type:"b")
    let entry = Entry(title: "a", enclosure: enc)
  }
}
