//
//  SQLFormatter.swift
//  FeedKit
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// MARK: - Stateful Formatting

/// `SQLFormatter` is a base class for formatters that produce SQL statements
/// from FeedKit structures, creating and transforming SQLite rows into FeedKit
/// core objects.
///
/// **These formatters should not return explicit transactions, leave that to
/// the call site, where the user knows the context.**
///
/// Remember to respect [SQLite limits](https://www.sqlite.org/limits.html) when
/// using this class. Some of its functions might exceed the maximum depth of an
/// SQLite expression tree. Here's the deal: basically every time an array of
/// identifiers is longer than 1000, we have to slice it down.
///
/// ```
/// Cache.slice(elements:, with:)
/// ```
class SQLFormatter {
  
  lazy var df: DateFormatter = {
    let df = DateFormatter()
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()
  
  /// Returns now as an SQLite datetime timestamp string.
  func now() -> String {
    return df.string(from: Date())
  }
  
  /// Returns a date from an SQLite datetime timestamp string.
  ///
  /// - Parameter string: A `'yyyy-MM-dd HH:mm:ss'` formatted timestamp.
  ///
  /// - Returns: A date or `nil`.
  func date(from string: String?) -> Date? {
    guard let str = string else {
      return nil
    }
    return df.date(from: str)
  }
  
  /// Produces an SQL formatted strings.
  func SQLString(from obj: Any?) -> String {
    switch obj {
    case nil:
      return "NULL"
    case is Int, is Double:
      return "\(obj!)"
    case let value as String:
      return SQLFormatter.SQLString(from: value)
    case let value as Date:
      return "'\(df.string(from: value))'"
    case let value as URL:
      return SQLFormatter.SQLString(from: value.absoluteString)
    default:
      return "NULL"
    }
  }
  
  /// The SQL standard specifies that single-quotes, and double quotes for that
  /// matter in strings are escaped by putting two single quotes in a row.
  static func SQLString(from string: String) -> String {
    let s = string.replacingOccurrences(
      of: "'",
      with: "''",
      options: String.CompareOptions.literal,
      range: nil
    )
    
    return "'\(s)'"
  }

}

extension SQLFormatter {
  
  /// If possible, returns an iTunes item from a database table `row`.
  ///
  /// - Parameters:
  ///   - row: The database row potentially containing an iTunes item.
  ///   - url: Optionally, the URL of the feed to associate with the item.
  static func iTunesItem(from row: SkullRow, url: FeedURL?) -> ITunesItem? {
    guard
      let feedURL = url ?? row["feed_url"] as? String ?? row["url"] as? String,
      let iTunesID = row["itunes_guid"] as? Int,
      let img100 = row["img100"] as? String,
      let img30 = row["img30"] as? String,
      let img60 = row["img60"] as? String,
      let img600 = row["img600"] as? String else {
      return nil
    }
    
    return ITunesItem(
      url: feedURL,
      iTunesID: iTunesID,
      img100: img100,
      img30: img30,
      img60: img60,
      img600: img600
    )
  }
  
}

