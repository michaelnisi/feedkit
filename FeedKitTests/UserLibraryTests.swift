//
//  UserLibraryTests.swift
//  FeedKit
//
//  Created by Michael on 9/8/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

class UserLibraryTests: XCTestCase {
  
  private var user: UserLibrary!
  private var cache: UserCache!

  private var browserCache: FeedCaching!

  override func setUp() {
    super.setUp()

    let cache = Common.makeUserCache()

    let browser = Common.makeBrowser()
    browserCache = browser.cache

    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    
    let user = UserLibrary.init(cache: cache, browser: browser, queue: queue)

    XCTAssert(user.isEmpty)
    XCTAssertFalse(user.isBackwardable)
    XCTAssertFalse(user.isForwardable)
    
    self.user = user
    self.cache = cache
  }

  override func tearDown() {
    user = nil
    cache = nil
    super.tearDown()
  }

  // Specifying APIs.

  private var library: Subscribing { return user }
  private var queue: Queueing { return user }
  
}

// MARK: - Subscribing

extension UserLibraryTests {
  
  func testAdd() {
    do {
      let exp = self.expectation(description: "subscribing empty list")
      
      library.add(subscriptions: []) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      let exp = self.expectation(description: "subscribing")

      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      
      library.add(subscriptions: subscriptions) { error in
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }

  func testSubscribe() {
    let exp = self.expectation(description: "subscribing to a feed")

    let entry = Common.makeEntry(name: .gruber)
    let feed = Common.makeFeed(name: .gruber)

    try! browserCache.update(feeds: [feed])
    try! browserCache.update(entries: [entry])

    let queue = self.queue
    let library = self.library

    queue.enqueue(entries: [entry]) { enqueued, error in
      XCTAssertNil(error)
      XCTAssert(enqueued.contains(entry))
      XCTAssertFalse(queue.isEmpty)

      queue.dequeue(entry: entry) { dequeued, error in
        XCTAssertNil(error)
        XCTAssert(dequeued.contains(entry))
        XCTAssert(queue.isEmpty)

        library.subscribe(feed) { error in
          XCTAssertNil(error)
          XCTAssert(library.has(subscription: feed.url))
          XCTAssert(queue.contains(entry: entry))

          library.unsubscribe(feed.url) { error in
            XCTAssertNil(error)
            XCTAssertFalse(library.has(subscription: feed.url))
            XCTAssertFalse(queue.contains(entry: entry))

            library.subscribe(feed) { error in
              XCTAssertNil(error)
              XCTAssert(library.has(subscription: feed.url))
              XCTAssert(queue.contains(entry: entry))

              exp.fulfill()
            }
          }
        }
      }
    }

    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }

  func testSynchronize() {
    let entry = Common.makeEntry(name: .gruber)
    let loc = EntryLocator(entry: entry)
    let q = Queued.init(entry: loc)

    try! cache.add(queued: [q])

    let queue = self.queue

    XCTAssertFalse(queue.contains(entry: entry))

    do {
      let exp = self.expectation(description: "synchronizing")

      library.synchronize { error in
        switch error {
        case .none:
          break
        case let er as QueueingError:
          switch er {
          case .outOfSync:
            // We have added q to the cache without committing the queue.
            break
          }
          break
        case .some:
          XCTFail()
        }

        XCTAssert(queue.contains(entry: entry))

        exp.fulfill()
      }

      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  /// Subscribes to feed at `url` and returns subscriptions for testing.
  @discardableResult
  private func subscribe(
    _ url: String,
    addComplete: @escaping (Error?) -> Void
  ) -> [Subscription] {
    let subscriptions = [Subscription(url: url)]
    library.add(subscriptions: subscriptions, completionBlock: addComplete)
    return subscriptions
  }
  
  func testUnsubscribe() {
    let url = "http://abc.de"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing empty list")
      
      user.unsubscribe([]) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      XCTAssert(self.user.has(subscription: url))

      let exp = self.expectation(description: "unsubscribing")

      library.unsubscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        XCTAssertFalse(self.user.has(subscription: url))
      }
    }
  }
  
  func testHasSubscription() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      self.measure {
        XCTAssertTrue(user.has(subscription: url))
      }
      
    }
  }
  
  func testFeeds() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let exp = self.expectation(description: "fetching feeds")
      
