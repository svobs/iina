//
//  MediaMetaCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-09-22.
//  Copyright © 2024 lhc. All rights reserved.
//

// TODO: consider merging this with MediaMeta
struct FFVideoMeta {
  let width: Int
  let height: Int
  /// Should match mpv's `video-params/rotate`
  let streamRotation: Int
}

struct MediaMeta {
  static let empty: MediaMeta = .init(duration: nil, progress: nil, title: nil, album: nil, artist: nil)

  let duration: Double?
  let progress: Double?
  let title: String?
  let album: String?
  let artist: String?

  func clone(duration: Double? = nil, progress: Double? = nil,
             title: String? = nil, album: String? = nil, artist: String? = nil) -> MediaMeta {
    return MediaMeta(duration: duration ?? self.duration, progress: progress ?? self.progress,
                     title: title ?? self.title, album: album ?? self.album, artist: artist ?? self.artist)
  }
}

/// Singleton for all app meta.
///
/// But currently separates meta categories into different lists.
/// Not retained across app launches.
class MediaMetaCache {
  static let shared = MediaMetaCache()

  private let metaLock = Lock()
  private var cachedMeta: [String: MediaMeta] = [:]
  private var cachedFFMeta: [URL: FFVideoMeta] = [:]


  func calculateTotalDuration(_ urlPaths: [String]) -> Double {
    metaLock.withLock {
      return urlPaths.compactMap { cachedMeta[$0]?.duration }
        .reduce(0, +)
    }
  }

  func getCachedMeta(forMediaPath urlPath: String) -> MediaMeta? {
    metaLock.withLock {
      return cachedMeta[urlPath]
    }
  }

  func setCachedMediaDuration(_ urlPath: String, _ duration: Double) {
    guard duration > 0.0 else { return }
    metaLock.withLock {
      let oldMeta = cachedMeta[urlPath] ?? MediaMeta.empty
      cachedMeta[urlPath] = oldMeta.clone(duration: duration)
    }
  }

  func setCachedMediaDurationAndProgress(_ urlPath: String, duration: Double?, progress: Double?) {
    metaLock.withLock {
      let oldMeta = cachedMeta[urlPath] ?? MediaMeta.empty
      cachedMeta[urlPath] = oldMeta.clone(duration: duration, progress: progress)
    }
  }

  // MARK: - Artist, title meta

  @discardableResult
  func setCachedTitle(forMediaPath urlPath: String, to title: String?) -> MediaMeta? {
    metaLock.withLock {
      let oldMeta = cachedMeta[urlPath] ?? MediaMeta.empty
      let newMeta = oldMeta.clone(title: title)
      cachedMeta[urlPath] = newMeta
      return newMeta
    }
  }

  /**
   Fetch video duration, playback progress, and name metadata, then save it to cache.
   It may take some time to run this method, so it should be used in background.
   Note: This only works for file paths (not network streams)!
   */
  @discardableResult
  func reloadCachedMeta(forMediaPath urlPath: String, mpvTitle: String? = nil) -> MediaMeta? {
    guard let url = Playback.url(fromPath: urlPath) else {
      Logger.log.debug("[reloadCachedMeta] Could not create URL from path, skipping: \(urlPath.pii.quoted)")
      return nil
    }

    var result: (duration: Double?, progress: Double?, title: String?, album: String?, artist: String?)

    if url.isFileURL, let dict = FFmpegController.probeVideoInfo(forFile: urlPath) {
      let progress = Utility.playbackProgressFromWatchLater(urlPath.md5)
      result.duration = dict["@iina_duration"] as? Double
      result.progress = progress?.second

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
    }

    // Favor mpv title
    if let mpvTitle {
      result.title = mpvTitle
    }

    let meta = MediaMeta(duration: result.duration, progress: result.progress,
                         title: result.title, album: result.album, artist: result.artist)
    Logger.log.debug("[reloadCachedMeta] Reloaded URL: \(urlPath.pii.quoted) = \(meta)")

    metaLock.withLock {
      cachedMeta[urlPath] = meta
    }
    return meta
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
