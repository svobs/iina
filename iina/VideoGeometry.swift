//
//  VideoGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 11/14/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `VideoGeometry`: collection of metadata for the current video.Fetched from mpv.
///
/// Processing pipeline:
/// `videoSizeRaw` (`rawWidth`, `rawHeight`)
///   ➤ Parse `selectedAspectLabel` into `aspectRatioOverride`, then apply it
///     ➤ `videoSizeA`
///       ➤ Parse `selectedCropLabel` into `cropRect`, then apply it
///         ➤ `videoSizeAC` (`videoWidthAC` x `videoHeightAC`). AKA "dsize", per mpv usage
///           ➤ apply `totalRotation` (== `userRotation` + rotation specified by video)
///             ➤ `videoSizeACR` (`videoWidthACR`, `videoHeightACR`)
///               ➤ apply `scale`
///                 ➤ `videoSizeACRS` (AKA `videoSize` in `PWGeometry`)
struct VideoGeometry: CustomStringConvertible {
  static let nullGeometry = VideoGeometry(rawWidth: 0, rawHeight: 0,
                                          selectedAspectLabel: "",
                                          totalRotation: 0, userRotation: 0,
                                          selectedCropLabel: AppData.noneCropIdentifier,
                                          scale: 0, log: Logger.Subsystem(rawValue: "null"))

  private let log: Logger.Subsystem

  init(rawWidth: Int, rawHeight: Int,
       selectedAspectLabel: String,
       totalRotation: Int, userRotation: Int,
       selectedCropLabel: String,
       scale: CGFloat,
       log: Logger.Subsystem) {
    self.rawWidth = rawWidth
    self.rawHeight = rawHeight
    if let aspectRatioOverride = Aspect(string: selectedAspectLabel) {
      self.selectedAspectLabel = selectedAspectLabel
      self.aspectRatioOverride = Aspect.mpvPrecision(of: aspectRatioOverride.value)
    } else {
      self.selectedAspectLabel = AppData.defaultAspectIdentifier
      self.aspectRatioOverride = nil
    }
    self.totalRotation = totalRotation
    self.userRotation = userRotation
    self.selectedCropLabel = selectedCropLabel
    self.cropRect = VideoGeometry.makeCropRect(fromCropLabel: selectedCropLabel, rawWidth: rawWidth, rawHeight: rawHeight)
    self.scale = scale
    self.log = log
  }

  // FIXME: make this the SST for scale, instead of calculating it afterwards
  func clone(rawWidth: Int? = nil, rawHeight: Int? = nil,
             selectedAspectLabel: String? = nil,
             totalRotation: Int? = nil, userRotation: Int? = nil,
             selectedCropLabel: String? = nil,
             scale: CGFloat? = nil) -> VideoGeometry {
    return VideoGeometry(rawWidth: rawWidth ?? self.rawWidth, rawHeight: rawHeight ?? self.rawHeight,
                         selectedAspectLabel: selectedAspectLabel ?? self.selectedAspectLabel,
                         totalRotation: totalRotation ?? self.totalRotation, userRotation: userRotation ?? self.userRotation,
                         selectedCropLabel: selectedCropLabel ?? self.selectedCropLabel,
                         scale: scale ?? self.scale, log: self.log)

  }

  /// The native ("raw") stored dimensions of the current video, before any transformation is applied.
  /// Either `rawWidth` or `rawHeight` should be 0 if the raw video size is unknown or not loaded yet.
  /// From the mpv manual:
  /// ```
  /// width, height
  ///   Video size. This uses the size of the video as decoded, or if no video frame has been decoded yet,
  ///   the (possibly incorrect) container indicated size.
  /// ```
  let rawWidth: Int
  let rawHeight: Int

  /// The native size of the current video, before any filters, rotations, or other transformations applied.
  /// Returns `nil` if its width or height is considered missing or invalid (i.e., not positive).
  var videoSizeRaw: CGSize? {
    guard rawWidth > 0, rawHeight > 0 else { return nil}
    return CGSize(width: rawWidth, height: rawHeight)
  }

  // MARK: - TRANSFORMATION 1: Aspect

  /// The currently applied aspect ratio override.
  ///
  /// This is a string so that it can be used to identify the currently selected aspect in the Video menu & in the Video Settings
  /// sidebar's segmented control.
  /// • If this is an aspect-based crop, it ideally should be in the format `"W:H"` to match in the UI, but can also be a decimal number.
  /// • If this is a crop rect, it should be in mpv format. This can be either `WxH` or `WxH+x+y` forms. See `MPVFilter.cropRect()`
  let selectedAspectLabel: String

  /// Optional aspect ratio override (mpv property `video-aspect-override`). Truncates aspect to the first 2 digits after decimal.
  let aspectRatioOverride: CGFloat?

