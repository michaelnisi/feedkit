//
//  common.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import XCTest
import Skull
@testable import FeedKit

func schemaForClass(aClass: AnyClass!) -> String {
  let bundle = NSBundle(forClass: aClass)
  return bundle.pathForResource("schema", ofType: "sql")!
}

private func ttl() -> CacheTTL {
  return CacheTTL(short: 3600, medium: 3600 * 24, long: 3600 * 24 * 3)
}

private func cacheURL(name: String) -> NSURL {
  let fm = NSFileManager.defaultManager()
  let dir = try! fm.URLForDirectory(
    .CachesDirectory,
    inDomain: .UserDomainMask,
    appropriateForURL: nil,
    create: true
  )
  return NSURL(string: name, relativeToURL: dir)!
}

func freshCache(aClass: AnyClass!, ttl: CacheTTL = ttl()) -> Cache {
  let name = "feedkit.test.db"
  let url = cacheURL(name)

  let fm = NSFileManager.defaultManager()
  let exists = fm.fileExistsAtPath(url.path!)
  if exists {
    try! fm.removeItemAtURL(url)
  }
  let schema = schemaForClass(aClass)
  return try! Cache(
    schema: schema,
    ttl: ttl,
    url: nil
  )
}

func destroyCache(cache: Cache) throws {
  if let url = cache.url {
    let fm = NSFileManager.defaultManager()
    try fm.removeItemAtURL(url)
    XCTAssertFalse(fm.fileExistsAtPath(url.path!), "should remove database file")
  }
}

func JSONFromFileAtURL(url: NSURL) throws -> [[String:AnyObject]] {
  let data = NSData(contentsOfURL: url)
  let json = try NSJSONSerialization.JSONObjectWithData(data!, options: .AllowFragments)
  if let dict = json as? [String: AnyObject] {
    return dict.isEmpty ? [] : [dict]
  } else if let arr = json as? [[String:AnyObject]] {
    return arr
  }
  throw FeedKitError.UnexpectedJSON
}

func feedsFromFileAtURL(url: NSURL) throws -> [Feed] {
  let json = try JSONFromFileAtURL(url)
  let (errors, feeds) = feedsFromPayload(json)
  XCTAssert(errors.isEmpty, "should return no errors")
  return feeds
}

func entriesFromFileAtURL(url: NSURL) throws -> [Entry] {
  let json = try JSONFromFileAtURL(url)
  let (errors, entries) = entriesFromPayload(json)
  XCTAssertEqual(errors.count, 9, "should contain 9 invalid entries")
  return entries
}

/// A newly created entry specified by name.
/// 
/// - Parameter name: An arbitary name making sense in the test domain.
/// - Returns: The named entry.
/// - Throws: This, of course, throws if the requested name is unknown.
func entryWithName(name: String) throws -> Entry {
  switch name {
    case "thetalkshow":
      let feed = "http://daringfireball.net/thetalkshow/rss"
      let id = "http://daringfireball.net/thetalkshow/2015/10/17/ep-133"
      let link = "http://daringfireball.net/thetalkshow/2015/10/17/ep-133"
      
      let enclosure = Enclosure(
        url: "http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3",
        length: 110282964,
        type: EnclosureType(withString: "audio/mpeg")
      )
      
      let updated = NSDate(timeIntervalSince1970: 1445110501000 / 1000)
      
      let guid = entryGUID(feed, id: id, updated: updated)
      
      return Entry(
        author: "Daring Fireball / John Gruber",
        enclosure: enclosure,
        duration: "02:33:05",
        feed: feed,
        feedTitle: nil,
        guid: guid,
        id: id,
        img: "http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png,",
        link: link,
        subtitle: "Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.",
        summary: "Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.",
        title: "Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell",
        ts: nil,
        updated: updated
    )
    default:
      throw FeedKitError.NotAnEntry
  }
}

func feedWithName(name: String) throws -> Feed {
  switch name {
  case "thetalkshow":
    return Feed(
      author: "Daring Fireball / John Gruber",
      iTunesGuid: 528458508,
      images: FeedImages(
        img: "http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg",
        img100: nil,
        img30: nil,
        img60: nil,
        img600: nil
      ),
      link: nil,
      summary: "The director’s commentary track for Daring Fireball.",
      title: "The Talk Show With John Gruber",
      ts: NSDate(),
      uid: nil,
      updated: NSDate(timeIntervalSince1970: 1445110501000 / 1000),
      url: "http://daringfireball.net/thetalkshow/rss"
    )
  case "roderickontheline":
    return Feed(
      author: "Merlin Mann",
      iTunesGuid: 471418144,
      images: FeedImages(
        img: "http://www.merlinmann.com/storage/rotl/rotl-logo-300-sq.jpg",
        img100: nil,
        img30: nil,
        img60: nil,
        img600: nil
      ),
      link: nil,
      summary: nil,
      title: "Roderick on the Line",
      ts: nil,
      uid: nil,
      updated: NSDate(timeIntervalSince1970: 0),
      url: "http://feeds.feedburner.com/RoderickOnTheLine"
    )
  default:
    throw FeedKitError.NotAFeed
  }
}
