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
    queue = Queue()
  }
  
  override func tearDown() {
    queue = nil
    super.tearDown()
  }
  
  lazy fileprivate var items: [Int] = {
    var items = [Int]()
    
    for i in 1...8 {
      items.append(i)
    }
    
    return items
  }()
  
  private func populate() {
    try! self.queue.add(items: items)
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
    XCTAssertEqual(queue.nextUp, [7, 8])
    XCTAssertEqual(queue.now, 6)
    XCTAssertEqual(queue.forward(), 7)
    XCTAssertEqual(queue.backward(), 7)
    
    XCTAssertEqual(queue.nextUp, [7, 8])
  }
  
  func testNextUp() {
    XCTAssertEqual(queue.nextUp, [])
    populate()
    XCTAssertEqual(queue.nextUp, items)
    
    XCTAssertEqual(queue.forward(), 1)
    
    XCTAssertEqual(queue.nextUp, [2,3,4,5,6,7,8])
  }
  
  func testForward() {
    XCTAssertNil(queue.forward())
    
    populate()
    
    let now = 4
    
    for i in 1...now {
      XCTAssertEqual(queue.forward(), i)
    }
  }
  
  func testBackward() {
    XCTAssertNil(queue.backward())
    
    populate()
    
    XCTAssertNil(queue.backward())
    
    let now = 4
    
    for i in 1...now {
      XCTAssertEqual(queue.forward(), i)
    }
    
    XCTAssertEqual(queue.now, now)
    
    for i in 1...now {
      XCTAssertEqual(queue.backward(), now - i + 1)
    }
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
    
    populate()
    
    for i in 1...8 {
      try! queue.remove(i)
    }
    
    XCTAssertNil(queue.forward())
    XCTAssertNil(queue.backward())
    
    for i in 1...8 {
      XCTAssertFalse(queue.contains(i))
    }
  }
  
  func testAdd() {
    let item = 11
    try! queue.add(item)
    
    XCTAssert(queue.contains(11))
    
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
