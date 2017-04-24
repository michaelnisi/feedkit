//
//  serialize.swift - transform things into other things
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// TODO: Review, document, and test

/// Remove whitespace from specified string and replace it with `""` or the
/// specified string. Consecutive spaces are reduced to a single space.
///
/// - parameter string: The string to trim..
/// - parameter replacement: The string to replace whitespace with.
///
/// - returns: The trimmed string.
public func replaceWhitespaces(in string: String, with replacement: String = "") -> String {
  let ws = CharacterSet.whitespaces
  let ts = string.trimmingCharacters(in: ws)
  let cmps = ts.components(separatedBy: " ") as [String]
  return cmps.reduce("") { a, b in
    if a.isEmpty { return b }
    let tb = b.trimmingCharacters(in: ws)
    if tb.isEmpty { return a }
    return "\(a)\(replacement)\(tb)"
  }
}

/// Create Cocoa time interval from JavaScript time.
///
/// As `NSJSONSerialization` returns Foundation objects, the input for this needs
/// to be `NSNumber`, especially to ensure we are OK on 32 bit as well.
///
/// - Parameter value: A timestamp from JSON in milliseconds.
/// - Returns: The respective time interval (in seconds):
func timeIntervalFromJS(_ value: NSNumber) -> TimeInterval {
  return Double(value) / 1000 as TimeInterval
}

/// Create and return a foundation date from a universal timestamp in
/// milliseconds, contained in a a dictionary, matching a specified key. If the
/// dictionary does not contain a value for the key or the value cannot be used
/// to create a date `nil` is returned.
///
/// - Parameter dict: The dictionary to look at.
/// - Parameter key: The key of a potential UTC timestamp in milliseconds.
/// - Returns: The date or `nil`.
func date(fromDictionary dict: [String : Any], withKey key: String) -> Date? {
  guard let ms = dict[key] as? NSNumber else { return nil }
  let s = timeIntervalFromJS(ms)
  return Date(timeIntervalSince1970: s)
}

/// Create an iTunes item from a JSON payload.
func iTunesItem(from dict: [String : Any]) -> ITunesItem? {
  guard let guid = dict["guid"] as? Int else {
    return nil
  }
  
  let img100 = dict["img100"] as? String
  let img30 = dict["img30"] as? String
  let img60 = dict["img60"] as? String
  let img600 = dict["img600"] as? String

  let it = ITunesItem(
    guid: guid,
    img100: img100,
    img30: img30,
    img60: img60,
    img600: img600
  )
  
  return it
}

/// Tries to create and return a feed from the specified dictionary.
///
/// - parameter json: The JSON dictionary to use.
/// - returns: The newly create feed object.
/// - throws: If the required properties `feed` and `title` are invalid, this
/// function throws `FeedKitError.InvalidFeed`.
func feed(from json: [String : Any]) throws -> Feed {
  
  // TODO: Replace feed with url in fanboy
  
  guard let url = json["url"] as? String ?? json["feed"] as? String else {
    throw FeedKitError.invalidFeed(reason: "feed missing")
  }
  
  guard let title = json["title"] as? String else {
    throw FeedKitError.invalidFeed(reason: "title missing")
  }

  let author = json["author"] as? String
  let iTunes = iTunesItem(from: json)
  let image = json["image"] as? String
  let link = json["link"] as? String
  let summary = json["summary"] as? String
  let originalURL = json["originalURL"] as? String
  let updated = date(fromDictionary: json, withKey: "updated")
  
  // Dealing with a case, the Montauk Podcast, where iTunes returned a mixed 
  // case feed URL, we lowercase the URL.

  return Feed(
    author: author,
    iTunes: iTunes,
    image: image,
    link: link,
    originalURL: originalURL,
    summary: summary,
    title: title,
    ts: nil,
    uid: nil,
    updated: updated,
    url: url.lowercased()
  )
}

