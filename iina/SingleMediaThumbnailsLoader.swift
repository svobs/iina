//
//  CurrentMediaThumbnails.swift
//  iina
//
//  Created by Matt Svoboda on 12/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

struct Thumbnail {
  let image: CGImage
  let timestamp: Double

  var nsImage: NSImage {
    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
  }
}

class SingleMediaThumbnailsLoader: NSObject, FFmpegControllerDelegate {
  unowned let player: PlayerCore!
  let queueTicket: Int
  let mediaFilePath: String
  let mediaFilePathMD5: String
  let videoTrackID: Int
  let thumbnailWidth: Int
  let rotationDegrees: Int

  private(set) var isCancelled = false
  var thumbnailsProgress: Double = 0
  var ffThumbnails: [FFThumbnail] = []
  var thumbnails: [Thumbnail] = []
  var currentDisplayedThumbFFTimestamp: Double = -1

  lazy var ffmpegController: FFmpegController = {
    let controller = FFmpegController()
    controller.delegate = self
    return controller
  }()

  var log: Logger.Subsystem {
    return player.log
  }

  init(_ player: PlayerCore, queueTicket: Int, mediaFilePath: String, mediaFilePathMD5: String, videoTrackID: Int, thumbnailWidth: Int, rotationDegrees: Int) {
    self.player = player
    self.queueTicket = queueTicket
    self.mediaFilePath = mediaFilePath
    self.mediaFilePathMD5 = mediaFilePathMD5
    self.videoTrackID = videoTrackID
    self.thumbnailWidth = thumbnailWidth
    self.rotationDegrees = rotationDegrees
  }

  /// We want the requested length of thumbnail to correspond to whichever video dimension is longer, and then get the corresponding width.
  /// Example: if video's native size is 600 W x 800 H and requested thumbnail size is 100, then `thumbWidth` should be 75.
  static func determineWidthOfThumbnail(from videoSizeRaw: NSSize, log: Logger.Subsystem) -> Int {
    let sizeOption: Preference.ThumbnailSizeOption = Preference.enum(for: .thumbnailSizeOption)
    switch sizeOption {
    case .scaleWithViewport:
      let rawSizePercentage = CGFloat(min(max(0, Preference.integer(for: .thumbnailRawSizePercentage)), 100))
      let thumbWidth = Int(round(videoSizeRaw.width * rawSizePercentage / 100))
      log.verbose("Thumbnail native width will be \(Int(videoSizeRaw.width))px * \(Int(rawSizePercentage))% → \(thumbWidth)px")
      return thumbWidth
    case .fixedSize:
      let requestedLength = CGFloat(Preference.integer(for: .thumbnailFixedLength))
      let thumbWidth: CGFloat
      if videoSizeRaw.height > videoSizeRaw.width {
        // Match requested size to video height
        if requestedLength > videoSizeRaw.height {
          // Do not go bigger than video's native width
          thumbWidth = videoSizeRaw.width
          log.debug("Video's height is longer than its width, & thumbLength (\(requestedLength)) is larger than video's native height (\(videoSizeRaw.height)); clamping thumbWidth to \(videoSizeRaw.width)")
        } else {
          thumbWidth = round(requestedLength * videoSizeRaw.aspect)
          log.debug("Video's height (\(videoSizeRaw.height)) is longer than its width (\(videoSizeRaw.width)); scaling down thumbWidth to \(thumbWidth)")
        }
      } else {
        // Match requested size to video width
        if requestedLength > videoSizeRaw.width {
          log.debug("Requested thumblLength (\(requestedLength)) is larger than video's native width; clamping thumbWidth to \(videoSizeRaw.width)")
          thumbWidth = videoSizeRaw.width
        } else {
          thumbWidth = requestedLength
        }
      }
      let thumbWidthInt = Int(thumbWidth)
      log.verbose("Using fixed thumbnail width of \(thumbWidthInt)")
      return thumbWidthInt
    }
  }

  func loadThumbnails() {
    assert(DispatchQueue.isExecutingIn(PlayerCore.thumbnailQueue))

    guard FileManager.default.fileExists(atPath: mediaFilePath) else {
      log.debug("Aborting thumbnails load. File does not exist: \(mediaFilePath.pii.quoted)")
      return
    }

    let cacheName = mediaFilePathMD5
    if ThumbnailCache.fileIsCached(forName: cacheName, forVideo: mediaFilePath, forWidth: thumbnailWidth) {
      log.debug{"Found matching thumbnail cache \(cacheName.quoted), \(thumbnailWidth)px width for: \(mediaFilePath.pii.quoted)"}
      if let thumbnails = ThumbnailCache.read(forName: cacheName, forWidth: thumbnailWidth) {
        if thumbnails.count >= AppData.minThumbnailsPerFile {
          addThumbnails(thumbnails)
          thumbnailsProgress = 1
          DispatchQueue.main.async{ [self] in
            player.refreshTouchBarSlider()
          }
          return
        } else {
          log.error("Expected at least \(AppData.minThumbnailsPerFile) thumbnails, but found only \(thumbnails.count) (width \(thumbnailWidth)px). Will try to regenerate")
        }
      } else {
        log.error("Cannot read thumbnails from cache \(cacheName.quoted), width \(thumbnailWidth)px. Will try to regenerate")
      }
    }

    log.debug("Generating new thumbnails for file \(mediaFilePath.pii.quoted), width=\(thumbnailWidth)")
    ffmpegController.generateThumbnail(forFile: mediaFilePath, thumbWidth:Int32(thumbnailWidth))
  }

