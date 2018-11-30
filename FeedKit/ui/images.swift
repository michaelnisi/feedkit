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
  var title: String { get }
}

/// Configures image loading.
public struct FKImageLoadingOptions {
  let fallbackImage: UIImage?
  let quality: ImageQuality
  let isDirect: Bool

  /// Creates new options for image loading.
  ///
  /// For larger sizes a smaller image gets preloaded and displayed first,
  /// which gets replaced when the large image has been loaded. Use `isDirect`
  /// to skip this preloading step.
  ///
  /// - Parameters:
  ///   - fallbackImage: A failure image for using as fallback.
  ///   - quality: The image quality defaults to medium.
  ///   - isDirect: Skip preloading smaller images, which is the default.
  public init(
    fallbackImage: UIImage? = nil,
    quality: ImageQuality = .medium,
    isDirect: Bool = false) {
    self.fallbackImage = fallbackImage
    self.quality = quality
    self.isDirect = isDirect
  }
}

public protocol Images {

  /// Loads an image to represent `item` into `imageView`, scaling the image
  /// to match the image view’s bounds.
  ///
  /// - Parameters:
  ///   - item: The item the loaded image should represent.
  ///   - imageView: The target view to display the image.
  ///   - options: Some options for image loading.
  func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions
  )

  /// Loads an image using default options: falling back on existing image,
  /// medium quality, and preloading smaller images for large sizes.
  func loadImage(representing item: Imaginable, into imageView: UIImageView)

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

fileprivate func makeSize(size: CGSize, quality: ImageQuality?) -> CGSize {
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

    guard let ctx = UIGraphicsGetCurrentContext() else {
      return nil
    }

    UIColor.white.setFill()
    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

    let cornerRadius: CGFloat = size.width <= 100 ? 3 : 6
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)

    UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius).addClip()
    image.draw(in: rect)

    guard let rounded = UIGraphicsGetImageFromCurrentImageContext() else {
      return nil
    }

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

/// Provides processed images as fast as possible.
public final class ImageRepository: Images {

  private static func makeImagePipeline() -> ImagePipeline {
    return ImagePipeline {
      $0.imageCache = ImageCache.shared

      let config = URLSessionConfiguration.default
      $0.dataLoader = DataLoader(configuration: config)

      let dataCache = try! DataCache(name: "ink.codes.podest.images")
      $0.dataCache = dataCache

      $0.dataLoadingQueue.maxConcurrentOperationCount = 6
      $0.imageDecodingQueue.maxConcurrentOperationCount = 1
      $0.imageProcessingQueue.maxConcurrentOperationCount = 2

      $0.isDeduplicationEnabled = true

      $0.isProgressiveDecodingEnabled = false
    }
  }

  init() {
    ImagePipeline.shared = ImageRepository.makeImagePipeline()
  }

  public static var shared: Images = ImageRepository()

  fileprivate let preheater = Nuke.ImagePreheater()

  public func cancel(displaying view: UIImageView) {
    Nuke.cancelRequest(for: view)
  }

  /// A thread-safe temporary cache for URL objects, which are expensive.
  private var urls = NSCache<NSString, NSURL>()

  public func flush() {
    urls.removeAllObjects()

    // The Nuke image cache automatically removes all stored elements when it
    // received a memory warning. It also automatically removes most of cached
    // elements when the app enters background.
  }

  public func image(for item: Imaginable, in size: CGSize) -> UIImage? {
    guard let url = imageURL(representing: item, at: size) else {
      return nil
    }

    os_log("synchronously loading: ( %{public}@, %{public}@ )",
           log: log, type: .debug, item.title, url as CVarArg)

    var image: UIImage?
    let req = ImageRequest(url: url, targetSize: size, contentMode: .aspectFill)
    let blocker = DispatchSemaphore(value: 0)

    Nuke.ImagePipeline.shared.loadImage(with: req) { res, error in
      if let er = error {
        os_log("synchronously loading failed: %{public}@", er as CVarArg)
      }
      image = res?.image
      blocker.signal()
    }

    blocker.wait()

    return image
  }

  private static
  func makeImageRequest(url: URL, size: CGSize) -> ImageRequest {
     var req = ImageRequest(
      url: url,
      targetSize: size,
      contentMode: .aspectFill
    )

    // Preferring smaller images, assuming they’re placeholders or lists.
    if size.width <= 120 {
      req.priority = .veryHigh
    }

    return req.processed(with: ScaledWithRoundedCorners(size: size))
  }

  private static func makeURL(url: URL) -> URL {
    return Int.random(in: 0...1) == 1 ? URL(string: "http://localhost/nowhere")! : url
  }

