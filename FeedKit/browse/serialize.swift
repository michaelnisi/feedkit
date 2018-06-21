//
//  serialize.swift - transform things into other things
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

/// Not much logging is done here, only the two main functions serializing
/// feed and entry payloads, for inspecting the original payloads served.
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "serialize")

/// Returns a new URL string with lowercased scheme and host, the path remains
/// as it is. Here‘s the spec: https://tools.ietf.org/html/rfc3986
///
/// - Parameter string: The URL string to use.
///
/// - Returns: RFC 3986 compliant URL or `nil`.
func lowercasedURL(string: String) -> String? {
  guard var c = URLComponents(string: string), let host = c.host else {
    return nil
  }
  c.host = host.lowercased()
  return c.string
}

/// Returns feed URL from `json` if is contains one. Unfortunately, *fanboy* and
/// *manger* APIs are naming the feed URL property differently.
fileprivate func feedURL(from json: [String : Any]) -> FeedURL? {
  guard
    let rawURL = json["url"] as? String ?? json["feed"] as? String,
    let url = lowercasedURL(string: rawURL) else {
    return nil
  }
  
  return url
}

/// A collection of serialization functions.
struct serialize {
  
  /// Create Cocoa time interval from JavaScript time.
  ///
  /// As `NSJSONSerialization` returns Foundation objects, the input for this needs
  /// to be `NSNumber`, especially to ensure we are OK on 32 bit as well.
  ///
  /// - Parameter value: A timestamp from JSON in milliseconds.
  ///
  /// - Returns: The respective time interval (in seconds):
  static func timeIntervalFromJS(_ value: NSNumber) -> TimeInterval {
    return Double(truncating: value) / 1000 as TimeInterval
  }
  
  /// Create an iTunes item from a JSON `payload` for the feed at `url`. All
  /// properties: guid, img100, img30, img60, and img600 must be present.
  static func makeITunesItem(url: FeedURL, payload: [String : Any]) -> ITunesItem? {
    guard
      let guid = payload["guid"] as? Int,
      let img100 = payload["img100"] as? String,
      let img30 = payload["img30"] as? String,
      let img60 = payload["img60"] as? String,
      let img600 = payload["img600"] as? String else {
      return nil
    }
    
    return ITunesItem(
      url: url,
      iTunesID: guid,
      img100: img100,
      img30: img30,
      img60: img60,
      img600: img600
    )
  }
  
  /// Arbitrary date watershed, 1990-01-01 00:00:00 +0000.
  static var watershed = TimeInterval(31557600 * 20)
  
  /// Create and return a foundation date from a universal timestamp in
  /// milliseconds, contained in a a dictionary, matching a specified key. If the
  /// dictionary does not contain a value for the key or the value cannot be used
  /// to create a date `nil` is returned.
  ///
  /// - Parameters:
  ///   - dictionary: The dictionary to look at.
  ///   - key: The key of a potential UTC timestamp in milliseconds.
  ///   - ts: The oldest valid date.
  ///
  /// - Returns: The date or `nil`.
  static func date(
    from dictionary: [String : Any],
    forKey key: String,
    newer ts: TimeInterval = serialize.watershed
  ) -> Date? {
    guard let ms = dictionary[key] as? NSNumber else {
      return nil
    }
    let s = serialize.timeIntervalFromJS(ms)
    
    guard s > ts else { // > 1989
      os_log("ignoring invalid date in %{public}@", log: log, dictionary)
      return nil
    }
    
    return Date(timeIntervalSince1970: s)
  }
  
