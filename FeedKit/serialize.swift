//
//  serialize.swift - transform things into other things
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import MangerKit

/// Remove whitespace from specified string and replace it with `""` or the
/// specified string. Consecutive spaces are reduced to single spaces.
///
/// - parameter String: The string to trim..
/// - parameter joinedByString: The string to replace whitespace with.
///
/// - returns: The trimmed string.
public func trimString(_ s: String, joinedByString j: String = "") -> String {
  let ws = CharacterSet.whitespaces
  let ts = s.trimmingCharacters(in: ws)
  let cmps = ts.components(separatedBy: " ") as [String]
  return cmps.reduce("") { a, b in
    if a.isEmpty { return b }
    let tb = b.trimmingCharacters(in: ws)
    if tb.isEmpty { return a }
    return "\(a)\(j)\(tb)"
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

/// Create a feed image set from a JSON payload.
func FeedImagesFromDictionary(_ dict: [String : Any]) -> FeedImages {
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

/// Tries to create and return a feed from the specified dictionary.
///
/// - Parameter dict: The JSON dictionary to use.
/// - Returns: The newly create feed object.
/// - Throws: If the required properties `feed` and `title` are invalid, this
/// function throws `FeedKitError.InvalidFeed`.
func feedFromDictionary (_ dict: [String : Any]) throws -> Feed {
  guard let url = dict["feed"] as? String else {
    throw FeedKitError.invalidFeed(reason: "feed missing")
  }
  guard let title = dict["title"] as? String else {
    throw FeedKitError.invalidFeed(reason: "title missing")
  }

  let author = dict["author"] as? String
  let iTunesGuid =  dict["guid"] as? Int
  let link = dict["link"] as? String
  let images: FeedImages = FeedImagesFromDictionary(dict)
  let summary = dict["summary"] as? String
  let updated = date(fromDictionary: dict, withKey: "updated")

  return Feed(
    author: author,
    iTunesGuid: iTunesGuid,
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
      let feed = try feedFromDictionary(dict)
      return acc + [feed]
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

// TODO: Identify entries without relying on their id property
//
// Not all entries have ids. How can we still identify them?

/// An artifical string to globally identify an entry.
///
/// But remember that to restore an entry from thin air you'd additionally need
/// its feed URL. And even then it cannot be guranteed that you'd get the entry,
/// because the might not contain the specific entry you are looking for. Feeds
/// commonly limit the number of items they contain. In such a case, if the
/// entry cannot be found in the local or remote caches, we'd be out of luck.
func entryGUID(_ feed: String, id: String, updated: Date) -> String {
  // TODO: Remove meaningless separator
  // or replace with @@
  let str = "\(feed)%\(id)%\(updated.timeIntervalSince1970)"
  return md5Digest(str)
}

/// Tries to create and return an entry from the specified dictionary.
///
/// To create a valid entry feed, title, and id are required. Also the updated
/// timestamp is relevant, but if this isn't present, its value will be set to
/// zero (1970-01-01 00:00:00 UTC).
///
/// - Parameter dict: The JSON dictonary to serialize.
/// - Parameter podcast: Flag that having an enclosure is required.
/// - Returns: The valid entry.
/// - Throws: Throws `FeedKitError.InvalidEntry` if `"feed"`, `"title"`, or
/// `"id"` are missing from the dictionary. If enclosure is required and not
/// present, also invalid entry is thrown.
func entryFromDictionary (
  _ dict: [String : Any],
  podcast: Bool = true
) throws -> Entry {
  guard let feed = dict["feed"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing feed")
  }
  guard let title = dict["title"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing title: \(feed)")
  }
  guard let id = dict["id"] as? String else {
    throw FeedKitError.invalidEntry(reason: "missing id: \(feed)")
  }

  let updated = date(fromDictionary: dict, withKey: "updated") ??
    Date(timeIntervalSince1970: 0)

  let guid = entryGUID(feed, id: id, updated: updated)

  let author = dict["author"] as? String
  let duration = dict["duration"] as? Int
  let img = dict["image"] as? String
  let link = dict["link"] as? String
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
    enclosure: enclosure,
    duration: duration,
    feed: feed,
    feedTitle: nil,
    guid: guid,
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

/// Return a search query, actually just a trimmed string, from a string. Empty
/// strings result in `nil`.
///
/// We don't validate more, because the Search UI already restricts inputs by
/// limiting the keyboard. Take care if you pass values programmatically.
///
/// - Parameter term: Any string to be used as a search term.
/// - Returns: The search query or nil.
func queryFromString(_ term: String) -> String? {
  let query = trimString(term, joinedByString: " ")
  return query.isEmpty ? nil : query
}
