//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

struct FFVideoMeta {
  let width: Int
  let height: Int
  /// Should match mpv's `video-params/rotate`
  let streamRotation: Int
}

/// Current state of player's mpv core. Reused between playbacks. For a single playback, see class `Playback`.
class PlaybackInfo {
  unowned var log: Logger.Subsystem

  init(log: Logger.Subsystem) {
    self.log = log
  }

  /// Enumeration representing the status of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  ///
  /// The A-B loop command cycles mpv through these states:
  /// - Cleared (looping disabled)
  /// - A loop point set
  /// - B loop point set (looping enabled)
  enum LoopStatus: Int {
    case cleared = 0
    case aSet
    case bSet
  }

  // MARK: - Playback lifecycle state

  var isIdle: Bool = true

  /// Is `true` only while restore from previous launch is still in progress; `false` otherwise.
  var isRestoring = false

  /// Contains info needed to restore the UI state from a previous launch. Should only be used if `isRestoring==true`
  var priorState: PlayerSaveState? = nil

  var isFileLoaded: Bool {
    return currentPlayback?.isFileLoaded ?? false
  }

  var isFileLoadedAndSized: Bool {
    return currentPlayback?.state.isAtLeast(.loadedAndSized) ?? false
  }

  var shouldAutoLoadFiles: Bool = false
  var isMatchingSubtitles = false

  var isSeeking: Bool = false

  // -- PERSISTENT PROPERTIES BEGIN --

  var isPaused: Bool = false {
    willSet {
      if isPaused != newValue {
        log.verbose("Playback is \(newValue ? "PAUSED" : "PLAYING")")
      }
    }
  }
  var isPlaying: Bool {
    return !isPaused
  }
  var pauseStateWasChangedLocally = false

  var currentPlayback: Playback? = nil {
    didSet {
      log.verbose("Updated currentPlayback to \(currentPlayback?.description ?? "nil")")
    }
  }

  var currentURL: URL? {
    return currentPlayback?.url
  }

  var isNetworkResource: Bool {
    if let currentPlayback {
      return currentPlayback.isNetworkResource
    }
    return false
  }
  var mpvMd5: String? {
    return currentPlayback?.mpvMD5
  }

  var isMediaOnRemoteDrive: Bool {
    if let attrs = try? currentURL?.resourceValues(forKeys: Set([.volumeIsLocalKey])), !attrs.volumeIsLocal! {
      return true
    }
    return false
  }

  // MARK: - Geometry

  // When navigating in playlist, and user does not have any other predefined resizing strategy, try to maintain the same window width
  // even for different video sizes and aspect ratios. Since it may not be possible to fit all videos onscreen, some videos will need to
  // be shrunk down, and over time this would lead to the window shrinking into the smallest size. Instead, remember the last window size
  // which the user manually chose, and try to match that across videos.
  //
  // This is also useful when opening outside sidebars:
  // When opening a sidebar and there is not enough space on screen, the viewport will be shrunk so that the sidebar can open while
  // keeping the window fully within the bounds of the screen. But when the sidebar is closed again, the viewport / window wiil be
  // expanded again to the preferred container size.
  var intendedViewportSize: NSSize? = nil {
    didSet {
      if let newValue = intendedViewportSize {
        log.verbose("Updated intendedViewportSize to \(newValue)")
      } else {
        log.verbose("Updated intendedViewportSize to nil")
      }
    }
  }

  // MARK: - Filters & Equalizers

  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilter: MPVFilter?
  var delogoFilter: MPVFilter?

  /// `[filter.name -> filter]`. Should be used on main thread only
  var videoFiltersDisabled: [String: MPVFilter] = [:]

  var deinterlace: Bool = false
  var hwdec: String = "no"
  var hwdecEnabled: Bool {
    hwdec != "no"
  }
  var hdrAvailable: Bool = false
  var hdrEnabled: Bool = true

  // video equalizer
  var brightness: Int = 0
  var contrast: Int = 0
  var saturation: Int = 0
  var gamma: Int = 0
  var hue: Int = 0

  var volume: Double = 50
  var isMuted: Bool = false

  // time
  var audioDelay: Double = 0
  var subDelay: Double = 0

  var abLoopStatus: LoopStatus = .cleared

