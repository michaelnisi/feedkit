//
//  ImageRepository.swift
//  FeedKit
//
//  Created by Michael Nisi on 13.12.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Nuke
import UIKit
import os.log

private let log = OSLog(subsystem: "ink.codes.feedkit", category: "images")

/// Provides processed images as fast as possible.
public final class ImageRepository {

  private static func makeImagePipeline() -> ImagePipeline {
    return ImagePipeline {
      $0.imageCache = ImageCache.shared

      let config = URLSessionConfiguration.default
      $0.dataLoader = DataLoader(configuration: config)

      let dataCache = try! DataCache(name: "ink.codes.feedkit.images")

      #warning("Remove dev code")
      dataCache.removeAll()

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

  /// A thread-safe temporary cache for URL objects.
  private var urls = NSCache<NSString, NSURL>()

}

// MARK: - Processing Images

extension ImageRepository {

  /// Produces a scaled image with rounded corners within a thin gray frame.
  struct ScaledWithRoundedCorners: ImageProcessing {

    let size: CGSize

    init(size: CGSize) {
      self.size = size
    }

    func process(image: Image, context: ImageProcessingContext) -> Image? {
      UIGraphicsBeginImageContextWithOptions(size, true, 0)

      guard let ctx = UIGraphicsGetCurrentContext() else {
        return nil
      }

      UIColor.white.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

      let cornerRadius: CGFloat = size.width <= 100 ? 3 : 6
      let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
      let p = UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius)

      p.addClip()
      image.draw(in: rect)

      let gray = UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1.0)

      ctx.setStrokeColor(gray.cgColor)
      p.stroke()

      guard let rounded = UIGraphicsGetImageFromCurrentImageContext() else {
        return nil
      }

      UIGraphicsEndImageContext()

      return rounded
    }

    static func ==(
      lhs: ScaledWithRoundedCorners, rhs: ScaledWithRoundedCorners) -> Bool {
      return lhs.size == rhs.size
    }

  }

}

// MARK: - Choosing and Caching URLs

extension ImageRepository {

  /// Picks and returns the optimal image URL for `size`.
  ///
  /// - Parameters:
  ///   - item: The image URL container.
  ///   - size: The size to choose an URL for.
  ///
  /// - Returns: An image URL or `nil` if the item doesn’t contain one of the
  /// expected URLs.
  private func imageURL(
    representing item: Imaginable, at size: CGSize) -> URL? {
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

  /// Scales `size` for`quality`.
  private static func makeSize(size: CGSize, quality: ImageQuality?) -> CGSize {
    let q = quality?.rawValue ?? ImageQuality.high.rawValue
    let w = size.width / q
    let h = size.height / q

    return CGSize(width: w, height: h)
  }

  /// Returns a cached URL for `string` creating and caching new URLs.
  private func makeURL(string: String) -> URL? {
    guard let url = urls.object(forKey: string as NSString) as URL? else {
      os_log("making URL: %@", log: log, type: .debug, string)

      if let fresh = URL(string: string) {
        urls.setObject(fresh as NSURL, forKey: string as NSString)
        return fresh
      }

      return nil
    }

    return url
  }

  /// Returns URL and/or cached response for placeholding.
  private func makePlaceholder(
    item: Imaginable, size: CGSize) -> (URL?, ImageResponse?) {
    os_log("making placeholder: %@", log: log, type: .debug, item.title)

    guard let iTunes = item.iTunes else {
      os_log("aborting placeholding: iTunes object not found", log: log)
      return (nil, nil)
    }

    var urlStrings = [iTunes.img30, iTunes.img60, iTunes.img100, iTunes.img600]

    if let image = item.image {
      urlStrings.append(image)
    }

    // Finding the first cached response.

    for urlString in urlStrings {
      guard let url = makeURL(string: urlString) else {
        continue
      }

      // Arbritrary size drawn from anecdotal evidence.
      let commonSize = CGSize(width: 82, height: 82)

      if let res =
        cachedResponse(matching: url, at: size) ??
        cachedResponse(matching: url, at: commonSize) {
        return (url, res)
      }
    }

    // Got no cached response, scaling placeholder to a quarter of the original
    // size, dividided by the screen scale factor to compensate multiplication
    // in imageURL(representing:at:).

    let l =  1 / 4 / UIScreen.main.scale
    let s = size.applying(CGAffineTransform(scaleX: l, y: l))

    return (imageURL(representing: item, at: s), nil)
  }

}

// MARK: - Images

extension ImageRepository: Images {

  public func cancel(displaying view: UIImageView) {
    Nuke.cancelRequest(for: view)
  }

  public func flush() {
    urls.removeAllObjects()

    // The Nuke image cache automatically removes all stored elements when it
    // received a memory warning. It also automatically removes most of cached
    // elements when the app enters background.
  }