  /// Equal to `videoSizeRaw` + `aspectRatioOverride` applied. If there is no aspect ratio override, then identical to `videoSizeRaw`.
  var videoSizeA: CGSize? {
    guard let videoSizeRaw else { return nil }

    return VideoGeometry.applyAspectOverride(aspectRatioOverride, to: videoSizeRaw)
  }

  // MARK: - TRANSFORMATION 2: Crop
  // (Aspect + Crop)

  /// The currently applied crop (`iina_crop` filter), or `None` if no crop.
  ///
  /// This is a string so that it can be used to identify the currently selected crop in the Video menu & in the Video Settings
  /// sidebar's segmented control.
  let selectedCropLabel: String

  var hasCrop: Bool {
    return selectedCropLabel != AppData.noneCropIdentifier
  }

  /// This is derived from `selectedCropLabel`, but has its Y value flipped so that it works with Cocoa views.
  let cropRect: CGRect?

  lazy var cropRectNormalized: CGRect? = {
    guard let videoSizeRaw, let cropRect else { return nil }
    let xNorm = cropRect.origin.x / videoSizeRaw.width
    let yNorm = cropRect.origin.y / videoSizeRaw.height
    let widthNorm = cropRect.width / videoSizeRaw.width
    let heightNorm = cropRect.height / videoSizeRaw.height
    let normRect = NSRect(x: xNorm, y: yNorm, width: widthNorm, height: heightNorm)
    if log.isTraceEnabled {
      log.trace("Normalized cropRect \(cropRect) → \(normRect)")
    }
    guard widthNorm > 0, heightNorm > 0 else {
      log.warn("Invalid cropRect! Returning nil")
      return nil
    }
    return normRect
  }()

  /// The video size, after aspect override and crop filter applied, but before rotation or final scaling.
  ///
  /// From the mpv manual:
  /// ```
  /// dwidth, dheight
  /// Video display size. This is the video size after filters and aspect scaling have been applied. The actual
  /// video window size can still be different from this, e.g. if the user resized the video window manually.
  /// These have the same values as video-out-params/dw and video-out-params/dh.
  /// ```
  var videoSizeAC: CGSize? {
    guard let videoSizeRaw, let videoSizeA else {
      return nil
    }
    let widthMultiplier = videoSizeA.width / videoSizeRaw.width
    let heightMultiplier = videoSizeA.height / videoSizeRaw.height

    if let cropRect {
      return CGSize(width: cropRect.width * widthMultiplier, height: cropRect.height * heightMultiplier)
    }
    return videoSizeA
  }

  /// Same as mpv `dwidth`. See docs for `videoSizeAC`.
  var videoWidthAC: Int? {
    guard let videoSizeAC else { return nil }
    return Int(videoSizeAC.width)
  }
  /// Same as mpv `dheight`. See docs for `videoSizeAC`.
  var videoHeightAC: Int? {
    guard let videoSizeAC else { return nil }
    return Int(videoSizeAC.height)
  }

  var cropFilter: MPVFilter? {
    return buildCropFilter(from: selectedCropLabel)
  }

  func buildCropFilter(from cropLabel: String) -> MPVFilter? {
    if cropLabel.isEmpty || cropLabel == AppData.noneCropIdentifier {
      return nil
    }

    guard let videoSizeRaw else {
      log.error("Cannot build crop filter from \(cropLabel.quoted): videoSizeRaw is invalid")
      return nil
    }

    if let aspect = Aspect(string: cropLabel)  {
      let cropped = videoSizeRaw.crop(withAspect: aspect)
      log.verbose("Building crop filter from requested string \(cropLabel.quoted) to: \(cropped.width)x\(cropped.height) (origSize: \(videoSizeRaw))")
      guard cropped.width > 0 && cropped.height > 0 else {
        log.error("Cannot build crop filter from \(cropped); width or height is <= 0")
        return nil
      }
      return MPVFilter.crop(w: Int(cropped.width), h: Int(cropped.height), x: nil, y: nil)
    }

    if let cropRect = VideoGeometry.makeCropRect(fromCropLabel: cropLabel,
                                                 rawWidth: Int(videoSizeRaw.width), rawHeight: Int(videoSizeRaw.height)) {

      let unflippedY = videoSizeRaw.height - (cropRect.origin.y + cropRect.height)
      return MPVFilter.crop(w: Int(cropRect.width), h: Int(cropRect.height), x: Int(cropRect.origin.x), y: Int(unflippedY))
    }

    log.error("Not a valid aspect-based crop string: \(cropLabel.quoted)")
    return nil
  }
  
  // MARK: - TRANSFORMATION 3: Rotation
  // (Aspect + Crop + Rotation)

  /// `MPVProperty.videoParamsRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVProperty.videoParamsRotate` ("video-params/rotate")
  /// IINA only supports one of [0, 90, 180, 270]
  let totalRotation: Int

