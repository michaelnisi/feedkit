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
  ///   - probe: A reachability probe to check this service.
  public init(
    cache: FeedCaching,
    svc: MangerService,
    queue: OperationQueue,
    probe: Reaching
    ) {
    self.cache = cache
    self.svc = svc
    
    super.init(queue: queue, probe: probe)
  }
  
}

// MARK: - Browsing

extension FeedRepository: Browsing {
  
  public func integrate(
    iTunesItems: [ITunesItem],
    completionBlock: ((_ error: Error?) -> Void)?
  ) -> Void {
    os_log("integrating iTunes items: %{public}@",
           log: Browse.log, type: .debug, iTunesItems)
    
    let cache = self.cache
    queue.addOperation {
      let q = OperationQueue.current?.underlyingQueue ?? DispatchQueue.global()
      do {
        try cache.integrate(iTunesItems: iTunesItems)
      } catch {
        q.async { completionBlock?(error) }
      }
      q.async { completionBlock?(nil) }
    }
  }
  
  public func feeds(
    _ urls: [String],
    feedsBlock: @escaping (_ feedsError: Error?, _ feeds: [Feed]) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)
    
    let r = reachable()
    let uri = urls.count == 1 ? urls.first : nil
    let ttl = timeToLive(
      uri,
      force: false,
      reachable: r,
      status: svc.client.status,
      ttl: CacheTTL.short
    )
    
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    op.reachable = r
    op.ttl = ttl
    
    queue.addOperation(op)
    
    return op
  }
  
  public func entries(satisfying provider: Operation) -> Operation {
    let reach = ReachHostOperation(host: svc.client.host)
    let fetchFeeds = FeedsOperation(cache: cache, svc: svc)
    let fetchEntries = EntriesOperation(cache: cache, svc: svc)
    
    fetchFeeds.addDependency(reach)
    fetchFeeds.addDependency(provider)
    
    fetchEntries.addDependency(reach)
    fetchEntries.addDependency(provider)
    fetchEntries.addDependency(fetchFeeds)
    
    queue.addOperation(fetchEntries)
    queue.addOperation(fetchFeeds)
    queue.addOperation(reach)
    
    return fetchEntries
  }
  
  public func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let fetchEntries = EntriesOperation(cache: cache, svc: svc, locators: locators)
    
    let r = reachable()
    let uri = locators.count == 1 ? locators.first?.url : nil
    let ttl = timeToLive(
      uri,
      force: force,
      reachable: r,
      status: svc.client.status,
      ttl: CacheTTL.short
    )
    
    fetchEntries.entriesBlock = entriesBlock
    fetchEntries.entriesCompletionBlock = entriesCompletionBlock
    fetchEntries.reachable = r
    fetchEntries.ttl = ttl
    
    // We have to get the according feeds, before we can request their entries,
    // because we cannot update entries of uncached feeds. Providing a place to
    // composite operations, like this, is an advantage of interposing
    // repositories, compared to exposing operations directly.
    
    let urls = locators.map { $0.url }
    
    let fetchFeeds = FeedsOperation(cache: cache, svc: svc, urls: urls)
    
    fetchFeeds.ttl = CacheTTL.forever
    fetchFeeds.reachable = r
    
    fetchFeeds.feedsBlock = { error, feeds in
      if let er = error {
        os_log("could not fetch feeds: %{public}@", log: Browse.log, type: .error,
               String(reflecting: er))
      }
    }
    
    fetchFeeds.feedsCompletionBlock = { error in
      if let er = error {
        os_log("could not fetch feeds: %{public}@", log: Browse.log, type: .error,
               String(reflecting: er))
      }
    }
    
    assert(fetchFeeds.ttl == CacheTTL.forever)
    
    fetchEntries.addDependency(fetchFeeds)

    queue.addOperation(fetchEntries)
    queue.addOperation(fetchFeeds)
    
    return fetchEntries
  }
  
  public func entries(
    _ locators: [EntryLocator],
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation {
    return self.entries(
      locators,
      force: false,
      entriesBlock: entriesBlock,
      entriesCompletionBlock: entriesCompletionBlock
    )
  }

}
