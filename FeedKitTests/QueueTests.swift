//
//  QueueTests.swift
//  FeedKit
//
//  Created by Michael on 6/9/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
import Ola

@testable import FeedKit

class QueueTests: XCTestCase {
  
  fileprivate var queue: Queue<String>!
  
  private func freshBrowser() -> Browsing {
    let cache = freshCache(self.classForCoder)
    let svc = freshManger(string: "http://localhost:8384")
    
    let dpq = DispatchQueue(label: "ink.codes.test.browsing")
    let queue = OperationQueue()
    queue.underlyingQueue = dpq
    
    let probe = Ola(host: "http://localhost:8384", queue: dpq)!
    
    return FeedRepository(cache: cache, svc: svc, queue: queue, probe: probe)
  }
  
  override func setUp() {
    super.setUp()
    queue = Queue()
  }
  
  override func tearDown() {
    queue = nil
    super.tearDown()
  }
  
  lazy fileprivate var items: [String] = {
    var items = [String]()
    
    for i in 1...8 {
      items.append(String(i))
    }
    
    return items
  }()
  
  private func populate() {
    try! self.queue.add(items: items)
  }
  
  func testInit() {
    queue = try! Queue(items: items, next: "4")
    for i in 4..<8 {
      let found = queue.forward()
      let wanted = String(i + 1)
      print("found: \(found!), wanted: \(wanted)")
      // XCTAssertEqual(found, wanted)
    }
  }
  
  func testForward() {
    XCTAssertNil(queue.forward())
    
    populate()

    for i in 1...8 {
      XCTAssertEqual(queue.forward(), String(i))
    }
  }
  
  func testBackward() {
    XCTAssertNil(queue.backward())
    
    populate()
    
    XCTAssertNil(queue.backward())
    
    for i in 1...8 {
      XCTAssertEqual(queue.forward(), String(i))
    }
    
    for i in 1...8 {
      XCTAssertEqual(queue.backward(), String(i))
    }
  }
  
  func testRemove() {
    XCTAssertThrowsError(try queue.remove("11"), "should throw") { er in
      switch er {
      case QueueError.notInQueue:
        break
      default:
        XCTFail()
      }
    }
  }
  
  func testAdd() {
    let item = "11"
    try! queue.add(item)
    
    XCTAssert(queue.contains("11"))
    
    let wanted = item
    for _ in 1...8 {
      XCTAssertEqual(queue.forward(), wanted)
      XCTAssertEqual(queue.backward(), wanted)
    }
    
    XCTAssertThrowsError(try queue.add(item), "should throw") { er in
      switch er {
      case QueueError.alreadyInQueue:
        break
      default:
        XCTFail()
      }
    }
  }
}
