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

struct Item: Identifiable, Equatable {
  let guid: String
  
  static func ==(lhs: Item, rhs: Item) -> Bool {
    return lhs.guid == rhs.guid
  }
}

class QueueTests: XCTestCase {
  
  var queue: Queue!
  
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
  
  private func populate() {
    for i in 1...8 {
      let guid = String(i)
      let item = Item(guid: guid)
      
      try! self.queue.add(item)
    }
  }
  
  func testForward() {
    XCTAssertNil(queue.forward())
    
    populate()
    
    var i = 8
    repeat {
      XCTAssertEqual(queue.forward() as! Item, Item(guid: String(i)))
      i = i - 1
    } while i > 0
  }
  
  func testBackward() {
    XCTAssertNil(queue.backward())
    
    populate()
    
    for _ in 1...8 {
      XCTAssertNotNil(queue.forward())
    }
    
    for i in 1...8 {
      XCTAssertEqual(queue.backward() as! Item, Item(guid: String(i)))
    }
  }
  
  func testRemove() {
    XCTAssertThrowsError(try queue.remove(guid: "11"), "should throw") { er in
      switch er {
      case QueueError.notInQueue:
        break
      default:
        XCTFail()
      }
    }
  }
  
  func testAdd() {
    let item = Item(guid: "11")
    try! queue.add(item)
    
    XCTAssert(queue.contains(guid: "11"))
    
    let wanted = item
    for _ in 1...8 {
      XCTAssertEqual(queue.forward() as! Item, wanted)
      XCTAssertEqual(queue.backward() as! Item, wanted)
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
