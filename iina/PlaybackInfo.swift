//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class MediaItem {
  enum LoadStatus {
    case notStarted       /// set before mpv is aware of it
    case started          /// set after mpv sends `fileStarted` notification
    case loaded           /// set after mpv sends `fileLoaded` notification
    case completelyLoaded /// everything loaded, including filters
    case ended
  }

  let url: URL
  let mpvMD5: String

  var playlistPos: Int
  var loadStatus: LoadStatus

  var thumbnails: SingleMediaThumbnailsLoader? = nil

  init(url: URL, playlistPos: Int = 0, loadStatus: LoadStatus = .notStarted) {
    self.url = url
    mpvMD5 = Utility.mpvWatchLaterMd5(url.path)
    self.playlistPos = playlistPos
    self.loadStatus = loadStatus
  }

  convenience init?(path: String, playlistPos: Int = 0, loadStatus: LoadStatus = .notStarted) {
    let url = path.contains("://") ?
    URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlAllowed) ?? path) :
    URL(fileURLWithPath: path)
    guard let url else { return nil }
    self.init(url: url, playlistPos: playlistPos, loadStatus: loadStatus)
  }
}

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

  var isIdle: Bool = true {
    didSet {
      PlayerCore.checkStatusForSleep()
    }
  }

  /// Is `true` only while restore from previous launch is still in progress; `false` otherwise.
  var isRestoring = false

  /// Contains info needed to restore the UI state from a previous launch. Should only be used if `isRestoring==true`
  var priorState: PlayerSaveState? = nil {
    didSet {
      Logger.log("Updated priorState to: \(priorState.debugDescription)")
    }
  }

  /// Opened or started file, but still waiting for `fileLoaded` event
  var justOpenedFile: Bool = true
  var timeLastFileOpenFinished: TimeInterval = 0
  var timeSinceLastFileOpenFinished: TimeInterval {
    Date().timeIntervalSince1970 - timeLastFileOpenFinished
  }

  var isFileLoaded: Bool = false

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

  var currentMedia: MediaItem? = nil

  var currentURL: URL? {
    return currentMedia?.url
  }

  var isNetworkResource: Bool {
    if let currentURL {
      return !currentURL.isFileURL
    }
    return false
  }
  var mpvMd5: String? {
    return currentMedia?.mpvMD5
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

  /// If displaying album art, will be `1` (square). Otherwise should match `videoGeo.videoAspectACR`, which should match the aspect of
  /// the currently displayed `videoView`.
  var videoAspect: CGFloat {
    if isShowingAlbumArt {
      return 1.0  // album art is always square
    }
    if let videoAspectACR = videoGeo.videoAspectACR {
      return videoAspectACR
    }
    // Ideally this should never happen
    // TODO: preload video information using ffmpeg before opening window
    log.warn("No videoAspect found in videoGeo! Falling back to default 16:9 aspect")
    return 16.0/9.0
  }

  /// If `true`, then `videoView` is used to display album art, or default album art, which is always square
  var isShowingAlbumArt: Bool = false

  /// Should be read/written on main thread only
  var videoGeo = VideoGeometry.nullGeometry {
    didSet {
      log.verbose("Updated videoGeo to: \(videoGeo)")
    }
  }

  var rawWidth: Int? {
    let width = videoGeo.rawWidth
    guard width > 0 else { return nil }
    return width
  }
  var rawHeight: Int? {
    let height = videoGeo.rawHeight
    guard height > 0 else { return nil }
    return height
  }

  // MARK: - Filters & Equalizers

  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilters: [MPVFilter?]?
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
  var aid: Int?
  var sid: Int?
  var vid: Int?
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

  // MARK: - Subtitles

  var subEncoding: String?

  var haveDownloadedSub: Bool = false

  /// Map: { video `path` for each `info` of `currentVideosInfo` -> `url` for each of `info.relatedSubs` }
  @Atomic var matchedSubs: [String: [URL]] = [:]

  func getMatchedSubs(_ file: String) -> [URL]? { $matchedSubs.withLock { $0[file] } }

  var currentSubsInfo: [FileInfo] = []
  var currentVideosInfo: [FileInfo] = []

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
        .compactMap { cachedVideoDurationAndProgress[playlist[$0].filename]?.duration }
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
