//
//  FeedRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 20.12.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import MangerKit
import Ola
import os.log

private let log = OSLog.disabled

/// The `FeedRepository` provides feeds and entries.
public final class FeedRepository: RemoteRepository {

  let cache: FeedCaching
  let svc: MangerService

  /// Initializes and returns a new feed repository.
  ///
  /// - Parameters:
  ///   - cache: The feed cache to use.
  ///   - svc: The remote service.
  ///   - queue: The queue to execute this repository's operations.
  public init(cache: FeedCaching, svc: MangerService, queue: OperationQueue) {
    self.cache = cache
    self.svc = svc

    super.init(queue: queue)
  }

}

// MARK: - Browsing

extension FeedRepository: Browsing {

  public func integrate(iTunesItems: [ITunesItem]) throws {
    os_log("integrating metadata: %{public}@",
           log: log, type: .info, iTunesItems)

    try cache.integrate(iTunesItems: iTunesItems)
  }
  
  public func feeds(
    _ urls: [String],
    ttl: CacheTTL,
    feedsBlock: ((_ feedsError: Error?, _ feeds: [Feed]) -> Void)?,
    feedsCompletionBlock: ((_ error: Error?) -> Void)?
  ) -> Operation {
    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)

    op.ttl = ttl
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock

    queue.addOperation(op)

    return op
  }

  public func feeds(
    _ urls: [String],
    feedsBlock: ((_ feedsError: Error?, _ feeds: [Feed]) -> Void)?,
    feedsCompletionBlock: ((_ error: Error?) -> Void)?
  ) -> Operation {
    return feeds(
      urls,
      ttl: .long,
      feedsBlock: feedsBlock,
      feedsCompletionBlock: feedsCompletionBlock
    )
  }

  public func feeds(_ urls: [String]) -> Operation {
    return feeds(urls, feedsBlock: nil, feedsCompletionBlock: nil)
  }

  private func makeFeedsOperationDependency(
    locators: [EntryLocator]? = nil,
    ttl: CacheTTL = .forever
  ) -> FeedsOperation {
    let urls = locators?.map { $0.url }

    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)

    op.ttl = ttl

    op.feedsBlock = { error, feeds in
      if let er = error {
        os_log("error while fetching feeds: %{public}@",
               log: log, type: .error, String(reflecting: er))
      }
    }

    op.feedsCompletionBlock = { error in
      if let er = error {
        os_log("could not fetch feeds: %{public}@",
               log: log, type: .error, String(reflecting: er))
      }
    }

    return op
  }

  public func entries(satisfying provider: Operation) -> Operation {
    let reach = ReachHostOperation(host: svc.client.host)

    let fetchFeeds = makeFeedsOperationDependency()
    fetchFeeds.addDependency(reach)
    fetchFeeds.addDependency(provider)

    let fetchEntries = EntriesOperation(cache: cache, svc: svc)
    fetchEntries.addDependency(provider)
    fetchEntries.addDependency(fetchFeeds)

    queue.addOperation(fetchEntries)
    queue.addOperation(fetchFeeds)
    queue.addOperation(reach)

    return fetchEntries
  }

  /// The `count` parameter just limits to the latest entry, nothing more yet.
  /// A full implementation will be covered with paging. For now, we have to
  /// work with this, relying on the cache.
  private func entries(
    _ locators: [EntryLocator],
    forcing: Bool,
    limiting count: Int = Int.max,
    entriesBlock: ((_ entriesError: Error?, _ entries: [Entry]) -> Void)? = nil,
    entriesCompletionBlock: ((_ error: Error?) -> Void)? = nil
  ) -> Operation {
    // We have to fetch according feeds, before we can request their entries,
    // because we cannot update entries of uncached feeds.

    let fetchFeeds = makeFeedsOperationDependency(locators: locators)

    let fetchEntries = EntriesOperation(cache: cache, svc: svc, locators: locators)

    if count == Int.max {
      fetchEntries.ttl = forcing ? .none : .short
    } else {
      fetchEntries.ttl = .forever
      fetchEntries.isLatest = true
    }

    fetchEntries.entriesBlock = entriesBlock
    fetchEntries.entriesCompletionBlock = entriesCompletionBlock

    fetchEntries.addDependency(fetchFeeds)

    queue.addOperation(fetchEntries)
    queue.addOperation(fetchFeeds)

    return fetchEntries
  }

  public func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: ((_ entriesError: Error?, _ entries: [Entry]) -> Void)?,
    entriesCompletionBlock: ((_ error: Error?) -> Void)?
  ) -> Operation {
    return entries(
      locators,
      forcing: force,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }

  public func entries(
    _ locators: [EntryLocator],
    entriesBlock: ((Error?, [Entry]) -> Void)?,
    entriesCompletionBlock: ((Error?) -> Void)?
  ) -> Operation {
    return self.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }

  public func latestEntry(_ url: FeedURL) -> Operation {
    os_log("fetching latest entry: %{public}@", log: log, url)
    let locators = [EntryLocator(url: url)]
    return entries(locators, forcing: false, limiting: 1)
  }

}
