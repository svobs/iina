//
//  VideoGeometry.swift
//  iina
//
//  Created by Matt Svoboda on 11/14/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

/// `VideoGeometry`: collection of metadata for the current video.
///
/// Mimics mpv's calculations rather than relying on the libmpv render API, which suffers from ambiguities
/// which can lead to errors in time-critical situations.
///
/// Processing pipeline:
/// `videoSizeRaw` (`rawWidth`, `rawHeight`)
///   ➤ Parse `selectedCropLabel` into `cropRect`, then apply it
///     ➤ `videoSizeC`: (`videoWidthC` x `videoHeightC`), AKA "dsize", per mpv usage)
///       ➤ Parse `userAspectLabel` into `aspectRatioOverride`, then apply it
///         ➤ `videoSizeCA`
///           ➤ apply `totalRotation` (== `userRotation` + `decodedRotation`)
///             ➤ `videoSizeCAR`
struct VideoGeometry: Equatable, CustomStringConvertible {
  typealias Transform = (GeometryTransform.Context) -> VideoGeometry?

  static func defaultGeometry(_ log: Logger.Subsystem? = nil) -> VideoGeometry {
    let log = log ?? Logger.log
    return VideoGeometry(rawWidth: Constants.DefaultVideoSize.rawWidth,
                         rawHeight: Constants.DefaultVideoSize.rawHeight,
                         decodedAspectLabel: Constants.DefaultVideoSize.aspectLabel, userAspectLabel: "",
                         decodedRotation: 0, userRotation: 0,
                         selectedCropLabel: AppData.noneCropIdentifier,
                         log: log)
  }

  /// Uses Spotify's standard 1600x1600 dimensions, but the only important property is that its aspect ratio is square.
  static func albumArtGeometry(_ log: Logger.Subsystem? = nil) -> VideoGeometry {
    let log = log ?? Logger.log
    return VideoGeometry(rawWidth: Constants.AlbumArt.rawWidth, rawHeight: Constants.AlbumArt.rawHeight,
                         decodedAspectLabel: "1:1", userAspectLabel: "",
                         decodedRotation: 0, userRotation: 0,
                         selectedCropLabel: AppData.noneCropIdentifier,
                         log: log)
  }

  let log: Logger.Subsystem