  /// Loads an image at `url` into `view` sized to `size`, while keeping the
  /// current image as placeholder until the remote image has been loaded
  /// successfully. If loading fails, keeps showing the placeholder.
  private func load(
    url: URL,
    into view: UIImageView,
    sized size: CGSize,
    placeholder: UIImage?,
    failureImage: UIImage?,
    cb: @escaping ImageTask.Completion
  ) {
    os_log("loading: ( %{public}@, %{public}@ )", log: log, type: .info,
           url as CVarArg, size as CVarArg)

    // TODO: Remove failure injection
    let x = Int.random(in: 0...1) == 1 ? URL(string: "http://localhost/nowhere")! : url

    let req = ImageRepository.makeImageRequest(url: url, size: size)

    let opts = ImageLoadingOptions(
      placeholder: placeholder,
      transition: nil,
      failureImage: failureImage,
      failureImageTransition: nil,
      contentModes: nil
    )

    Nuke.loadImage(with: req, options: opts, into: view, completion: cb)
  }

  /// Returns `true` if there’s a cached response matching `url`.
  private func hasCachedResponse(matching url: URL) -> Bool {
    let req = ImageRequest(url: url)
    return Nuke.ImageCache.shared.cachedResponse(for: req) != nil
  }

  /// Returns high quality if `item` is cached or `nil` if not.
  private func makeHighQuality(item: Imaginable, size: CGSize) -> ImageQuality? {
    guard let url = imageURL(representing: item, at: size),
      hasCachedResponse(matching: url) else {
      return nil
    }

    os_log("** upgrading to high quality: %{public}@",
           log: log, type: .debug, item.title)

    return .high
  }

  public func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions
  ) {
    dispatchPrecondition(condition: .onQueue(.main))

    let (size, tag) = (imageView.bounds.size, imageView.tag)

    os_log("requesting: ( %@, %@ )",
           log: log, type: .info, item.title, size as CVarArg)

    let q = makeHighQuality(item: item, size: size) ?? options.quality
    let s = makeSize(size: size, quality: q)

    guard let itemURL = imageURL(representing: item, at: s) else {
      os_log("missing URL: %{public}@", log: log,  type: .error,
             String(describing: item))
      return
    }

    func l(_ url: URL, hasPlaceHolder: Bool = false, cb: (() -> Void)? = nil) {
      dispatchPrecondition(condition: .onQueue(.main))

      // Having a placeholder, we don’t have to fallback on generic image.
      let f = hasPlaceHolder ? imageView.image : options.fallbackImage

      load(url: url, into: imageView, sized: size,
           placeholder: imageView.image, failureImage: f) { response, error in
        dispatchPrecondition(condition: .onQueue(.main))

        if let er = error {
          os_log("image loading failed: %{public}@", er as CVarArg)
        }

        cb?()
      }
    }

    // If direct loading wasn’t requested and we can find a suitable URL for
    // placeholding, we are loading a smaller image first.

    guard !options.isDirect ,
      let placeholderURL = makePlaceholderURL(item: item, size: size) else {
      return l(itemURL)
    }

    os_log("loading placeholder: %@",
           log: log, type: .debug, placeholderURL as CVarArg)

    l(placeholderURL) {
      l(itemURL, hasPlaceHolder: true)
    }
  }

  public func loadImage(
    representing item: Imaginable, into imageView: UIImageView) {
    let defaults = FKImageLoadingOptions()
    loadImage(representing: item, into: imageView, options: defaults)
  }

}

// MARK: - Choosing and Caching URLs

extension ImageRepository {

  /// Returns a cached URL for `string` creating and caching new URLs.
  ///
  /// - Returns: Returns a valid URL or `nil`.
  private func makeURL(string: String) -> URL? {
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
  fileprivate
  func imageURL(representing item: Imaginable, at size: CGSize) -> URL? {
    os_log("looking up URL representing: ( %{public}@, %{public}@ )",
           log: log, type: .debug, item.title, size as CVarArg)

    let wanted = size.width * UIScreen.main.scale

    var urlString: String?

    if wanted <= 30 {
      urlString = item.iTunes?.img30
    } else if wanted <= 60 {
      urlString = item.iTunes?.img60
    } else if wanted <= 180 {
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

    guard let string = urlString, let url = makeURL(string: string) else {
      os_log("no image URL", log: log, type: .error)
      return nil
    }

    return url
  }

  /// Returns adequate URL for placeholding if possible.
  private func makePlaceholderURL(item: Imaginable, size: CGSize) -> URL? {
    os_log("making placeholder URL", log: log, type: .debug)

    guard let iTunes = item.iTunes else {
      os_log("aborting: no iTunes", log: log, type: .debug)
      return nil
    }

    var urlStrings = [iTunes.img30, iTunes.img60, iTunes.img100, iTunes.img600]
    if let image = item.image { urlStrings.append(image) }

    for urlString in urlStrings {
      guard let url = makeURL(string: urlString) else {
        continue
      }

      if hasCachedResponse(matching: url) {
        return url
      }
    }

    // Scaling placeholder to a quarter of the original size, additionally
    // dividing by the screen scale factor to compensate multiplication in
    // imageURL(representing:, at:).

    let l =  1 / 4 / UIScreen.main.scale
    let s = size.applying(CGAffineTransform(scaleX: l, y: l))

    return imageURL(representing: item, at: s)
  }

}

// MARK: - Prefetching

extension ImageRepository {

  fileprivate func requests(
    with items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    return items.compactMap {
      let s = makeSize(size: size, quality: quality)
      guard let url = imageURL(representing: $0, at: s) else {
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