  var playSpeed: Double = 1.0
  var videoPosition: VideoTime?
  var videoDuration: VideoTime?

  var playlist: [MPVPlaylistItem] = []
  var playlistPlayingPos: Int = -1  /// `MPVProperty.playlistPlayingPos`

  func constrainVideoPosition() {
    guard let duration = videoDuration, let position = videoPosition else { return }
    if position.second < 0 { videoPosition = VideoTime.zero }
    if position.second > duration.second { videoPosition = duration }
  }

  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  var vid: Int? {
    didSet {
      log.verbose("Video track changed to: \(vid?.description ?? "nil")")
    }
  }
  var aid: Int?
  var sid: Int?
  var secondSid: Int?

  var isAudioTrackSelected: Bool {
    if let aid {
      return aid != 0
    }
    return false
  }

  var isVideoTrackSelected: Bool {
    if let vid {
      return vid != 0
    }
    return false
  }

  /// If it return `nil`, it means do not change visibility from existing value
  var shouldShowDefaultArt: Bool? {
    if let currentPlayback {
      // Don't show art if currently loading
      if currentPlayback.state.isAtLeast(.loaded) {
        return !isVideoTrackSelected
      }
    }
    return nil
  }

  var isSubVisible = true
  var isSecondSubVisible = true

  enum CurrentMediaAudioStatus {
    case unknown
    case isAudio
    case notAudio
  }

  var currentMediaAudioStatus: CurrentMediaAudioStatus {
    guard !isNetworkResource else { return .notAudio }
    let noVideoTrack = videoTracks.isEmpty
    let noAudioTrack = audioTracks.isEmpty
    if noVideoTrack && noAudioTrack {
      return .unknown
    }
    if noVideoTrack {
      return .isAudio
    }
    let allVideoTracksAreAlbumCover = !videoTracks.contains { !$0.isAlbumart }
    if allVideoTracksAreAlbumCover {
      return .isAudio
    }
    return .notAudio
  }

  // -- PERSISTENT PROPERTIES END --

  var chapter = 0
  var chapters: [MPVChapter] = []

  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  var subTracks: [MPVTrack] = []

  var selectedSub: MPVTrack? {
    let selected = infoLock.withLock { subTracks.filter { $0.id == sid } }
    if selected.count > 0 {
      return selected[0]
    }
    return nil
  }

  func findExternalSubTrack(withURL url: URL) -> MPVTrack? {
    infoLock.withLock {
      return subTracks.first(where: { $0.externalFilename == url.path })
    }
  }