  init(rawWidth: Int, rawHeight: Int,
       decodedAspectLabel: String, userAspectLabel: String,
       decodedRotation: Int, userRotation: Int,
       selectedCropLabel: String,
       log: Logger.Subsystem) {
    self.rawWidth = rawWidth
    self.rawHeight = rawHeight
    self.decodedAspectLabel = decodedAspectLabel
    if Aspect.isValid(userAspectLabel) {
      self.userAspectLabel = userAspectLabel
    } else {
      self.userAspectLabel = Aspect.defaultIdentifier
    }
    self.decodedRotation = decodedRotation
    self.userRotation = userRotation
    self.selectedCropLabel = selectedCropLabel
    let cropRect = VideoGeometry.makeCropRect(fromCropLabel: selectedCropLabel, rawWidth: rawWidth, rawHeight: rawHeight)
    self.cropRect = cropRect
    if let cropRect {
      self.cropRectNormalized = VideoGeometry.makeCropRectNormalized(videoSizeRaw: CGSize(width: rawWidth, height: rawHeight), cropRect: cropRect, log: log)
    } else {
      self.cropRectNormalized = nil
    }
    self.log = log
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
  var videoSizeRaw: CGSize {
    return CGSize(width: rawWidth, height: rawHeight)
  }

  // MARK: - Substitution convenience functions

  func clone(rawWidth: Int? = nil, rawHeight: Int? = nil,
             decodedAspectLabel: String? = nil,
             userAspectLabel: String? = nil,
             decodedRotation: Int? = nil, userRotation: Int? = nil,
             selectedCropLabel: String? = nil, _ log: Logger.Subsystem? = nil) -> VideoGeometry {
    return VideoGeometry(rawWidth: rawWidth ?? self.rawWidth, rawHeight: rawHeight ?? self.rawHeight,
                         decodedAspectLabel: decodedAspectLabel ?? self.decodedAspectLabel,
                         userAspectLabel: userAspectLabel ?? self.userAspectLabel,
                         decodedRotation: decodedRotation ?? self.decodedRotation, userRotation: userRotation ?? self.userRotation,
                         selectedCropLabel: selectedCropLabel ?? self.selectedCropLabel, log: log ?? self.log)
  }

  func substituting(_ ffMeta: FFVideoMeta, _ log: Logger.Subsystem? = nil) -> VideoGeometry {
    return clone(rawWidth: ffMeta.width, rawHeight: ffMeta.height, decodedRotation: ffMeta.streamRotation, log)
  }

  // MARK: - TRANSFORMATION 1: Crop

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

  let cropRectNormalized: CGRect?

  /// The video size after crop applied, or raw video size if no crop applied.
  /// Equal to crop rect size, if crop applied. If there is no crop, then identical to raw video size.
  var videoSizeC: CGSize {
    if let cropRect {
      return cropRect.size
    }
    return videoSizeRaw
  }

  var videoAspectC: Double {
    return videoSizeC.mpvAspect
  }

  var cropFilter: MPVFilter? {
    return buildCropFilter(from: selectedCropLabel)
  }

  func buildCropFilter(from cropLabel: String) -> MPVFilter? {
    if cropLabel.isEmpty || cropLabel == AppData.noneCropIdentifier {
      return nil
    }

    if let aspect = Aspect(string: cropLabel)  {
      let cropped = videoSizeRaw.crop(withAspect: aspect.value)
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
  
  // MARK: - TRANSFORMATION 2: Aspect
  // (Crop + Aspect)

  /// The video's aspect ratio. This may be the result of applying pixel aspect ratio, etc, and may be different than
  /// simple width / height.
  ///
  /// This is a string so that it can be used to identify the currently selected aspect in the Video menu & in the Video Settings
  /// sidebar's segmented control. It ideally should be in the format `"W:H"` to match the UI and avoid number rounding issues,
  /// but this is also allowed to contain a decimal number (only the first 2 digits of its decimal will be read, however).
  let decodedAspectLabel: String

  /// The currently applied aspect ratio override.
  ///
  /// This is a string so that it can be used to identify the currently selected aspect in the Video menu & in the Video Settings
  /// sidebar's segmented control. It ideally should be in the format `"W:H"` to match the UI and avoid number rounding issues,
  /// but this is also allowed to contain a decimal number (only the first 2 digits of its decimal will be read, however).
  ///
  /// This roughly corresponds to mpv's `--video-aspect-override` option. But does not allow values of `0` or `no` to
  /// use square pixels.
  let userAspectLabel: String

  /// Same as `userAspectLabel`, but in Double format, or `nil` if no change from codec aspect.
  private var aspectRatioOverride: Double? {
    Aspect(string: userAspectLabel)?.doubleValue
  }

  /// The video size, after crop + aspect override applied, but before rotation or final scaling.
  ///
  /// From the mpv manual:
  /// ```
  /// dwidth, dheight
  /// Video display size. This is the video size after filters and aspect scaling have been applied. The actual
  /// video window size can still be different from this, e.g. if the user resized the video window manually.
  /// These have the same values as video-out-params/dw and video-out-params/dh.
  /// ```
  var videoSizeCA: CGSize {
    var videoSize = videoSizeC

    // FIXME: this is still not consistent with mpv when crop + container aspect are active!
    if let codecAspect = Aspect(string: decodedAspectLabel),
       !Aspect.looselyEquals(codecAspect.value, videoSizeRaw.aspect) {
      // mpv uses some fuzzy matching here. Let's do the same
      videoSize = VideoGeometry.applyAspectOverride(codecAspect.value, to: videoSize)
    }
    return VideoGeometry.applyAspectOverride(aspectRatioOverride, to: videoSize)
  }

  var videoAspectCA: Double {
    return videoSizeCA.mpvAspect
  }

  // MARK: - TRANSFORMATION 3: Rotation
  // (Crop + Aspect + Rotation)

  /// decodedRotation = (totalRotation - userRotation) %% 360
  let decodedRotation: Int

  /// `MPVProperty.videoRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVOption.Video.videoRotate` ("video-rotate").
  /// Not to be confused with the `MPVProperty.videoParamsRotate` ("video-params/rotate")
  let userRotation: Int

  /// `MPVProperty.videoParamsRotate`.
  ///
  /// Is refreshed as property change events arrive for `MPVProperty.videoParamsRotate` ("video-params/rotate")
  /// IINA only supports one of [0, 90, 180, 270]
  var totalRotation: Int {
    return (decodedRotation + userRotation) %% 360
  }

  var isWidthSwappedWithHeightByTotalRotation: Bool {
    // 90, 270, etc...
    (totalRotation %% 180) != 0
  }

  /// Like `videoSizeCA`, but after applying `totalRotation`.
  var videoSizeCAR: CGSize {
    let videoSizeCA = videoSizeCA
    if isWidthSwappedWithHeightByTotalRotation {
      return CGSize(width: videoSizeCA.height, height: videoSizeCA.width)
    }
    return videoSizeCA
  }

  /// Final aspect ratio which takes into account pixel aspect, aspect override, crop, and rotation (scale-invariant).
  ///
  /// The aspect constraint in `videoView` should attempt to come as close to this as possible (but usually cannot because the view's
  /// dimensions are limited to whole numbers).
  /// If displaying album art, this will be `1` (square).
  var videoAspectCAR: Double {
    return videoSizeCAR.mpvAspect
  }

  // MARK: - Protocol conformance

  var description: String {
    return "VidGeo(crop:\(selectedCropLabel.description.quoted)|\(cropRect?.description ?? "nil") aspect:\(decodedAspectLabel.quoted)→\(userAspectLabel.quoted) rot:…+\(userRotation)=\(totalRotation)° raw:\(videoSizeRaw) CA:\(videoSizeCA) CAR:\(videoSizeCAR)|\(videoAspectCAR))"
  }

  static func == (lhs: VideoGeometry, rhs: VideoGeometry) -> Bool {
    return lhs.rawWidth == rhs.rawWidth
    && lhs.decodedAspectLabel == rhs.decodedAspectLabel
    && lhs.userAspectLabel == rhs.userAspectLabel
    && lhs.decodedRotation == rhs.decodedRotation
    && lhs.userRotation == rhs.userRotation
    && lhs.selectedCropLabel == rhs.selectedCropLabel
  }

  static func != (lhs: VideoGeometry, rhs: VideoGeometry) -> Bool {
    return !(lhs == rhs)
  }

  // MARK: Static util functions

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

  static func makeCropRectNormalized(videoSizeRaw: CGSize, cropRect: CGRect, log: Logger.Subsystem) -> CGRect? {
    let xNorm = cropRect.origin.x / videoSizeRaw.width
    let yNorm = cropRect.origin.y / videoSizeRaw.height
    let widthNorm = cropRect.width / videoSizeRaw.width
    let heightNorm = cropRect.height / videoSizeRaw.height
    let normRect = NSRect(x: xNorm, y: yNorm, width: widthNorm, height: heightNorm)
    log.trace{"Normalized cropRect \(cropRect) → \(normRect)"}
    guard widthNorm > 0, heightNorm > 0 else {
      log.warn("Invalid cropRect! Returning nil")
      return nil
    }
    return normRect
  }

  /// Adjusts the dimensions of the given `CGSize` as needed to match the given aspect
  static func applyAspectOverride(_ newAspect: Double?, to origSize: CGSize) -> CGSize {
    guard let newAspect else {
      // No aspect override
      return origSize
    }
    if origSize.mpvAspect == Aspect.mpvPrecision(of: newAspect) {
      return origSize
    }
    let origAspect = origSize.aspect
    if origAspect > newAspect {
      return CGSize(width: origSize.width, height: round(origSize.height * origAspect / newAspect))
    }
    return CGSize(width: round(origSize.width / origAspect * newAspect), height: origSize.height)
  }

}
