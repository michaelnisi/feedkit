//
//  QueueTests.swift
//  FeedKit
//
//  Created by Michael on 6/9/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest

@testable import FeedKit

final class QueueTests: XCTestCase {
  
  fileprivate var queue: Queue<Int>!
  
  override func setUp() {
    super.setUp()
    queue = Queue<Int>()
  }
  
  override func tearDown() {
    queue = nil
    super.tearDown()
  }
  
  fileprivate var items = [1, 2, 3, 4, 5, 6, 7, 8]
  
  private func populate() {
    try! self.queue.append(items: items)
    XCTAssertEqual(queue.current, 1)
    XCTAssertEqual(queue.items, items)
  }
  
  func testInitItems() {
    XCTAssertNoThrow(Queue<Int>(items: []))
    XCTAssertNil(Queue<Int>().current)
    XCTAssertEqual(Queue<Int>(items: items).items, items)
    XCTAssertEqual(Queue<Int>(items: items).current, 1)
  }
  
  func testRemoveAll() {
    populate()
    XCTAssertFalse(queue.isEmpty)
    queue.removeAll()
    XCTAssertTrue(queue.isEmpty)
    XCTAssertNil(queue.current)
  }
  
  func testLiteral() {
    let q: Queue = [1, 2, 3]
    XCTAssertEqual(q, Queue<Int>(items: [1, 2, 3]))
    XCTAssertEqual(q.current, 1)
    XCTAssertEqual(q.nextUp, [2, 3])
  }
  
  func testSequence() {
    populate()
    XCTAssertEqual(queue.map { $0 }, items)
    XCTAssertEqual(queue.filter { $0 > 4}, [5, 6, 7, 8])
  }
  
  func testAppend() {
    try! queue.append(3)
    XCTAssertEqual(queue.current, 3)
    XCTAssertEqual(queue.nextUp, [])
    
    try! queue.append(4)
    XCTAssertEqual(queue.current, 3)
    XCTAssertEqual(queue.items, [3, 4])
    XCTAssertEqual(queue.nextUp, [4])
  }
  
  func testAppendAlready() {
    try! queue.append(1)
    do {
      try queue.append(items: [1, 2, 3])
    } catch {
      switch error {
      case QueueError.alreadyInQueue:
        break
      default:
        XCTFail("should be expected error")
      }
    }
    XCTAssertEqual(queue.items, [1, 2, 3])
  }
  
  func testPrepend() {
    XCTAssertEqual(try! queue.prepend(4), 4)
    XCTAssertEqual(queue.current, 4)
    XCTAssertEqual(queue.nextUp, [])
    
    XCTAssertEqual(try! queue.prepend(3), 3)
    XCTAssertEqual(queue.current, 4)
    XCTAssertEqual(queue.items, [3, 4])
    XCTAssertEqual(queue.nextUp, [])
    XCTAssertNil(queue.forward())
  }
  
  func testPrependAlready() {
    try! queue.append(3)
    XCTAssertEqual(queue.prepend(items: [1, 2, 3]), [2, 1])
    XCTAssertEqual(queue.items, [1, 2, 3])
  }
  
  func testSkipTo() {
    XCTAssertThrowsError(try queue.skip(to: 6)) { er in
      switch er {
      case QueueError.notInQueue:
        break
      default:
        XCTFail()
      }
    }

    populate()
    
    try! queue.skip(to: 6)
    
    XCTAssertEqual(queue.current, 6)
    XCTAssertEqual(queue.nextUp, [7, 8])
    XCTAssertEqual(queue.items, items)
    
    XCTAssertEqual(queue.forward(), 7)
    XCTAssertEqual(queue.backward(), 6)
    
    XCTAssertEqual(queue.nextUp, [7, 8])
    
    try! queue.skip(to: 3)
    
    XCTAssertEqual(queue.current, 3)
    XCTAssertEqual(queue.nextUp, [4, 5, 6, 7, 8])
    XCTAssertEqual(queue.items, items)
  }
  
  func testNextUp() {
    XCTAssertEqual(queue.nextUp, [])
    
    do {
      populate()
      
      XCTAssertEqual(queue.current, 1)
      XCTAssertEqual(queue.forward(), 2)
      
      XCTAssertEqual(queue.nextUp, [3,4,5,6,7,8])
    }
  }
  
  func testForward() {
    XCTAssertNil(queue.forward())
    
    populate()
    XCTAssertEqual(queue.current, 1)

    let now = 4
    for i in 2...now {
      XCTAssertEqual(queue.forward(), i)
    }
    XCTAssertEqual(queue.current, now)
  }
  
  func testBackward() {
    XCTAssertNil(queue.backward())
    
    populate()
    XCTAssertEqual(queue.current, 1)
    
    XCTAssertNil(queue.backward())
    
    let now = 4
    for i in 2...now {
      XCTAssertEqual(queue.forward(), i)
    }
    XCTAssertEqual(queue.current, now)
    
    XCTAssertEqual(queue.backward(), 3)
  }
  
  func testRemove() {
    XCTAssertThrowsError(try queue.remove(11), "should throw") { er in
      switch er {
      case QueueError.notInQueue:
        break
      default:
        XCTFail()
      }
    }
    
    do {
      populate()
      
      for i in 1...8 { try! queue.remove(i) }
      
      XCTAssertNil(queue.forward())
      XCTAssertNil(queue.backward())
      for i in 1...8 { XCTAssertFalse(queue.contains(i)) }
      XCTAssertTrue(queue.isEmpty)
    }
    
    do {
      populate()
      try! queue.skip(to: 4)
      
      try! queue.remove(1)
      
      XCTAssertFalse(queue.contains(1))
    }
  }
  
  func testPrependItems() {
    XCTAssertEqual(queue.prepend(items: [4, 5, 6]), [6, 5, 4])
    XCTAssertEqual(queue.current, 6)
    
    XCTAssertEqual(queue.prepend(items: [1, 2, 3]), [3, 2, 1])
    XCTAssertEqual(queue.current, 6)
    
    XCTAssertEqual(queue.items, [1, 2, 3, 4, 5, 6])
    
    XCTAssertThrowsError(try queue.prepend(1), "should throw") { er in
      switch er {
      case QueueError.alreadyInQueue:
        break
      default:
        XCTFail()
      }
    }
  }
  
  func testAppendItems() {
    try! queue.append(items: [1, 2, 3])
    XCTAssertEqual(queue.current, 1)
    
    XCTAssertThrowsError(try queue.append(1), "should throw") { er in
      switch er {
      case QueueError.alreadyInQueue:
        break
      default:
        XCTFail()
      }
    }
    
    try! queue.append(5)
    XCTAssertEqual(queue.current, 1)
    
    try! queue.skip(to: 5)
    XCTAssertEqual(queue.current, 5)
  }
}