      user.fetchFeeds(feedsBlock: { feeds, error in
        XCTAssertFalse(Thread.isMainThread)
        let found = feeds.first!.url

        // Not sure if we should be testing redirects here. ↑

        let wanted = "https://omny.fm/shows/monocle-24-the-urbanist/playlists/podcast.rss"
        XCTAssertEqual(found, wanted)
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
}

// MARK: - Updating

extension UserLibraryTests {
  
  func testUpdate() {
    do {
      let exp = expectation(description: "update")
      user.update { newData, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        XCTAssertFalse(newData)
        exp.fulfill()
      }
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testPrepareUpdate() {
    do {
      let locators = [EntryLocator]()
      let subscriptions = [Subscription]()
      let found = PrepareUpdateOperation.merge(locators, with: subscriptions)
      XCTAssertEqual(found, [])
    }
    
    do {
      let locators = [EntryLocator]()
      let url = "http://abc.de"
      let ts = Date.init(timeIntervalSince1970: 0)
      let subscriptions = [Subscription(url: url, ts: ts)]
      let found = PrepareUpdateOperation.merge(locators, with: subscriptions)
      let wanted = [EntryLocator(url: url, since: ts)]
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testEnqueueLatest() {
    let many = try! Common.loadEntries()
    let latest = EnqueueOperation.latest(entries: many)
    let urls = latest.map { $0.feed }
    let unique = Set(urls)
    XCTAssertEqual(unique.count, urls.count, "should be unique")
    
    let found = latest.sorted { $0.updated > $1.updated }.map { $0.title }
    let wanted = [
      "Best Of: Gloria Steinem / Carrie Brownstein",
      "Playing With Perceptions",
      "Episode Two: Amy Schumer, Jorge Ramos, and the Search for a Lost Father",
      "`Josh N Chuck\'s Hallowe\'en Spooky Scarefest",
      "Mini-Episode: Lena Dunham & Emma Stone",
      "Show 56 - Kings of Kings",
      "Episode 19: Bite Marks",
      "#319: And the Call Was Coming from the Basement",
      "Update: New Normal?",
      "Episode 12: What We Know"
    ]
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Queueing

extension UserLibraryTests {
  
  func testMissingEntries() {
    do {
      let exp = expectation(description: "initially fetching queue")
      
      user.populate(entriesBlock: { entries, error in
        XCTFail("should not call block")
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    let entries = try! Common.loadEntries()
    let entriesToQueue = Array(Set(entries.prefix(5)))
    
    do {
      let exp = expectation(description: "enqueue")
      
      user.enqueue(entries: entriesToQueue) { enqueued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { error in
        XCTAssertNil(error)
      }
    }
    
    do {
      let exp = expectation(description: "fetching queue")
      
      var acc = [Entry]()
      
      user.populate(entriesBlock: { entries, error in
        XCTAssertFalse(Thread.isMainThread)

        guard let er = error as? FeedKitError else {
          return XCTFail("should error")
        }
        
        switch er {
        case .missingEntries(let missing):
          XCTAssertEqual(missing.count, 2)

        default:
          XCTFail("should err expectedly")
        }
        
        acc.append(contentsOf: entries)
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        
        // The missing entries, self-healingly, have been removed from the
        // queue by now.
        
        XCTAssertEqual(acc, [], "should remove unavailable entries")
        
        print(acc.map { $0.enclosure?.url })
        
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
  }
  
  func testEnqueueEntry() {
    let entry = Common.makeEntry(name: .gruber)
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueueing")

    user.enqueue(entries: [entry]) { enqueued, error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.enqueue(entries: [entry]) { enqueued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error, "should not error any longer")
        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testDequeingNotEnqueued() {
    let entry = Common.makeEntry(name: .gruber)
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing not enqueued")
    
    user.dequeue(entry: entry) { dequeued, error in
      XCTAssertFalse(Thread.isMainThread)

      XCTAssertNil(error)
      XCTAssertTrue(dequeued.isEmpty)

      exp.fulfill()
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEnqueuingByUser() {
    let exp = expectation(description: "enqueueing")

    func go(_ count: Int) {
      guard count != 0 else {
        return exp.fulfill()
      }

      let entry = Common.makeEntry(name: .gruber)
      let u = self.user!

      XCTAssertFalse(u.contains(entry: entry))

      u.enqueue(entries: [entry], belonging: .user) { enqueued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        XCTAssertTrue(u.contains(entry: entry))
        XCTAssertTrue(enqueued.contains(entry), "\(count)")

        u.dequeue(entry: entry) { dequeued, error in
          XCTAssertFalse(Thread.isMainThread)
          XCTAssertNil(error)
          XCTAssertFalse(u.contains(entry: entry))
          XCTAssertTrue(dequeued.contains(entry))
          
          go(count - 1)
        }
      }
    }

    go(10)

    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testDequeueing() {
    let entry = Common.makeEntry(name: .gruber)
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing")
    
    user.enqueue(entries: [entry]) { enqueued, error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.dequeue(entry: entry) { dequeued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)

        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }

  func testDequeueingByFeed() {
    let entry = Common.makeEntry(name: .gruber)
    XCTAssertFalse(user.contains(entry: entry))

    let exp = expectation(description: "dequeueing")

    user.enqueue(entries: [entry]) { enqueued, error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)

      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.dequeue(feed: entry.feed) { dequeued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }

    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }

  func testContainsEntry() {
    let entry = Common.makeEntry(name: .gruber)
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueue")
    user.enqueue(entries: [entry]) { enqueued, error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.dequeue(entry: entry) { dequeued, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        XCTAssertFalse(self.user.contains(entry: entry))
        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testNext() {
    XCTAssertNil(user.next())
  }
  
  func testPrevious() {
    XCTAssertNil(user.previous())
  }
  
}
