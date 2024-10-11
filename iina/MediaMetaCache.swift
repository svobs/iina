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

  init(duration: Double?, progress: Double?, title: String?, album: String?, artist: String?) {
    self.duration = duration
    self.progress = progress
    // Sometimes newlines end up in the metadata (and on Windows these also include "\r" as well). Strip them for better visibility:
    self.title = title?.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
    self.album = album
    self.artist = artist
  }

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
  private var cachedMeta: [URL: MediaMeta] = [:]
  private var cachedFFMeta: [URL: FFVideoMeta] = [:]

  func fillInVideoSizes(_ videoFiles: [FileInfo], onBehalfOf player: PlayerCore) {
    let log = player.log
    log.verbose("Filling in video sizes for \(videoFiles.count) files...")
    let sw = Utility.Stopwatch()
    var updateCount = 0
    for fileInfo in videoFiles {
      guard player.state.isNotYet(.stopping) else {
        log.verbose("Stopping after \(updateCount)/\(videoFiles.count) video sizes due to player stopping")
        return
      }
      if getCachedVideoMeta(forURL: fileInfo.url) == nil {
        if reloadCachedVideoMeta(forURL: fileInfo.url) != nil {
          updateCount += 1
        }
      }
    }
    log.verbose("Filled in \(updateCount)/\(videoFiles.count) video sizes in \(sw) ms")
  }


  func calculateTotalDuration(_ urls: [URL]) -> Double {
    metaLock.withLock {
      return urls.compactMap { cachedMeta[$0]?.duration }.reduce(0, +)
    }
  }

  func getCachedMeta(for url: URL) -> MediaMeta? {
    metaLock.withLock {
      return cachedMeta[url]
    }
  }

  func setCachedMediaDuration(_ url: URL, _ duration: Double) {
    guard duration > 0.0 else { return }
    metaLock.withLock {
      let oldMeta = cachedMeta[url] ?? MediaMeta.empty
      cachedMeta[url] = oldMeta.clone(duration: duration)
    }
  }

  func setCachedMediaDurationAndProgress(_ url: URL, duration: Double?, progress: Double?) {
    metaLock.withLock {
      let oldMeta = cachedMeta[url] ?? MediaMeta.empty
      cachedMeta[url] = oldMeta.clone(duration: duration, progress: progress)
    }
  }

  // MARK: - Artist, title meta

  /**
   Fetch video duration, playback progress, and name metadata, then save it to cache.
   It may take some time to run this method, so it should be used in background.
   Note: This only works for file paths (not network streams)!
   */
  @discardableResult
  func updateCache(for url: URL, reloadFromWatchLater: Bool = true, reloadFromFFmpeg: Bool = true,
                   mpvTitle: String? = nil, mpvAlbum: String? = nil, mpvArtist: String? = nil) -> MediaMeta? {

    var progress: Double? = nil
    var duration: Double? = nil

    var title: String? = nil
    var album: String? = nil
    var artist: String? = nil

    if url.isFileURL {
      if reloadFromWatchLater {
        progress = Utility.playbackProgressFromWatchLater(url.path.md5)
      }

      if reloadFromFFmpeg, let dict = FFmpegController.probeVideoInfo(forFile: url.path) {

        duration = dict["@iina_duration"] as? Double

        dict.forEach { (k, v) in
          guard let key = k as? String else { return }
          switch key.lowercased() {
          case "title":
            title = v as? String
          case "album":
            album = v as? String
          case "artist":
            artist = v as? String
          default:
            break
          }
        }
      }
    }

    // Favor mpv properties
    if let mpvTitle {
      title = mpvTitle
    }
    if let mpvAlbum {
      album = mpvAlbum
    }
    if let mpvArtist {
      artist = mpvArtist
    }

    return metaLock.withLock {
      let oldMeta = cachedMeta[url] ?? MediaMeta.empty
      let newMeta = oldMeta.clone(duration: duration, progress: progress,
                                  title: title, album: album, artist: artist)
      cachedMeta[url] = newMeta
      Logger.log.verbose("[reloadCachedMeta] Reloaded URL \(Playback.path(from: url).pii.quoted) ≔ \(newMeta)")
      return newMeta
    }
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
    let path = Playback.path(from: url)
    guard Utility.playableFileExt.contains(path.lowercasedPathExtension) else {
      log.verbose("Skipping ffMeta check; not a playable file: \(path.pii.quoted)")
      return nil
    }

    var missed = false
    var ffMeta = getCachedVideoMeta(forURL: url)
    if ffMeta == nil {
      missed = true
      ffMeta = reloadCachedVideoMeta(forURL: url)
    }

    guard let ffMeta else {
      log.error("Unable to find ffMeta from either cache or ffmpeg for \(path.pii.quoted)")
      return nil
    }
    log.debug("Found ffMeta via \(missed ? "ffmpeg" : "cache"): \(ffMeta), for \(path.pii.quoted)")
    return ffMeta
  }

}
