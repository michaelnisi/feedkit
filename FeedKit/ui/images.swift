//
//  images.swift - Load images
//  Podest
//
//  Created by Michael on 3/19/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Nuke
import UIKit
import os.log

private let log = OSLog.disabled

// Hiding Nuke from participants.
public typealias ImageRequest = Nuke.ImageRequest

// MARK: - API

public enum ImageQuality: CGFloat {
  case high = 1
  case medium = 2
  case low = 4
}

public protocol Imaginable {
  var iTunes: ITunesItem? { get }
  var image: String? { get }
}

public protocol Images {

  func loadImage(for item: Imaginable, into imageView: UIImageView)

  /// Loads an image to represent `item` into `imageView`, scaling the image
  /// to match the image view’s bounds. For larger sizes a smaller image gets
  /// preloaded and displayed first, which gets replaced when the large image
  /// has been loaded, unless `imageView` is already occupied by an image, in
  /// that case, that previous image is used for placeholding while loading.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  ///   - quality: The expected image quality.
  func loadImage(
    for item: Imaginable,
    into imageView: UIImageView,
    quality: ImageQuality?
  )

  /// Prefetches images of `items`, preheating the image cache.
  ///
  /// - Returns: The resulting image requests, these can be used to cancel
  /// this prefetching batch.
  func prefetchImages(
    for items: [Imaginable],
    at size: CGSize,
    quality: ImageQuality
  ) -> [ImageRequest]

  /// Cancels prefetching `requests`.
  func cancel(prefetching requests: [ImageRequest])

  /// Cancels request associated with `view`.
  func cancel(displaying view: UIImageView)

  /// Synchronously loads an image for the specificied item and size.
  func image(for item: Imaginable, in size: CGSize) -> UIImage?
  
  /// Flushes memory cache.
  func flush()
  
}

fileprivate func scale(_ size: CGSize, to quality: ImageQuality?) -> CGSize {
  let q = quality?.rawValue ?? ImageQuality.high.rawValue
  let w = size.width / q
  let h = size.height / q
  return CGSize(width: w, height: h)
}

// MARK: - Image Processing

private struct ScaledWithRoundedCorners: ImageProcessing {

  let size: CGSize

  init(size: CGSize) {
    self.size = size
  }

  /// Returns scaled `image` with rounded corners.
  func process(image: Image, context: ImageProcessingContext) -> Image? {
    UIGraphicsBeginImageContextWithOptions(size, true, 0)

    let ctx = UIGraphicsGetCurrentContext()!

    UIColor.white.setFill()
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    let cornerRadius: CGFloat = size.width <= 100 ? 3 : 6
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius).addClip()
    image.draw(in: rect)
    let rounded: UIImage = UIGraphicsGetImageFromCurrentImageContext()!

    UIGraphicsEndImageContext()

    return rounded
  }

  static func ==(
    lhs: ScaledWithRoundedCorners,
    rhs: ScaledWithRoundedCorners
  ) -> Bool {
    return lhs.size == rhs.size
  }
}

/// Provides images. Images are cached, including their rounded corners, making
/// it impossible to get an image without rounded corners, at the moment.
public final class ImageRepository: Images {
  
