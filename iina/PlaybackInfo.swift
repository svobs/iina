//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

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

  var priorStateBuildNumber: Int = Int(InfoDictionary.shared.version.1)!

  var isFileLoaded: Bool {
    return currentPlayback?.isFileLoaded ?? false
  }

  var isFileLoadedAndSized: Bool {
    return currentPlayback?.state.isAtLeast(.loadedAndSized) ?? false
  }

  var shouldAutoLoadFiles: Bool = false
  var isMatchingSubtitles = false

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

  var nowPlayingIndex: Int {
    return currentPlayback?.playlistPos ?? -1
  }

  var currentURL: URL? {
    return currentPlayback?.url
  }

  var isNetworkResource: Bool {
    return currentPlayback?.isNetworkResource ?? false
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
      if log.isTraceEnabled {
        if let newValue = intendedViewportSize {
          log.trace{"Updated intendedViewportSize to \(newValue)"}
        } else {
          log.trace("Updated intendedViewportSize to nil")
        }
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
  var sub2Delay: Double = 0
  var subScale: Double = 0
  var subPos: Double = 0
  var sub2Pos: Double = 0

  var abLoopStatus: LoopStatus = .cleared

  var playSpeed: Double = 1.0

  var shouldShowSpeedLabel: Bool {
    return !(isPaused || playSpeed == 1)
  }

  var playbackPositionSec: Double?
  var playbackDurationSec: Double?

  var playlist: [MPVPlaylistItem] = []
  var playlistPlayingPos: Int = -1  /// `MPVProperty.playlistPlayingPos`

  func constrainVideoPosition() {
    guard let playbackDurationSec, let playbackPositionSec else { return }
    if playbackPositionSec < 0.0 {
      self.playbackPositionSec = 0.0
    }
    if playbackPositionSec > playbackDurationSec { 
      self.playbackPositionSec = playbackDurationSec
    }
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

  var isSubVisible = true
  var isSecondSubVisible = true

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

  // -- PERSISTENT PROPERTIES END --

  enum CurrentMediaAudioStatus {
    case unknown
    case isAudioWithoutArt
    case isAudioWithArtHidden
    case isAudioWithArtShown
    case notAudio

    var isAudio: Bool {
      switch self {
      case .isAudioWithoutArt, .isAudioWithArtHidden, .isAudioWithArtShown:
        return true
      default:
        return false
      }
    }
  }

  var currentMediaAudioStatus: CurrentMediaAudioStatus {
    guard !isNetworkResource else { return .notAudio }
    let noVideoTrack = videoTracks.isEmpty
    let noAudioTrack = audioTracks.isEmpty
    if noVideoTrack && noAudioTrack {
      return .unknown
    }
    if noVideoTrack {
      return .isAudioWithoutArt
    }
    let allVideoTracksAreAlbumCover = !videoTracks.contains { !$0.isAlbumart }
    if allVideoTracksAreAlbumCover {
      if isVideoTrackSelected {
        return .isAudioWithArtShown
      } else {
        return .isAudioWithArtHidden
      }
    }
    return .notAudio
  }

  private let infoLock = Lock()

  var chapter = 0
  var chapters: [MPVChapter] = []

  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  var subTracks: [MPVTrack] = []

  var selectedSub: MPVTrack? {
    infoLock.withLock {
      let selected = infoLock.withLock { subTracks.filter { $0.id == sid } }
      if selected.count > 0 {
        return selected[0]
      }
      return nil
    }
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
    infoLock.withLock {
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
  /// mpv's `demuxer-cache-time`: Approximate timestamp of video buffered in the demuxer, in seconds
  var cacheTime: Double = 0
  var bufferingState: Int = 0

  func calculateTotalDuration() -> Double? {
    let playlist: [MPVPlaylistItem] = playlist
    let urls = playlist.map { $0.url }
    return MediaMetaCache.shared.calculateTotalDuration(urls)
  }

  func calculateTotalDuration(_ indexes: IndexSet) -> Double {
    let playlist: [MPVPlaylistItem] = playlist
    let urls = indexes.compactMap{ $0 < playlist.count ? playlist[$0].url : nil }
    return MediaMetaCache.shared.calculateTotalDuration(urls)
  }
  
}