  private func addThumbnails(_ ffThumbnails: [FFThumbnail]) {
    let sw = Utility.Stopwatch()
    if rotationDegrees != 0 {
      log.verbose("Rotating \(ffThumbnails.count) thumbnails by \(rotationDegrees)° clockwise")
    }

    // FFmpegController can send duplicates. Weed them out by timestamp
    var existingTimestamps = Set(self.thumbnails.compactMap{ $0.timestamp })

    var addedCount: Int = 0
    for ffThumbnail in ffThumbnails {
      guard !existingTimestamps.contains(ffThumbnail.realTime) else { continue }
      guard let rawImage = ffThumbnail.image?.cgImage else { continue }

      let image: CGImage
      if rotationDegrees != 0 {
        // Rotation is an expensive procedure. Do it up front so that thumbnail display is snappier.
        // Reverse the rotation direction because mpv is opposite direction of Core Graphics
        image = rawImage.rotated(degrees: -rotationDegrees)
      } else {
        image = rawImage
      }
      self.ffThumbnails.append(ffThumbnail)
      let thumb = Thumbnail(image: image, timestamp: ffThumbnail.realTime)
      self.thumbnails.append(thumb)
      existingTimestamps.insert(ffThumbnail.realTime)
      addedCount += 1
    }

    if rotationDegrees != 0 {
      log.verbose{"Rotated \(addedCount) thumbnails in \(sw) ms"}
    }
  }

  func getThumbnail(forSecond sec: Double) -> Thumbnail? {
    guard !thumbnails.isEmpty else { return nil }
    var tb = thumbnails.last!
    for i in 0..<thumbnails.count {
      if thumbnails[i].timestamp >= sec {
        tb = thumbnails[(i == 0 ? i : i - 1)]
        break
      }
    }
    return tb
  }

  func invalidateDisplayedThumbnail() {
    currentDisplayedThumbFFTimestamp = -1
  }

  // MARK: - FFmpegControllerDelegate implementation

  func didUpdate(_ thumbnails: [FFThumbnail]?, forFile filename: String, thumbWidth width: Int32, withProgress progress: Int) {
    // quick & dirty workaround for indexing method discrepancy: just add 1
    let progress = progress + 1
    guard !isCancelled else {
      log.debug("Discarding thumbnails update (\(width)px width, progress \(progress)) due to cancel")
      return
    }
    guard mediaFilePath == filename, width == thumbnailWidth else {
      log.warn("Discarding thumbnails update (\(width)px width, progress \(progress)): either sourcePath or thumbnailWidth does not match expected")
      return
    }
    let targetCount = ffmpegController.thumbnailCount + 1
    PlayerCore.thumbnailQueue.async { [self] in
      guard queueTicket == player.thumbnailQueueTicket else {
        isCancelled = true
        return
      }
      if let thumbnails = thumbnails, thumbnails.count > 0 {
        addThumbnails(thumbnails)
      }
      log.debug("Got \(thumbnails?.count ?? 0) more \(width)px thumbs (\(self.thumbnails.count) so far), progress: \(progress) / \(targetCount)")
      thumbnailsProgress = Double(progress) / Double(targetCount)
      DispatchQueue.main.async { [self] in
        // TODO: this call is currently unnecessary. But should add code to make thumbnails displayable as they come in.
        player.refreshTouchBarSlider()
      }
    }
  }

  func didGenerate(_ thumbnails: [FFThumbnail], forFile filename: String, thumbWidth width: Int32, succeeded: Bool) {
    guard !isCancelled else {
      log.debug("Discarding thumbnails (\(width)px), due to cancel")
      return
    }
    guard mediaFilePath == filename, width == thumbnailWidth else {
      log.error("Ignoring generated thumbnails (\(width)px width): either filePath or thumbnailWidth does not match expected")
      return
    }

    PlayerCore.thumbnailQueue.async { [self] in
      guard queueTicket == player.thumbnailQueueTicket else {
        isCancelled = true
        return
      }
      if thumbnails.count > 0 {
        log.verbose("Got final count of \(thumbnails.count) thumbs, width=\(width)px")
        addThumbnails(thumbnails)
      }
      log.debug("Done generating thumbnails, success=\(succeeded.yn) count=\(self.thumbnails.count) width=\(width)px")
      guard succeeded else { return }

      player.refreshTouchBarSlider()
      guard !ffThumbnails.isEmpty else {
        log.verbose("No thumbnails to write")
        return
      }
      ThumbnailCache.write(ffThumbnails, forName: mediaFilePathMD5, forVideo: mediaFilePath, forWidth: Int(width))
      ffThumbnails = []  // free the memory - not needed anymore
    }
    player.events.emit(.thumbnailsReady)
  }
}