  init() {
    let pipeline = ImagePipeline {
      // Shared image cache with a `sizeLimit` equal to ~20% of available RAM.
      $0.imageCache = ImageCache.shared
      
      // Data loader with a `URLSessionConfiguration.default` but with a
      // custom shared URLCache instance:
      //
      // public static let sharedUrlCache = URLCache(
      //     memoryCapacity: 0,
      //     diskCapacity: 150 * 1024 * 1024, // 150 MB
      //     diskPath: "com.github.kean.Nuke.Cache"
      //  )
      let config = URLSessionConfiguration.default
      config.urlCache = nil
      $0.dataLoader = DataLoader(configuration: config)
      
      // Custom disk cache is disabled by default, the native URL cache used
      // by a `DataLoader` is used instead.
      $0.dataCache = try! DataCache(name: "ink.codes.podest.images") { name in
        let hash = String(djb2Hash32(string: name))
//        os_log("""
//        using hash: (
//          %{public}@,
//          %{public}@
//        )
//        """, log: log, type: .debug, name, hash)
        return hash
      }
      
      // Each stage is executed on a dedicated queue with has its own limits.
      $0.dataLoadingQueue.maxConcurrentOperationCount = 6
      $0.imageDecodingQueue.maxConcurrentOperationCount = 1
      $0.imageProcessingQueue.maxConcurrentOperationCount = 2
      
      // Combine the requests for the same original image into one.
      $0.isDeduplicationEnabled = true
      
      // Progressive decoding is a resource intensive feature so it is
      // disabled by default.
      $0.isProgressiveDecodingEnabled = false
    }
    
    // When you're done you can make the pipeline a shared one:
    ImagePipeline.shared = pipeline
  }
  
  public static var shared: Images = ImageRepository()

  fileprivate let preheater = Nuke.ImagePreheater()
  
  public func cancel(displaying view: UIImageView) {
    Nuke.cancelRequest(for: view)
  }
  
  /// A thread-safe temporary cache for URL objects.
  private var urls = NSCache<NSString, NSURL>()
  
  public func flush() {
    urls.removeAllObjects()
    
    // The Nuke image cache automatically removes all stored elements when it
    // received a memory warning. It also automatically removes most of cached
    // elements when the app enters background.
  }

  public func image(for item: Imaginable, in size: CGSize) -> UIImage? {
    os_log("synchronously loading image: %{public}@, %{public}@",
           log: log,
           type: .debug,
           String(describing: item),
           String(describing: item.iTunes))

    guard let url = urlToLoad(from: item, for: size) else {
      return nil
    }

    var image: UIImage?
    let req = ImageRequest(url: url, targetSize: size, contentMode: .aspectFill)
    let blocker = DispatchSemaphore(value: 0)

    Nuke.ImagePipeline.shared.loadImage(with: req) { res, error in
      if let er = error {
        os_log("synchronous loading error: %{public}@", log: log, er as CVarArg)
      }
      image = res?.image
      blocker.signal()
    }

    blocker.wait()

    return image
  }

  /// Loads image at `url` into `view` sized to `size`, while keeping the
  /// current image as placeholder until the remote image has been loaded
  /// successfully. If loading fails, keeps showing the placeholder.
  private static func load(
    url: URL,
    into view: UIImageView?,
    sized size: CGSize,
    cb: @escaping ImageTask.Completion
  ) {
    let req = ImageRequest(
      url: url,
      targetSize: size,
      contentMode: .aspectFill
    ).processed(with: ScaledWithRoundedCorners(size: size))

    guard let v = view else { return }

    os_log("loading image: %{public}@ %{public}@", log: log, type: .debug,
           url as CVarArg, size as CVarArg)

    guard let currentImage = v.image else {
      Nuke.loadImage(with: req, into: v, completion: cb)
      return
    }

    os_log("placeholding with current image", log: log, type: .debug)

    let opts = ImageLoadingOptions(
      placeholder: currentImage,
      transition: nil,
      failureImage: currentImage,
      failureImageTransition: nil,
      contentModes: nil
    )

    Nuke.loadImage(with: req, options: opts, into: v, completion: cb)
  }

  public func loadImage(
    for item: Imaginable,
    into imageView: UIImageView,
    quality: ImageQuality? = nil
  ) {
    dispatchPrecondition(condition: .onQueue(.main))
    
    let (size, tag) = (imageView.bounds.size, imageView.tag)

    os_log("handling image request for: %@, with: %@, at: %@",
           log: log, type: .debug,
           String(describing: item),
           String(describing: item.iTunes),
           size as CVarArg)

    guard let itemURL = urlToLoad(from: item, for: scale(size, to: quality)) else {
      os_log("missing URL: %{public}@", log: log,  type: .error,
             String(describing: item))
      return
    }
    
    func load(_ url: URL, cb: (() -> Void)? = nil) {
      dispatchPrecondition(condition: .onQueue(.main))
      ImageRepository.load(url: url, into: imageView, sized: size) {
        [weak imageView] res, _ in
        dispatchPrecondition(condition: .onQueue(.main))
        defer { cb?() }
        guard imageView?.tag == tag else { return }
        imageView?.image = res?.image
      }
    }
    
    guard imageView.image == nil else {
      return load(itemURL)
    }
    
    guard let placeholderURL = urlToPreload(from: item, for: size) else {
      return load(itemURL)
    }
    
    load(placeholderURL) {
      load(itemURL)
    }
  }

