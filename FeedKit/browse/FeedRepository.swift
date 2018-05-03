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
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    
    
    self.cache = cache
    self.svc = svc
    
    super.init(queue: queue, probe: probe)
  }
  
}

// MARK: - Browsing

extension FeedRepository: Browsing {
  
  public func integrate(iTunesItems: [ITunesItem]) throws {
    os_log("integrating metadata: %{public}@",
           log: Browse.log, type: .debug, iTunesItems)
    try cache.integrate(iTunesItems: iTunesItems)
  }
  
  // TODO: Replace with synchronous version
  public func integrate(
    iTunesItems: [ITunesItem],
    completionBlock: ((_ error: Error?) -> Void)?
  ) -> Void {
    os_log("integrating metadata: %{public}@",
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
    feedsBlock: ((_ feedsError: Error?, _ feeds: [Feed]) -> Void)?,
    feedsCompletionBlock: ((_ error: Error?) -> Void)?
  ) -> Operation {
    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)
    
    let idea = RemoteRepository.ServiceIdea(
      reachability: probe.reach(),
      expecting: .long,
      status: svc.client.status
    )
    
    op.isOffline = idea.isOffline
    op.isAvailable = idea.isAvailable
    op.ttl = idea.ttl
    
    op.feedsBlock = feedsBlock
    op.feedsCompletionBlock = feedsCompletionBlock
    
    queue.addOperation(op)
    
    return op
  }
  
  public func feeds(_ urls: [String]) -> Operation {
    return feeds(urls, feedsBlock: nil, feedsCompletionBlock: nil)
  }
  
  private func makeFeedsOperationDependency(
    locators: [EntryLocator]? = nil,
    isOffline: Bool = false,
    isAvailable: Bool = true,
    ttl: CacheTTL = .forever
  ) -> FeedsOperation {
    let urls = locators?.map { $0.url }
    
    let op = FeedsOperation(cache: cache, svc: svc, urls: urls)
    
    op.isOffline = isOffline
    op.isAvailable = isAvailable
    op.ttl = ttl

    op.feedsBlock = { error, feeds in
      if let er = error {
        os_log("error while fetching feeds: %{public}@",
               log: Browse.log, type: .error, String(reflecting: er))
      }
    }
    
    op.feedsCompletionBlock = { error in
      if let er = error {
        os_log("could not fetch feeds: %{public}@",
               log: Browse.log, type: .error, String(reflecting: er))
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
  
  public func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: @escaping (_ entriesError: Error?, _ entries: [Entry]) -> Void,
    entriesCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation {
    let ttl: CacheTTL = {
      if force,
        locators.count == 1,
        let uri = locators.first?.url,
        self.isEnforceable(uri) {
        return .forever
      }
      return .short
    }()
    
    let idea = RemoteRepository.ServiceIdea(
      reachability: probe.reach(),
      expecting: ttl,
      status: svc.client.status
    )
    
    // We have to aquire according feeds, before we can request their entries,
    // because we cannot update entries of uncached feeds.
    
    let fetchFeeds = makeFeedsOperationDependency(
      locators: locators,
      isOffline: idea.isOffline,
      isAvailable: idea.isAvailable
    )
    
    assert(fetchFeeds.ttl == CacheTTL.forever)
    
    let fetchEntries = EntriesOperation(cache: cache, svc: svc, locators: locators)
    
    fetchEntries.isOffline = idea.isOffline
    fetchEntries.isAvailable = idea.isAvailable
    fetchEntries.ttl = idea.ttl
    
    fetchEntries.entriesBlock = entriesBlock
    fetchEntries.entriesCompletionBlock = entriesCompletionBlock

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