  public func loadImage(item: Imaginable, size: CGSize) -> UIImage? {
    guard let url = imageURL(representing: item, at: size) else {
      return nil
    }

    os_log("synchronously loading: %{public}@",
           log: log, type: .info, url.lastPathComponent)

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

  private static func makeImageLoadingOptions(
    placeholder: UIImage?, failureImage: UIImage?) -> ImageLoadingOptions {
    return ImageLoadingOptions(
      placeholder: placeholder,
      transition: nil,
      failureImage: failureImage,
      failureImageTransition: nil,
      contentModes: nil
    )
  }

  /// Returns a request for image `url` at `size`.
  ///
  /// - Parameters:
  ///   - url: The URL of the image to load.
  ///   - size: The target size of the image.
  ///   - isClean: Append no processors to this request.
  ///
  /// The default processor adds rounded corners and a gray frame.
  private static func makeImageRequest(
    url: URL, size: CGSize, isClean: Bool = false) -> ImageRequest {
    var req = ImageRequest(url: url, targetSize: size, contentMode: .aspectFill)

    // Preferring smaller images, assuming they are placeholders or lists.
    if size.width <= 120 {
      req.priority = .veryHigh
    }

    guard !isClean else {
      return req
    }

    return req.processed(with: ScaledWithRoundedCorners(size: size))
  }

  private func cachedResponse(
    matching url: URL, at size: CGSize, isClean: Bool = false
  ) -> ImageResponse? {
    let req = ImageRepository.makeImageRequest(
      url: url, size: size, isClean: isClean)

    return Nuke.ImageCache.shared.cachedResponse(for: req)
  }

  public func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions,
    completionBlock: (() -> Void)? = nil
  ) {
    dispatchPrecondition(condition: .onQueue(.main))

    let originalSize = imageView.bounds.size
    let relativeSize = ImageRepository.makeSize(
      size: originalSize, quality: options.quality)

    guard let itemURL = imageURL(representing: item, at: relativeSize) else {
      os_log("missing URL: %{public}@", log: log,  type: .error,
             String(describing: item))
      return
    }

    os_log("getting: ( %@, %@ )",
           log: log, type: .info, item.title, originalSize as CVarArg)

    let isClean = options.isClean

    if let res = cachedResponse(
      matching: itemURL, at: originalSize, isClean: isClean) {
      os_log("** setting image: %@", log: log, type: .debug, item.title)

      imageView.image = res.image

      completionBlock?()
      return
    }

    /// Issues the actual load request.
    func issue(_ url: URL, cb: (() -> Void)? = nil) {
      dispatchPrecondition(condition: .onQueue(.main))

      let req = ImageRepository.makeImageRequest(
        url: url, size: originalSize, isClean: options.isClean)

      let opts = ImageRepository.makeImageLoadingOptions(
        placeholder: imageView.image,
        failureImage: options.fallbackImage ?? imageView.image
      )

      os_log("loading: %@", log: log, type: .debug, url.lastPathComponent)

      Nuke.loadImage(with: req, options: opts, into: imageView) {
        response, error in
        dispatchPrecondition(condition: .onQueue(.main))

        if let er = error {
          os_log("image loading failed: %{public}@", log: log, er as CVarArg)
        }

        cb?()
      }
    }

    // If this isn’t specifically direct, no cached response is available, and
    // we can find a suitable placeholder, we are loading a smaller image first.

    guard !options.isDirect else {
      return issue(itemURL) {
        completionBlock?()
      }
    }

    let (placeholderURL, placeholder) = makePlaceholder(
      item: item, size: originalSize)

    guard placeholderURL != nil || placeholder != nil else {
      return issue(itemURL) {
        completionBlock?()
      }
    }

    if let image = placeholder?.image {
      os_log("** setting placeholder: %@", log: log, type: .debug, item.title)
      
      imageView.image = image

      return issue(itemURL) {
        completionBlock?()
      }
    }

    issue(placeholderURL!) {
      issue(itemURL) {
        completionBlock?()
      }
    }
  }

  public func loadImage(
    representing item: Imaginable,
    into imageView: UIImageView,
    options: FKImageLoadingOptions
  ) {
    loadImage(
      representing: item,
      into: imageView,
      options: options,
      completionBlock: nil
    )
  }

  public func loadImage(
    representing item: Imaginable, into imageView: UIImageView) {
    let defaults = FKImageLoadingOptions()

    loadImage(representing: item, into: imageView, options: defaults)
  }

}

// MARK: - Prefetching

extension ImageRepository {

  private func makeRequests(
    items: [Imaginable], size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    return items.compactMap {
      let s = ImageRepository.makeSize(size: size, quality: quality)

      guard let url = imageURL(representing: $0, at: s) else {
        return nil
      }

      return ImageRequest(url: url)
    }
  }

  public func prefetchImages(
    for items: [Imaginable], at size: CGSize, quality: ImageQuality
  ) -> [ImageRequest] {
    os_log("prefetching: %i", log: log, type: .debug, items.count)

    let reqs = makeRequests(items: items, size: size, quality: quality)

    preheater.startPreheating(with: reqs)

    return reqs
  }

  public func cancel(prefetching requests: [ImageRequest]) {
    os_log("cancelling prefetching", log: log, type: .debug)
    preheater.stopPreheating(with: requests)
  }

}