/// Create an array of feeds from a JSON payload.
///
/// It should be noted, relying on our service written by ourselves, there
/// shouldn't be any errors, handling these should be a mere safety measure for
/// more transparent debugging.
///
/// - Parameter dicts: A JSON array of dictionaries to serialize.
/// - Returns: A tuple of errors and feeds.
/// - Throws: Doesn't throw but collects its errors and returns them in the
/// result tuple alongside the feeds.
func feedsFromPayload(_ dicts: [[String : Any]]) -> ([Error], [Feed]) {
  var errors = [Error]()
  let feeds = dicts.reduce([Feed]()) { acc, dict in
    do {
      let f = try feed(from: dict)
      return acc + [f]
    } catch let er {
      errors.append(er)
      return acc
    }
  }
  return (errors, feeds)
}

/// Create an enclosure from a JSON payload.
func enclosureFromDictionary (_ dict: [String : Any]) throws -> Enclosure? {
  guard let url = dict["url"] as? String else {
    throw FeedKitError.invalidEnclosure(reason: "missing url")
  }
  guard let t = dict["type"] as? String else {
    throw FeedKitError.invalidEnclosure(reason: "missing type")
  }

  var length: Int?
  if let lenstr = dict["length"] as? String {
    length = Int(lenstr)
  }
  let type = EnclosureType(withString: t)

  return Enclosure(
    url: url,
    length: length,
    type: type
  )
}

// TODO: Update documentation

/// Tries to create and return an entry from the specified dictionary.
///
/// To create a valid entry feed, title, and id are required. Also the updated
/// timestamp is relevant, but if this isn't present, its value will be set to
/// zero (1970-01-01 00:00:00 UTC).
///
/// - Parameters:
///   - dict: The JSON dictonary to serialize.
///   - podcast: Flag that having an enclosure is required.
///
/// - Returns: The valid entry.
///
/// - Throws: Might throw `FeedKitError.InvalidEntry` if `"feed"`, `"title"`, or
/// `"id"` are missing from the dictionary. If enclosure is required, `podcast` 
/// is `true`, and not present, also invalid entry is thrown.
func entryFromDictionary (
  _ dict: [String : Any],
  podcast: Bool = true
) throws -> Entry {
  
  guard let feed = dict["url"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing feed")
  }
  guard let title = dict["title"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing title: \(feed)")
  }
  guard let guid = dict["id"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing id: \(feed)")
  }

  let updated = date(fromDictionary: dict, withKey: "updated") ??
    Date(timeIntervalSince1970: 0)

  let author = dict["author"] as? String
  let duration = dict["duration"] as? Int
  let image = dict["image"] as? String
  let link = dict["link"] as? String
  let originalURL = dict["originalURL"] as? String
  let subtitle = dict["subtitle"] as? String
  let summary = dict["summary"] as? String
  
  var enclosure: Enclosure?
  if let enc = dict["enclosure"] as? [String:AnyObject] {
    enclosure = try enclosureFromDictionary(enc)
  }
  
  if podcast {
    guard enclosure != nil else {
      throw FeedKitError.invalidEntry(reason: "missing enclosure: \(feed)")
    }
  }

  return Entry(
    author: author,
    duration: duration,
    enclosure: enclosure,
    feed: feed,
    feedImage: nil,
    feedTitle: nil,
    guid: guid,
    iTunes: nil,
    image: image,
    link: link,
    originalURL: originalURL,
    subtitle: subtitle,
    summary: summary,
    title: title,
    ts: nil,
    updated: updated
  )
}

/// Create an array of entries from a JSON payload.
///
/// - Parameter dicts: An array of—presumably—entry dictionaries.
/// - Parameter podcast: A flag to require an enclosure for each entry.
/// - Returns: A tuple containing errors and entries.
/// - Throws: This function doesn't throw because it collects the entries it
/// successfully serialized and returns them, additionally it also collects
/// the occuring errors and returns them too. May its user act wisely!
func entriesFromPayload(
  _ dicts: [[String: Any]],
  podcast: Bool = true
) -> ([Error], [Entry]) {
  var errors = [Error]()
  let entries = dicts.reduce([Entry]()) { acc, dict in
    do {
      let entry = try entryFromDictionary(dict, podcast: podcast)
      return acc + [entry]
    } catch let er {
      errors.append(er)
      return acc
    }
  }
  return (errors, entries)
}
