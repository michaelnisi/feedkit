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

func schemaForClass(_ aClass: AnyClass!) -> String {
  let bundle = Bundle(for: aClass)
  return bundle.path(forResource: "schema", ofType: "sql")!
}

private func cacheURL(_ name: String) -> URL {
  let fm = FileManager.default
  let dir = try! fm.url(
    for: .cachesDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  )
  return URL(string: name, relativeTo: dir)!
}

func freshCache(_ aClass: AnyClass!) -> Cache {
  let name = "feedkit.test.db"
  let url = cacheURL(name)

  let fm = FileManager.default
  let exists = fm.fileExists(atPath: url.path)
  if exists {
    try! fm.removeItem(at: url)
  }
  let schema = schemaForClass(aClass)
  return try! Cache(
    schema: schema,
    url: nil
  )
}

func destroyCache(_ cache: Cache) throws {
  if let url = cache.url {
    let fm = FileManager.default
    try fm.removeItem(at: url)
    XCTAssertFalse(fm.fileExists(atPath: url.path), "should remove database file")
  }
}

func JSONFromFileAtURL(_ url: URL) throws -> [[String : Any]] {
  let data = try? Data(contentsOf: url)
  let json = try JSONSerialization.jsonObject(with: data!, options: .allowFragments)
  if let dict = json as? [String : Any] {
    return dict.isEmpty ? [] : [dict]
  } else if let arr = json as? [[String : Any]] {
    return arr
  }
  throw FeedKitError.unexpectedJSON
}

func feedsFromFileAtURL(_ url: URL) throws -> [Feed] {
  let json = try JSONFromFileAtURL(url as URL)
  let (errors, feeds) = feedsFromPayload(json)
  XCTAssert(errors.isEmpty, "should return no errors")
  return feeds
}

func entriesFromFileAtURL(_ url: URL) throws -> [Entry] {
  let json = try JSONFromFileAtURL(url as URL)
  let (errors, entries) = entriesFromPayload(json)
  XCTAssertEqual(errors.count, 9, "should contain 9 invalid entries")
  return entries
}

// TODO: Use realistic guids in all tests

/// A newly created entry specified by name.
/// 
/// - Parameter name: An arbitary name making sense in the test domain.
/// - Returns: The named entry.
/// - Throws: This, of course, throws if the requested name is unknown.
func entryWithName(_ name: String) throws -> Entry {
  switch name {
    case "thetalkshow":
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
        feedTitle: nil,
        guid: guid,
        img: "http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png,",
        link: link,
        originalURL: nil,
        subtitle: "Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.",
        summary: "Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.",
        title: "Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell",
        ts: nil,
        updated: updated
      )
    default:
      throw FeedKitError.notAnEntry
  }
}

func feedWithName(_ name: String) throws -> Feed {
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
      originalURL: nil,
      summary: "The director’s commentary track for Daring Fireball.",
      title: "The Talk Show With John Gruber",
      ts: Date(),
      uid: nil,
      updated: Date(timeIntervalSince1970: 1445110501000 / 1000),
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
      originalURL: nil,
      summary: nil,
      title: "Roderick on the Line",
      ts: nil,
      uid: nil,
      updated: Date(timeIntervalSince1970: 0),
      url: "http://feeds.feedburner.com/RoderickOnTheLine"
    )
  default:
    throw FeedKitError.notAFeed
  }
}