  /// `MPVProperty.videoRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVOption.Video.videoRotate` ("video-rotate").
  /// Not to be confused with the `MPVProperty.videoParamsRotate` ("video-params/rotate")
  let userRotation: Int

  var isWidthSwappedWithHeightByRotation: Bool {
    // 90, 270, etc...
    (totalRotation %% 180) != 0
  }

  /// Like `dwidth`, but after applying `totalRotation`.
  var videoWidthACR: Int? {
    if isWidthSwappedWithHeightByRotation {
      return videoHeightAC
    } else {
      return videoWidthAC
    }
  }

  /// Like `dheight`, but after applying `totalRotation`.
  var videoHeightACR: Int? {
    if isWidthSwappedWithHeightByRotation {
      return videoWidthAC
    } else {
      return videoHeightAC
    }
  }

  /// Like `videoSizeAC`, but after applying `totalRotation`.
  var videoSizeACR: CGSize? {
    guard let videoWidthACR, let videoHeightACR else { return nil }
    return CGSize(width: videoWidthACR, height: videoHeightACR)
  }

  var hasValidSize: Bool {
    return videoWidthACR != nil && videoHeightACR != nil
  }

  var videoAspectACR: CGFloat? {
    guard let videoSizeACR else { return nil }
    return videoSizeACR.mpvAspect
  }

  // MARK: - TRANSFORMATION 4: Scale
  // (Aspect + Crop + Rotation + Scale)

  /// `MPVProperty.windowScale`:
  var scale: CGFloat

  /// Like `videoSizeACR`, but after applying `scale`.
  var videoSizeACRS: CGSize? {
    guard let videoSizeACR else { return nil }
    guard scale > 0.0 else { return nil }
    return CGSize(width: round(videoSizeACR.width * scale),
                  height: round(videoSizeACR.height * scale))
  }

  /// Final aspect ratio of `videoView`, equal to `videoAspectACR`. Takes into account aspect override, crop, and rotation (scale-invariant).
  var videoViewAspect: CGFloat? {
    return videoAspectACR
  }

  // MARK: - Etc

  var description: String {
    return "VideoGeometry:{vidSizeRaw=(\(rawWidth) x \(rawHeight)) vidSizeAC=(\(videoWidthAC?.description ?? "nil") x \(videoHeightAC?.description ?? "nil")) selectedAspectLabel=\(selectedAspectLabel.quoted) aspectOverride=\(aspectRatioOverride?.description.quoted ?? "nil") rotTotal=\(totalRotation) rotUser=\(userRotation) cropLabel=\(selectedCropLabel.description.quoted) cropRect=\(cropRect?.description ?? "nil") aspectACR=\(videoAspectACR?.description ?? "nil") vidSizeACR=\(videoSizeACR?.description ?? "nil") scale=\(scale) videoSizeACRS=\(videoSizeACRS?.description ?? "nil")}"
  }

  // MARK: Static util functions

  /// Adjusts the dimensions of the given `CGSize` as needed to match the given aspect
  static func applyAspectOverride(_ newAspect: CGFloat?, to origSize: CGSize) -> CGSize {
    guard let newAspect else {
      // No aspect override
      return origSize
    }
    let origAspect = origSize.mpvAspect
    if origAspect > newAspect {
      return CGSize(width: origSize.width, height: round(origSize.height * origAspect / newAspect))
    }
    return CGSize(width: round(origSize.width / origAspect * newAspect), height: origSize.height)
  }

  static func makeCropRect(fromCropLabel cropLabel: String, rawWidth: Int, rawHeight: Int) -> CGRect? {
    if cropLabel == AppData.noneCropIdentifier {
      return nil
    }

    let videoRawSize = CGSize(width: rawWidth, height: rawHeight)

    if let aspect = Aspect(string: cropLabel) {
      /// Aspect ratio, e.g. `16:9` or `1.33`
      return videoRawSize.getCropRect(withAspect: aspect)
    }

    /// mpv format, either `WxH`, or `WxH+x+y` forms.
    let split1 = cropLabel.split(separator: "x")
    if split1.count == 2 {
      if split1[1].firstIndex(of: "+") == nil {
        let params: [String: String] = [
          "w": String(split1[0]),
          "h": String(split1[1])
        ]
        return MPVFilter.cropRect(fromParams: params, origVideoSize: videoRawSize, flipY: true)
      }

      let split2 = split1[1].split(separator: "+")
      if split2.count == 3 {
        let params: [String: String] = [
          "w": String(split1[0]),
          "h": String(split2[0]),
          "x": String(split2[1]),
          "y": String(split2[2])
        ]
        return MPVFilter.cropRect(fromParams: params, origVideoSize: videoRawSize, flipY: true)
      }
    }
    Logger.log("Could not parse crop from label: \(cropLabel.quoted)", level: .error)
    return nil
  }

}