  /// Tries to create and return a feed from the specified dictionary.
  ///
  /// - Parameter json: The JSON dictionary to use.
  ///
  /// - Returns: The resulting feed object from the payload.
  ///
  /// - Throws: If the required properties are missing or invalid this throws
  /// `FeedKitError.invalidFeed(reason:)`.
  static func feed(from json: [String : Any]) throws -> Feed {
    guard let url = feedURL(from: json) else {
      throw FeedKitError.invalidFeed(reason: "feed missing")
    }
    
    guard let title = json["title"] as? String else {
      throw FeedKitError.invalidFeed(reason: "title missing: \(url)")
    }
    
    let author = json["author"] as? String
    
    // Apparantly, people spam the iTunes author property. To ignore them, we
    // limit its length.
    
    if let a = author, a.count > 64 {
      throw FeedKitError.invalidFeed(reason: "excessive author: \(url)")
    }
    
    let iTunes = serialize.makeITunesItem(url: url, payload: json)
    let image = json["image"] as? String
    let link = json["link"] as? String
    let summary = json["summary"] as? String
    let originalURL = json["originalURL"] as? String
    let updated = serialize.date(from: json, forKey: "updated")
  
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
      url: url
    )
  }
  
  /// Create an array of feeds from a JSON payload.
  ///
  /// It should be noted, relying on our service written by ourselves, there
  /// shouldn't be any errors, handling these should be a mere safety measure for
  /// more transparent debugging. Doublets are filtered out and reported.
  ///
  /// - Parameter dicts: A JSON array of dictionaries to serialize.
  ///
  /// - Returns: A tuple of errors and feeds.
  ///
  /// - Throws: Doesn't throw but collects its errors and returns them in the
  /// result tuple alongside the feeds.
  static func feeds(from dicts: [[String : Any]]) -> ([Error], [Feed]) {
    os_log("serializing feeds: %{public}@", log: log, type: .debug, dicts)
    
    var errors = [Error]()
    let feeds = dicts.reduce([Feed]()) { acc, dict in
      do {
        let f = try serialize.feed(from: dict)
        guard !acc.contains(f) else {
          if #available(iOS 10.0, *) {
            // Feed doublets can occure when iTunes search returns objects with
            // different GUIDs, but with equal feed URLs.
            os_log("feed doublet: %{public}@", log: log,  type: .error,
                   String(describing: f))
          }
          return acc
        }
        return acc + [f]
      } catch let er {
        errors.append(er)
        return acc
      }
    }
    return (errors, feeds)
  }
  
  /// Create an enclosure from a JSON payload.
  static func enclosure(from json: [String : Any]) throws -> Enclosure? {
    guard let url = json["url"] as? String else {
      throw FeedKitError.invalidEnclosure(reason: "missing url")
    }
    guard let t = json["type"] as? String else {
      throw FeedKitError.invalidEnclosure(reason: "missing type")
    }
    
    var length: Int?
    if let lenstr = json["length"] as? String {
      length = Int(lenstr)
    }
    let type = EnclosureType(withString: t)
    
    return Enclosure(
      url: url,
      length: length,
      type: type
    )
  }
  
  /// Tries to create and return an entry from the specified dictionary.
  ///
  /// To create a valid entry feed, title, and id are required. Also the updated
  /// timestamp is relevant, but if this isn't present, its value will be set to
  /// zero (1970-01-01 00:00:00 UTC).
  ///
  /// - Parameters:
  ///   - json: The JSON dictionary to serialize.
  ///   - podcast: Flag that having an enclosure is required.
  ///
  /// - Returns: The valid entry.
  ///
  /// - Throws: Might throw `FeedKitError.InvalidEntry` if `"feed"`, `"title"`, or
  /// `"id"` are missing from the dictionary. If enclosure is required, `podcast`
  /// is `true`, and not present, also invalid entry is thrown.
  static func entry(from json: [String : Any], podcast: Bool = true) throws -> Entry {
    guard let feed = json["url"] as? String else {
      throw FeedKitError.invalidEntry(reason: "missing feed")
    }
    guard let title = json["title"] as? String else {
      throw FeedKitError.invalidEntry(reason: "missing title: \(feed)")
    }
    guard let guid = json["id"] as? String else {
      throw FeedKitError.invalidEntry(reason: "missing id: \(feed)")
    }

    let updated = serialize.date(from: json, forKey: "updated") ??
      Date(timeIntervalSince1970: 0)
    
    let author = json["author"] as? String
    let duration = json["duration"] as? Int
    let image = json["image"] as? String
    let link = json["link"] as? String
    let originalURL = json["originalURL"] as? String
    let subtitle = json["subtitle"] as? String
    let summary = json["summary"] as? String
    
    var enclosure: Enclosure?
    if let enc = json["enclosure"] as? [String : AnyObject] {
      enclosure = try serialize.enclosure(from: enc)
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
  /// - Parameters:
  ///   - dicts: An array of—presumably—entry dictionaries.
  ///   - podcast: A flag to require an enclosure for each entry.
  ///
  /// - Returns: A tuple containing errors and entries.
  ///
  /// - Throws: This function doesn't throw because it collects the entries it
  /// successfully serialized and returns them, additionally it also collects
  /// the occuring errors and returns them too. May its user act wisely!
  static func entries(from dicts: [[String: Any]], podcast: Bool = true) -> ([Error], [Entry]) {
    os_log("serializing entries: %{public}@", log: log, type: .debug, dicts)
    
    var errors = [Error]()
    let entries = dicts.reduce([Entry]()) { acc, dict in
      do {
        let entry = try serialize.entry(from: dict, podcast: podcast)
        return acc + [entry]
      } catch let er {
        errors.append(er)
        return acc
      }
    }
    return (errors, entries)
  }
  
}
