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

private func cacheURL (name: String) -> NSURL {
  let fm = NSFileManager.defaultManager()
  let dir = try! fm.URLForDirectory(
    .CachesDirectory,
    inDomain: .UserDomainMask,
    appropriateForURL: nil,
    create: true
  )
  return NSURL(string: name, relativeToURL: dir)!
}

func freshCache (aClass: AnyClass!, ttl: CacheTTL = ttl()) -> Cache {
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

func destroyCache (cache: Cache) throws {
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
  return try! feedsFromPayload(json)
}

func entriesFromFileAtURL(url: NSURL) throws -> [Entry] {
  let json = try JSONFromFileAtURL(url)
  return try! entriesFromPayload(json)
}

func entryWithName(name: String) throws -> Entry {
  switch name {
    case "thetalkshow":
      return Entry(
        author: "Daring Fireball / John Gruber",
        enclosure: Enclosure(
          url: "http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3",
          length: 110282964,
          type: try! EnclosureType(withString: "audio/mpeg")
        ),
        duration: "02:33:05",
        feed: "http://feeds.muleradio.net/thetalkshow",
        id: "http://daringfireball.net/thetalkshow/2015/10/17/ep-133",
        img: "http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png,",
        link: "http://daringfireball.net/thetalkshow/2015/10/17/ep-133",
        subtitle: "Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.",
        summary: "Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.",
        title: "Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell",
        ts: nil,
        updated: NSDate(timeIntervalSince1970: 1445110501000 / 1000)
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
      guid: 528458508,
      images: FeedImages(
        img: "http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg",
        img100: nil,
        img30: nil,
        img60: nil,
        img600: nil
      ),
      link: "http://feeds.muleradio.net/thetalkshow",
      summary: "The director’s commentary track for Daring Fireball.",
      title: "The Talk Show With John Gruber",
      ts: NSDate(),
      uid: nil,
      updated: NSDate(timeIntervalSince1970: 1445110501000 / 1000),
      url: "http://feeds.muleradio.net/thetalkshow"
    )
  case "roderickontheline":
    return Feed(
      author: "Merlin Mann",
      guid: 471418144,
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
