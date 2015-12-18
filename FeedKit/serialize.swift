//
//  serialize.swift - transform things received from our services
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import MangerKit

/// Remove whitespace from string and replace it with `""` or any provided string.
/// Consecutive spaces are reduced to single spaces.
/// - Parameter s: The string to trim..
/// - Parameter j: The string to replace whitespace with.
/// - Returns: The trimmed string.
func trimString(s: String, joinedByString j:String = "") -> String {
  let ws = NSCharacterSet.whitespaceCharacterSet()
  let ts = s.stringByTrimmingCharactersInSet(ws)
  let cmps = ts.componentsSeparatedByString(" ") as [String]
  return cmps.reduce("") { a, b in
    if a.isEmpty { return b }
    let tb = b.stringByTrimmingCharactersInSet(ws)
    if tb.isEmpty { return a }
    return "\(a)\(j)\(tb)"
  }
}

func timeIntervalFromJS (value: Int) -> NSTimeInterval {
  return Double(value) / 1000 as NSTimeInterval
}

func dateFromDictionary (dict: [String:AnyObject], withKey key: String) -> NSDate? {
  guard let ms = dict[key] as? Int else { return nil }
  let s = timeIntervalFromJS(ms)
  return NSDate(timeIntervalSince1970: s)
}

func FeedImagesFromDictionary(dict: [String:AnyObject]) -> FeedImages {
  let img = dict["image"] as? String
  let img100 = dict["img100"] as? String
  let img30 = dict["img30"] as? String
  let img60 = dict["img60"] as? String
  let img600 = dict["img600"] as? String
  
  return FeedImages(
    img: img,
    img100: img100,
    img30: img30,
    img60: img60,
    img600: img600
  )
}

func feedFromDictionary (dict: [String:AnyObject]) throws -> Feed {
  let author = dict["author"] as? String
  let guid =  dict["guid"] as? Int
  let link = dict["link"] as? String
  let images: FeedImages = FeedImagesFromDictionary(dict)
  let summary = dict["summary"] as? String
  guard let title = dict["title"] as? String else { throw FeedKitError.Missing(name: "title") }
  let updated = dateFromDictionary(dict, withKey: "updated")
  guard let url = dict["feed"] as? String else { throw FeedKitError.Missing(name: "url") }

  return Feed(
    author: author,
    guid: guid,
    images: images,
    link: link,
    summary: summary,
    title: title,
    ts: nil,
    uid: nil,
    updated: updated,
    url: url
  )
}

func feedsFromPayload(dicts: [[String: AnyObject]]) throws -> [Feed] {
  var errors = [ErrorType]()
  let feeds = dicts.reduce([Feed]()) { acc, dict in
    do {
      let feed = try feedFromDictionary(dict)
      return acc + [feed]
    } catch let er {
      errors.append(er)
      return acc
    }
  }
  if !errors.isEmpty {
    throw FeedKitError.Multiple(errors: errors)
  }
  return feeds
}

func enclosureFromDictionary (dict: [String:AnyObject]) throws -> Enclosure? {
  guard let url = dict["url"] as? String else {
    throw FeedKitError.Missing(name: "url")
  }
  var length: Int?
  if let lenstr = dict["length"] as? String {
    length = Int(lenstr)
  }
  guard let t = dict["type"] as? String else {
    throw FeedKitError.Missing(name: "type")
  }
  let type = try EnclosureType(withString: t)
  
  return Enclosure(
    url: url,
    length: length,
    type: type
  )
}

func entryFromDictionary (dict: [String:AnyObject]) throws -> Entry {
  let author = dict["author"] as? String
  
  var enclosure: Enclosure?
  if let enc = dict["enclosure"] as? [String:AnyObject] {
    enclosure = try enclosureFromDictionary(enc)
  }
  
  let duration = dict["duration"] as? String
  guard let feed = dict["feed"] as? String else {
    throw FeedKitError.Missing(name: "feed")
  }
  guard let id = dict["id"] as? String else {
    throw FeedKitError.Missing(name: "id")
  }
  let img = dict["image"] as? String
  let link = dict["link"] as? String
  let subtitle = dict["subtitle"] as? String
  let summary = dict["summary"] as? String
  guard let title = dict["title"] as? String else {
    throw FeedKitError.Missing(name: "title")
  }
  let updated = dateFromDictionary(dict, withKey: "updated")

  return Entry(
    author: author,
    enclosure: enclosure,
    duration: duration,
    feed: feed,
    id: id,
    img: img,
    link: link,
    subtitle: subtitle,
    summary: summary,
    title: title,
    ts: nil,
    updated: updated
  )
}

func entriesFromPayload(dicts: [[String: AnyObject]]) throws -> [Entry] {
  var errors = [ErrorType]()
  let entries = dicts.reduce([Entry]()) { acc, dict in
    do {
      let entry = try entryFromDictionary(dict)
      return acc + [entry]
    } catch let er {
      errors.append(er)
      return acc
    }
  }
  if !errors.isEmpty {
    throw FeedKitError.Multiple(errors: errors)
  }
  return entries
}

func queryFromString (term: String) -> String? {
  let query = trimString(term, joinedByString: "+")
  return query.isEmpty ? nil : query
}

func queryURL (baseURL: NSURL, verb: String, term: String) -> NSURL? {
  guard let query = queryFromString(term) else { return nil }
  return NSURL(string: "\(verb)?q=\(query)", relativeToURL: baseURL)
}

func suggestionsFromTerms (terms: [String]) -> [Suggestion]? {
  guard !terms.isEmpty else { return nil }
  return terms.map { Suggestion(term: $0, ts: nil) }
}