//
//  Common.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import XCTest
import Skull
import Patron
import MangerKit
import Ola

@testable import FeedKit

/// Common things that are helpful for testing FeedKit.
final class Common {
  private init() {}

  /// Names of mock feeds.
  enum FeedName {
    case gruber
    case roderick
  }
}

// MARK: - Making Basic Types

extension Common {
  /// Returns a random String of `length`.
  static func makeString(length: Int) -> String {
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let max = UInt32(chars.count)
    var str = ""

    for _ in 0..<length {
      let offset = Int(arc4random_uniform(max))
      let index = chars.index(chars.startIndex, offsetBy: offset)
      str += String(chars[index])
    }

    return str
  }

  static func makeITunesItem(url: String) -> ITunesItem {
    return ITunesItem(url: url, iTunesID: 123, img100: "img100",
                      img30: "img30", img60: "img60", img600: "img600")
  }
  
  static func makeFeed(name: FeedName) -> Feed {
    switch name {
    case .gruber:
      return Feed(
        author: "Daring Fireball / John Gruber",
        iTunes: ITunesItem(
          url: "http://daringfireball.net/thetalkshow/rss",
          iTunesID: 528458508,
          img100: "abc",
          img30: "def",
          img60: "ghi",
          img600: "jkl"
        ),
        image: "http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg",
        link: nil,
        originalURL: nil,
        summary: "The director’s commentary track for Daring Fireball.",
        title: "The Talk Show With John Gruber",
        ts: Date(),
        uid: nil,
        updated: Date(timeIntervalSince1970: 1445110501000 / 1000),
        url: "http://daringfireball.net/thetalkshow/rss"
      )
    case .roderick:
      return Feed(
        author: "Merlin Mann",
        iTunes: ITunesItem(
          url: "http://feeds.feedburner.com/RoderickOnTheLine",
          iTunesID: 471418144,
          img100: "abc",
          img30: "def",
          img60: "ghi",
          img600: "jkl"
        ),
        image: "http://www.merlinmann.com/storage/rotl/rotl-logo-300-sq.jpg",
        link: nil,
        originalURL: nil,
        summary: nil,
        title: "Roderick on the Line",
        ts: nil,
        uid: nil,
        updated: Date(timeIntervalSince1970: 0),
        url: "http://feeds.feedburner.com/RoderickOnTheLine"
      )
    }
  }

  static func makeEntry(name: FeedName) -> Entry {
    switch name {
    case .gruber:
      let feed = "http://daringfireball.net/thetalkshow/rss"
      let link = "http://daringfireball.net/thetalkshow/2015/10/17/ep-133"

      let enclosure = Enclosure(
        url: "http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3",
        length: 110282964,
        type: EnclosureType(withString: "audio/mpeg")
      )

      let updated = Date(timeIntervalSince1970: 1445110501000 / 1000)

      let guid = "c596b134310d499b13651fed64597de2c9931179"

      return Entry(
        author: "Daring Fireball / John Gruber",
        duration: 9185,
        enclosure: enclosure,
        feed: feed,
        feedImage: nil,
        feedTitle: nil,
        guid: guid,
        iTunes: nil,
        image: "http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png",
        link: link,
        originalURL: nil,
        subtitle: "Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.",
        summary: "Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.",
        title: "Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell",
        ts: nil,
        updated: updated
      )
    default:
      fatalError("not implemented yet")
    }
  }
  
}

// MARK: - Loading Things

extension Common {
  static func decodeFeeds(reading url: URL) throws -> [Feed] {
    let data = try! Data(contentsOf: url)
    return try JSONDecoder().decode([Feed].self, from: data)
  }

  static func decodeEntries(reading url: URL) throws -> [Entry] {
    let data = try! Data(contentsOf: url)
    return try JSONDecoder().decode([Entry].self, from: data)
  }

  /// Returns an Array of Dictionaries read and parsed from `url`.
  static func JSON(contentsOf url: URL) throws -> [[String : Any]] {
    let data = try? Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data!, options: .allowFragments)
    if let dict = json as? [String : Any] {
      return dict.isEmpty ? [] : [dict]
    } else if let arr = json as? [[String : Any]] {
      return arr
    }
    throw FeedKitError.unexpectedJSON
  }

  static func loadFeeds(url: URL) throws -> [Feed] {
    let json = try JSON(contentsOf: url as URL)
    let (errors, feeds) = serialize.feeds(from: json)
    XCTAssert(errors.isEmpty, "should return no errors")
    return feeds
  }

  static func loadEntries(url: URL? = nil) throws -> [Entry] {
    let entriesURL = url ?? {
      Bundle.module.url(forResource: "entries", withExtension: "json")!
    }()
    let json = try JSON(contentsOf: entriesURL)
    let (errors, entries) = serialize.entries(from: json)
    XCTAssertEqual(errors.count, 9, "should contain 9 invalid entries")
    return entries
  }
}

// MARK: - FeedCaching

extension Common {
  static var bundle: Bundle {
    class Stooge {}
    return Bundle(for: type(of: Stooge()))
  }

  /// Returns feeds from a file in this bundle with the matching `name` without
  /// extension.
  static func feedsFromFile(named name: String = "feeds") throws -> [Feed] {
    let feedsURL = Bundle.module.url(forResource: name, withExtension: "json")!
    
    return try loadFeeds(url: feedsURL)
  }

  /// Populates `cache` with data from common test files and returns a tuple
  /// with the population of feeds and entries.
  static func populate(cache: FeedCaching) throws -> ([Feed], [Entry]) {
    let feeds = try! feedsFromFile()
    try! cache.update(feeds: feeds)

    let entries = try! loadEntries()
    try! cache.update(entries: entries)

    return (feeds, entries)
  }
}

// MARK: - Making Services

extension Common {
  static func makeManger(url: String = "http://localhost:8384") -> Manger {
    let conf = URLSessionConfiguration.default
    conf.httpShouldUsePipelining = false
    conf.requestCachePolicy = .reloadIgnoringLocalCacheData
    let session = URLSession(configuration: conf)

    let client = Patron(URL: URL(string: url)!, session: session)

    return Manger(client: client)
  }
}

// MARK: Making Complex Things

extension Common {
  private static func makeCacheURL(string: String) -> URL {
    let fm = FileManager.default
    let dir = try! fm.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return URL(string: string, relativeTo: dir)!
  }

  static func makeCache() -> FeedCache {
    let name = "ink.codes.feedkit.test.cache.db"
    let url = makeCacheURL(string: name)

    let fm = FileManager.default
    let exists = fm.fileExists(atPath: url.path)
    if exists {
      try! fm.removeItem(at: url)
    }

    return try! FeedCache(schema: cacheURL.path, url: nil)
  }

  static func makeUserCache() -> UserCache {
    let name = "ink.codes.feedkit.test.user.db"
    let url = makeCacheURL(string: name)

    let fm = FileManager.default
    let exists = fm.fileExists(atPath: url.path)
    if exists {
      try! fm.removeItem(at: url)
    }

    return try! UserCache(schema: userURL.path, url: nil)
  }

  static func makeBrowser() -> FeedRepository {
    let cache = makeCache()
    let svc = Common.makeManger(url: "http://localhost:8384")
    return FeedRepository(cache: cache, svc: svc, queue: OperationQueue())
  }
}

// MARK: - Destroying Things

extension Common {
  static func destroyCache(_ cache: LocalCache) throws {
    if let url = cache.url {
      let fm = FileManager.default
      try fm.removeItem(at: url)
      XCTAssertFalse(fm.fileExists(atPath: url.path), "should remove database file")
    }
  }
}