  func replaceTracks(audio: [MPVTrack], video: [MPVTrack], sub: [MPVTrack]) {
    infoLock.withLock {
      audioTracks = audio
      videoTracks = video
      subTracks = sub
    }
  }

  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    switch type {
    case .video: return videoTracks
    case .audio: return audioTracks
    case .sub, .secondSub: return subTracks
    }
  }

  func trackId(_ type: MPVTrack.TrackType) -> Int? {
    switch type {
    case .video: return vid
    case .audio: return aid
    case .sub: return sid
    case .secondSub: return secondSid
    }
  }

  func currentTrack(_ type: MPVTrack.TrackType) -> MPVTrack? {
    let id: Int?, list: [MPVTrack]
    switch type {
    case .video:
      id = vid
      list = videoTracks
    case .audio:
      id = aid
      list = audioTracks
    case .sub:
      id = sid
      list = subTracks
    case .secondSub:
      id = secondSid
      list = subTracks
    }
    if let id = id {
      return list.first { $0.id == id }
    } else {
      return nil
    }
  }

  var subEncoding: String?

  // Playlist metadata:
  var currentVideosInfo: [FileInfo] = []
  var currentSubsInfo: [FileInfo] = []
  /// Map: { video `path` for each `info` of `currentVideosInfo` -> `url` for each of `info.relatedSubs` }
  @Atomic var matchedSubs: [String: [URL]] = [:]

  func getMatchedSubs(_ file: String) -> [URL]? { $matchedSubs.withLock { $0[file] } }

  // MARK: - Cache

  var pausedForCache: Bool = false
  var cacheUsed: Int = 0
  var cacheSpeed: Int = 0
  var cacheTime: Int = 0
  var bufferingState: Int = 0

  // The cache is read by the main thread and updated by a background thread therefore all use
  // must be through the class methods that properly coordinate thread access.
  private var cachedVideoDurationAndProgress: [String: (duration: Double?, progress: Double?)] = [:]
  private var cachedMetadata: [String: (title: String?, album: String?, artist: String?)] = [:]

  private let infoLock = Lock()

  // TODO: move into its own class
  private static let ffMetaLock = Lock()
  private static var cachedFFMeta: [URL: FFVideoMeta] = [:]

  static func getCachedFFVideoMeta(forURL url: URL?) -> FFVideoMeta? {
    guard let url else { return nil }

    var ffMeta: FFVideoMeta? = nil
    ffMetaLock.withLock {
      if let cachedMeta = cachedFFMeta[url] {
        ffMeta = cachedMeta
      }
    }
    return ffMeta
  }

  static func updateCachedFFVideoMeta(forURL url: URL?) -> FFVideoMeta? {
    guard let url else { return nil }
    guard url.absoluteString != "stdin" else { return nil }  // do not cache stdin!
    if let sizeArray = FFmpegController.readVideoSize(forFile: url.path) {
      let ffMeta = FFVideoMeta(width: Int(sizeArray[0]), height: Int(sizeArray[1]), streamRotation: Int(sizeArray[2]))
      ffMetaLock.withLock {
        // Don't let this get too big
        if cachedFFMeta.count > Constants.SizeLimit.maxCachedVideoSizes {
          Logger.log("Too many cached FF meta entries (count=\(cachedFFMeta.count); maximum=\(Constants.SizeLimit.maxCachedVideoSizes)). Clearing cached FF meta...", level: .debug)
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

  static func getOrReadFFVideoMeta(forURL url: URL?, _ log: Logger.Subsystem) -> FFVideoMeta? {
    var missed = false
    var ffMeta = getCachedFFVideoMeta(forURL: url)
    if ffMeta == nil {
      missed = true
      ffMeta = updateCachedFFVideoMeta(forURL: url)
    }
    let path = Playback.path(for: url)

    guard let ffMeta else {
      log.error("Unable to find ffMeta from either cache or ffmpeg for \(path.pii.quoted)")
      return nil
    }
    log.debug("Found ffMeta via \(missed ? "ffmpeg" : "cache"): \(ffMeta), for \(path.pii.quoted)")
    return ffMeta
  }

  // end TODO

  func calculateTotalDuration() -> Double? {
    infoLock.withLock {
      let playlist: [MPVPlaylistItem] = playlist

      var totalDuration: Double? = 0
      for p in playlist {
        if let duration = cachedVideoDurationAndProgress[p.filename]?.duration {
          totalDuration! += duration > 0 ? duration : 0
        } else {
          // Cache is missing an entry, can't provide a total.
          return nil
        }
      }
      return totalDuration
    }
  }

  func calculateTotalDuration(_ indexes: IndexSet) -> Double {
    infoLock.withLock {
      let playlist = playlist
      return indexes
        .compactMap { $0 >= playlist.count ? nil : (cachedVideoDurationAndProgress[playlist[$0].filename]?.duration) }
        .compactMap { $0 > 0 ? $0 : 0 }
        .reduce(0, +)
    }
  }

  func getCachedVideoDurationAndProgress(_ file: String) -> (duration: Double?, progress: Double?)? {
    infoLock.withLock {
      cachedVideoDurationAndProgress[file]
    }
  }

  func setCachedVideoDuration(_ file: String, _ duration: Double) {
    infoLock.withLock {
      cachedVideoDurationAndProgress[file]?.duration = duration
    }
  }

  func setCachedVideoDurationAndProgress(_ file: String, _ value: (duration: Double?, progress: Double?)) {
    infoLock.withLock {
      cachedVideoDurationAndProgress[file] = value
    }
  }

  func getCachedMetadata(_ file: String) -> (title: String?, album: String?, artist: String?)? {
    infoLock.withLock {
      cachedMetadata[file]
    }
  }

  func setCachedMetadata(_ file: String, _ value: (title: String?, album: String?, artist: String?)) {
    infoLock.withLock {
      cachedMetadata[file] = value
    }
  }

  
}