  public func loadImage(for item: Imaginable, into imageView: UIImageView) {
    loadImage(for: item, into: imageView, quality: .high)
  }
}

// MARK: - Choosing and Caching URLs

extension ImageRepository {
  
  /// Returns a cached URL for `string` creating and caching new URLs.
  ///
  /// - Returns: Returns a valid URL or `nil`.
  private func cachedURL(string: String) -> URL? {
    guard let url = urls.object(forKey: string as NSString) as URL? else {
      if let fresh = URL(string: string) {
        urls.setObject(fresh as NSURL, forKey: string as NSString)
        return fresh
      }
      return nil
    }
    
    return url
  }
  
  /// Picks and returns the optimal image URL for `size`.
  ///
  /// - Parameters:
  ///   - item: The image URL container.
  ///   - size: The size to choose an URL for.
  ///
  /// - Returns: An image URL or `nil` if the item doesn’t contain one of the
  /// expected URLs.
  fileprivate func urlToLoad(from item: Imaginable, for size: CGSize) -> URL? {
    let wanted = size.width * UIScreen.main.scale
    
    var urlString: String?
    
    if wanted <= 30 {
      urlString = item.iTunes?.img30
    } else if wanted <= 60 {
      urlString = item.iTunes?.img60
    } else if wanted <= 100 {
      urlString = item.iTunes?.img100
    } else {
      urlString = item.iTunes?.img600
    }
    
    if urlString == nil {
      os_log("falling back on LARGE image", log: log)
      if let entry = item as? Entry {
        urlString = entry.feedImage
      }
      urlString = urlString ?? item.image
    }
    
    guard let string = urlString, let url = cachedURL(string: string) else {
      os_log("no image URL", log: log, type: .error)
      return nil
    }
    
    return url
  }
  
  /// Returns an URL adequate for placeholding.
  private func urlToPreload(from item: Imaginable, for size: CGSize) -> URL? {
    guard let iTunes = item.iTunes else {
      os_log("aborting: no iTunes", log: log, type: .debug)
      return nil
    }
    
    var urlStrings = [iTunes.img30, iTunes.img60, iTunes.img100, iTunes.img600]
    if let image = item.image { urlStrings.append(image) }
    
    for urlString in urlStrings {
      guard let url = cachedURL(string: urlString) else {
        continue
      }
      let req = ImageRequest(url: url)
      if Nuke.ImageCache.shared.cachedResponse(for: req) != nil {
        return url
      }
    }
    
    let s = min(size.width / 4, 100) / UIScreen.main.scale
    return urlToLoad(from: item, for: CGSize(width: s, height: s))
  }
  
}

// MARK: - Prefetching

extension ImageRepository {

  fileprivate func requests(
    with items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    return items.compactMap {
      guard let url = urlToLoad(from: $0, for: scale(size, to: quality)) else {
        return nil
      }
      return ImageRequest(url: url)
    }
  }

  public func prefetchImages(
    for items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    let reqs = requests(with: items, at: size, quality: quality)
    os_log("starting preheating: %{public}@", log: log, type: .debug, items)
    preheater.startPreheating(with: reqs)
    return reqs
  }

  public func cancel(prefetching requests: [ImageRequest]) {
    os_log("stopping preheating: %{public}@", log: log, type: .debug, requests)
    preheater.stopPreheating(with: requests)
  }

}
