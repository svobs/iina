//
//  MediaMetaCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-09-22.
//  Copyright © 2024 lhc. All rights reserved.
//

struct FFVideoMeta {
  let width: Int
  let height: Int
  /// Should match mpv's `video-params/rotate`
  let streamRotation: Int
}

/// Singleton for all app meta.
///
/// But currently separates meta categories into different lists.
/// Not retained across app launches.
class MediaMetaCache {
  static let shared = MediaMetaCache()

  private let metaLock = Lock()
  private var cachedFFMeta: [URL: FFVideoMeta] = [:]

  // The cache is read by the main thread and updated by a background thread therefore all use
  // must be through the class methods that properly coordinate thread access.
  private var cachedMediaDurationAndProgress: [String: (duration: Double?, progress: Double?)] = [:]
  private var cachedNameMeta: [String: (title: String?, album: String?, artist: String?)] = [:]

  func calculateTotalDuration(_ urlPaths: [String]) -> Double {
    metaLock.withLock {
      return urlPaths.compactMap { cachedMediaDurationAndProgress[$0]?.duration }
        .reduce(0, +)
    }
  }

  func getCachedMediaDurationAndProgress(_ urlPath: String) -> (duration: Double?, progress: Double?)? {
    metaLock.withLock {
      return cachedMediaDurationAndProgress[urlPath]
    }
  }

  func setCachedMediaDuration(_ urlPath: String, _ duration: Double) {
    guard duration > 0.0 else { return }
    metaLock.withLock {
      var meta = cachedMediaDurationAndProgress[urlPath] ?? (duration: nil, progress: nil)
      meta.duration = duration
      cachedMediaDurationAndProgress[urlPath] = meta
    }
  }

  func setCachedMediaDurationAndProgress(_ urlPath: String, _ value: (duration: Double?, progress: Double?)) {
    metaLock.withLock {
      return cachedMediaDurationAndProgress[urlPath] = value
    }
  }

  // MARK: - Artist, title meta

  private func getCachedNameMeta(_ urlPath: String) -> (title: String?, album: String?, artist: String?)? {
    metaLock.withLock {
      cachedNameMeta[urlPath]
    }
  }

  /// Both `artist` & `title` must be present, or `nil` is returned
  func getCachedNameMeta(forMediaPath urlPath: String) -> (artist: String, title: String)? {
    guard let metadata = getCachedNameMeta(urlPath) else { return nil }
    guard let artist = metadata.artist, let title = metadata.title else { return nil }
    return (artist, title)
  }

  func setCachedNameMeta(forMediaPath urlPath: String, to value: (title: String?, album: String?, artist: String?)) {
    metaLock.withLock {
      cachedNameMeta[urlPath] = value
    }
  }

  /**
   Fetch video duration, playback progress, and name metadata, then save it to cache.
   It may take some time to run this method, so it should be used in background.
   Note: This only works for file paths (not network streams)!
   */
  func reloadCachedNameMeta(forMediaPath urlPath: String) {
    guard let url = Playback.url(fromPath: urlPath) else {
      Logger.log.debug("[updateCachedMeta] Could not create URL from path, skipping: \(urlPath.pii.quoted)")
      return
    }
    guard url.isFileURL else {
      Logger.log.verbose("[updateCachedMeta] Not a file; skipping: \(urlPath.pii.quoted)")
      return
    }
    guard let dict = FFmpegController.probeVideoInfo(forFile: urlPath) else { return }
    let progress = Utility.playbackProgressFromWatchLater(urlPath.md5)
    MediaMetaCache.shared.setCachedMediaDurationAndProgress(urlPath, (
      duration: dict["@iina_duration"] as? Double,
      progress: progress?.second
    ))
    var result: (title: String?, album: String?, artist: String?)
    dict.forEach { (k, v) in
      guard let key = k as? String else { return }
      switch key.lowercased() {
      case "title":
        result.title = v as? String
      case "album":
        result.album = v as? String
      case "artist":
        result.artist = v as? String
      default:
        break
      }
    }
    setCachedNameMeta(forMediaPath: urlPath, to: result)
  }


  // MARK: - Video Meta

  func getCachedVideoMeta(forURL url: URL?) -> FFVideoMeta? {
    guard let url else { return nil }
    guard url.isFileURL else { return nil }
    guard url.absoluteString != "stdin" else { return nil }

    var ffMeta: FFVideoMeta? = nil
    metaLock.withLock {
      if let cachedMeta = cachedFFMeta[url] {
        ffMeta = cachedMeta
      }
    }
    return ffMeta
  }

  func reloadCachedVideoMeta(forURL url: URL?) -> FFVideoMeta? {
    guard let url else { return nil }
    guard url.isFileURL else { return nil }
    guard url.absoluteString != "stdin" else { return nil }  // do not cache stdin!
    guard FileManager.default.fileExists(atPath: url.path) else {
      Logger.log.verbose("Skipping ffMeta update, file does not exist: \(url.path.pii.quoted)")
      return nil
    }

    if let sizeArray = FFmpegController.readVideoSize(forFile: url.path) {
      let ffMeta = FFVideoMeta(width: Int(sizeArray[0]), height: Int(sizeArray[1]), streamRotation: Int(sizeArray[2]))
      metaLock.withLock {
        // Don't let this get too big
        if cachedFFMeta.count > Constants.SizeLimit.maxCachedVideoSizes {
          Logger.log.debug("Too many cached FF meta entries (count=\(cachedFFMeta.count); maximum=\(Constants.SizeLimit.maxCachedVideoSizes)). Clearing cached FF meta...")
          cachedFFMeta.removeAll()
        }
        cachedFFMeta[url] = ffMeta
      }
      return ffMeta
    } else {
      Logger.log("Failed to read video size for file \(url.path.pii.quoted)", level: .error)
    }
    return nil
  }

  func ensureVideoMetaIsCached(forURL url: URL?, _ log: Logger.Subsystem) {
    _ = getOrReadVideoMeta(forURL: url, log)
  }

  func getOrReadVideoMeta(forURL url: URL?, _ log: Logger.Subsystem) -> FFVideoMeta? {
    guard let url else { return nil }
    guard url.isFileURL else {
      log.verbose("Skipping ffMeta check; not a file URL: \(url.absoluteString.pii.quoted)")
      return nil
    }
    guard Utility.playableFileExt.contains(url.absoluteString.lowercasedPathExtension) else {
      log.verbose("Skipping ffMeta check; not a playable file URL: \(url.absoluteString.pii.quoted)")
      return nil
    }

    var missed = false
    var ffMeta = getCachedVideoMeta(forURL: url)
    if ffMeta == nil {
      missed = true
      ffMeta = reloadCachedVideoMeta(forURL: url)
    }
    let path = Playback.path(for: url)

    guard let ffMeta else {
      log.error("Unable to find ffMeta from either cache or ffmpeg for \(path.pii.quoted)")
      return nil
    }
    log.debug("Found ffMeta via \(missed ? "ffmpeg" : "cache"): \(ffMeta), for \(path.pii.quoted)")
    return ffMeta
  }

}
