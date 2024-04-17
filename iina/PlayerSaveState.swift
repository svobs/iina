//
//  PlayerSaveState.swift
//  iina
//
//  Created by Matt Svoboda on 8/6/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

// Data structure for saving to prefs / restoring from prefs the UI state of a single player window
struct PlayerSaveState {
  enum PropName: String {
    case launchID = "launchID"

    case playlistPaths = "playlistPaths"

    case playlistVideos = "playlistVideos"
    case playlistSubtitles = "playlistSubs"
    case matchedSubtitles = "matchedSubs"

    case intendedViewportSize = "intendedViewportSize"
    case layoutSpec = "layoutSpec"
    case windowedModeGeo = "windowedModeGeo"
    case musicModeGeo = "musicModeGeo"
    case screens = "screens"
    case miscWindowBools = "miscWindowBools"
    case overrideAutoMusicMode = "overrideAutoMusicMode"
    case isOnTop = "onTop"
    case windowScale = "windowScale"  /// `MPVProperty.windowScale`

    case url = "url"
    case playPosition = "playPosition"/// `MPVOption.PlaybackControl.start`
    case playDuration = "playDuration"/// `MPVProperty.duration`
    case paused = "paused"            /// `MPVOption.PlaybackControl.pause`

    case vid = "vid"                  /// `MPVOption.TrackSelection.vid`
    case aid = "aid"                  /// `MPVOption.TrackSelection.aid`
    case sid = "sid"                  /// `MPVOption.TrackSelection.sid`
    case s2id = "sid2"                /// `MPVOption.Subtitles.secondarySid`

    case hwdec = "hwdec"              /// `MPVOption.Video.hwdec`
    case deinterlace = "deinterlace"  /// `MPVOption.Video.deinterlace`
    case hdrEnabled = "hdrEnabled"    /// IINA setting

    case brightness = "brightness"    /// `MPVOption.Equalizer.brightness`
    case contrast = "contrast"        /// `MPVOption.Equalizer.contrast`
    case saturation = "saturation"    /// `MPVOption.Equalizer.saturation`
    case gamma = "gamma"              /// `MPVOption.Equalizer.gamma`
    case hue = "hue"                  /// `MPVOption.Equalizer.hue`

    case videoFilters = "vf"          /// `MPVProperty.vf`
    case audioFilters = "af"          /// `MPVProperty.af`
    case videoFiltersDisabled = "vfDisabled"/// IINA-only

    case playSpeed = "playSpeed"      /// `MPVOption.PlaybackControl.speed`
    case volume = "volume"            /// `MPVOption.Audio.volume`
    case isMuted = "muted"            /// `MPVOption.Audio.mute`
    case maxVolume = "maxVolume"      /// `MPVOption.Audio.volumeMax`
    case audioDelay = "audioDelay"    /// `MPVOption.Audio.audioDelay`
    case subDelay = "subDelay"        /// `MPVOption.Subtitles.subDelay`
    case abLoopA = "abLoopA"          /// `MPVOption.PlaybackControl.abLoopA`
    case abLoopB = "abLoopB"          /// `MPVOption.PlaybackControl.abLoopB`

    case videoRawWidth = "vidRawW"    /// `MPVProperty.width`
    case videoRawHeight = "vidRawH"   /// `MPVProperty.height`
    case videoAspectLabel = "aspect"  /// Converted into `MPVOption.Video.videoAspectOverride`
    case cropLabel = "cropLabel"      /// Converted into `MPVOption.Video.videoAspectOverride`
    case videoRotation = "videoRotate"/// `MPVOption.Video.videoRotate`
    case totalRotation = "totalRotation"/// `MPVProperty.videoParamsRotate`

    case isSubVisible = "subVisible"  /// `MPVOption.Subtitles.subVisibility`
    case isSub2Visible = "sub2Visible"/// `MPVOption.Subtitles.secondarySubVisibility`
    case subScale = "subScale"        /// `MPVOption.Subtitles.subScale`
    case subPos = "subPos"            /// `MPVOption.Subtitles.subPos`
    case loopPlaylist = "loopPlaylist"/// `MPVOption.PlaybackControl.loopPlaylist`
    case loopFile = "loopFile"        /// `MPVOption.PlaybackControl.loopFile`
  }

  static fileprivate let specPrefStringVersion = "1"
  static fileprivate let windowGeometryPrefStringVersion = "1"
  static fileprivate let musicModeGeoPrefStringVersion = "1"
  static fileprivate let playlistVideosCSVVersion = "1"
  static fileprivate let specErrPre = "Failed to parse LayoutSpec from string:"
  static fileprivate let geoErrPre = "Failed to parse WindowGeometry from string:"

  let properties: [String: Any]

  /// Cached values parsed from `properties`

  /// Describes the current layout configuration of the player window.
  /// See `setInitialWindowLayout()` in `PlayerWindowLayout.swift`.
  let layoutSpec: PlayerWindowController.LayoutSpec?
  /// If in fullscreen, this is actually the `priorWindowedGeometry`
  let windowedModeGeo: PWGeometry?
  let musicModeGeo: MusicModeGeometry?
  let screens: [ScreenMeta]

  init(_ props: [String: Any]) {
    self.properties = props

    let layoutSpecCSV = PlayerSaveState.string(for: .layoutSpec, properties)
    self.layoutSpec = PlayerWindowController.LayoutSpec.fromCSV(layoutSpecCSV)
    let windowdModeCSV = PlayerSaveState.string(for: .windowedModeGeo, properties)
    self.windowedModeGeo = PWGeometry.fromCSV(windowdModeCSV)
    let musicModeCSV = PlayerSaveState.string(for: .musicModeGeo, properties)
    self.musicModeGeo = MusicModeGeometry.fromCSV(musicModeCSV)
    self.screens = (props[PropName.screens.rawValue] as? [String] ?? []).compactMap({ScreenMeta.from($0)})
  }

  // MARK: - Save State / Serialize to prefs strings

  /// Generates a Dictionary of properties for storage into a Preference entry
  static private func generatePropDict(from player: PlayerCore) -> [String: Any] {
    var props: [String: Any] = [:]
    let info = player.info
    /// Must *not* access `window`: this is not the main thread
    let wc = player.windowController!
    let layout = wc.currentLayout

    props[PropName.launchID.rawValue] = AppDelegate.launchID

    // - Window Layout & Geometry

    /// `layoutSpec`
    props[PropName.layoutSpec.rawValue] = layout.spec.toCSV()

    /// `windowedModeGeo`
    let windowedModeGeo = wc.windowedModeGeo
    props[PropName.windowedModeGeo.rawValue] = windowedModeGeo.toCSV()

    /// `musicModeGeo`
    props[PropName.musicModeGeo.rawValue] = wc.musicModeGeo.toCSV()

    let screenMetaCSVList: [String] = wc.cachedScreens.values.map{$0.toCSV()}
    props[PropName.screens.rawValue] = screenMetaCSVList

    if let size = info.intendedViewportSize {
      let sizeString = [size.width.stringMaxFrac2, size.height.stringMaxFrac2].joined(separator: ",")
      props[PropName.intendedViewportSize.rawValue] = sizeString
    }

    if player.windowController.isOnTop {
      props[PropName.isOnTop.rawValue] = true.yn
    }

    // - Video geometry

    props[PropName.videoRawWidth.rawValue] = String(info.videoGeo.rawWidth)
    props[PropName.videoRawHeight.rawValue] = String(info.videoGeo.rawHeight)
    props[PropName.videoAspectLabel.rawValue] = info.videoGeo.selectedAspectLabel
    props[PropName.cropLabel.rawValue] = info.videoGeo.selectedCropLabel
    props[PropName.totalRotation.rawValue] = String(info.videoGeo.totalRotation)
    props[PropName.videoRotation.rawValue] = String(info.videoGeo.userRotation)
    props[PropName.windowScale.rawValue] = info.videoGeo.scale.stringMaxFrac6

    // - Misc window state

    if Preference.bool(for: .autoSwitchToMusicMode) {
      var overrideAutoMusicMode = player.overrideAutoMusicMode
      let audioStatus = player.info.currentMediaAudioStatus
      if (audioStatus == .notAudio && player.isInMiniPlayer) || (audioStatus == .isAudio && !player.isInMiniPlayer) {
        /// Need to set this so that when restoring, the player won't immediately overcorrect and auto-switch music mode.
        /// This can happen because the `iinaFileLoaded` event will be fired by mpv very soon after restore is done, which is where it switches.
        overrideAutoMusicMode = true
      }
      props[PropName.overrideAutoMusicMode.rawValue] = overrideAutoMusicMode.yn
    }

    props[PropName.miscWindowBools.rawValue] = [
      wc.isWindowMiniturized.yn,
      wc.isWindowHidden.yn,
      (wc.pipStatus == .inPIP).yn,
      wc.isWindowMiniaturizedDueToPip.yn,
      wc.isPausedPriorToInteractiveMode.yn
    ].joined(separator: ",")

    // - Playback State

    if let urlString = info.currentURL?.absoluteString ?? nil {
      props[PropName.url.rawValue] = urlString
    }

    let playlist = info.playlist
    let playlistPaths: [String] = playlist.compactMap{ $0.filename }
    if !playlistPaths.isEmpty {
      props[PropName.playlistPaths.rawValue] = playlistPaths
    }

    if let videoPosition = info.videoPosition?.second {
      props[PropName.playPosition.rawValue] = videoPosition.stringMaxFrac6
    }
    if let videoDuration = info.videoDuration?.second {
      props[PropName.playDuration.rawValue] = videoDuration.stringMaxFrac6
    }
    props[PropName.paused.rawValue] = info.isPaused.yn

    // - Video, Audio, Subtitles Settings

    props[PropName.playlistVideos.rawValue] = Array(info.currentVideosInfo.map({
      // Need to store the group prefix length (if any) to allow collapsing it in the playlist. Not easy to recompute
      "\(playlistVideosCSVVersion),\($0.prefix.count),\($0.url.absoluteString)"
    })).joined(separator: " ")
    props[PropName.playlistSubtitles.rawValue] = Array(info.currentSubsInfo.map({$0.url.absoluteString}))
    let matchedSubsArray = info.matchedSubs.map({key, value in (key, Array(value.map({$0.absoluteString})))})
    let matchedSubs: [String: [String]] = Dictionary(uniqueKeysWithValues: matchedSubsArray)
    props[PropName.matchedSubtitles.rawValue] = matchedSubs

    props[PropName.deinterlace.rawValue] = info.deinterlace.yn
    props[PropName.hwdec.rawValue] = info.hwdec
    props[PropName.hdrEnabled.rawValue] = info.hdrEnabled.yn

    if let intVal = info.vid {
      props[PropName.vid.rawValue] = String(intVal)
    }
    if let intVal = info.aid {
      props[PropName.aid.rawValue] = String(intVal)
    }
    if let intVal = info.sid {
      props[PropName.sid.rawValue] = String(intVal)
    }
    if let intVal = info.secondSid {
      props[PropName.s2id.rawValue] = String(intVal)
    }
    props[PropName.brightness.rawValue] = String(info.brightness)
    props[PropName.contrast.rawValue] = String(info.contrast)
    props[PropName.saturation.rawValue] = String(info.saturation)
    props[PropName.gamma.rawValue] = String(info.gamma)
    props[PropName.hue.rawValue] = String(info.hue)

    props[PropName.playSpeed.rawValue] = info.playSpeed.stringMaxFrac6
    props[PropName.volume.rawValue] = info.volume.stringMaxFrac6
    props[PropName.isMuted.rawValue] = info.isMuted.yn
    props[PropName.audioDelay.rawValue] = info.audioDelay.stringMaxFrac6
    props[PropName.subDelay.rawValue] = info.subDelay.stringMaxFrac6

    props[PropName.subScale.rawValue] = player.mpv.getDouble(MPVOption.Subtitles.subScale).stringMaxFrac2
    props[PropName.subPos.rawValue] = String(player.mpv.getInt(MPVOption.Subtitles.subPos))

    props[PropName.isSubVisible.rawValue] = info.isSubVisible.yn
    props[PropName.isSub2Visible.rawValue] = info.isSecondSubVisible.yn

    let abLoopA: Double = player.abLoopA
    if abLoopA != 0 {
      props[PropName.abLoopA.rawValue] = abLoopA.stringMaxFrac6
    }
    let abLoopB: Double = player.abLoopB
    if abLoopB != 0 {
      props[PropName.abLoopB.rawValue] = abLoopB.stringMaxFrac6
    }

    let maxVolume = player.mpv.getInt(MPVOption.Audio.volumeMax)
    if maxVolume != 100 {
      props[PropName.maxVolume.rawValue] = String(maxVolume)
    }

    props[PropName.videoFilters.rawValue] = player.mpv.getString(MPVProperty.vf)
    props[PropName.audioFilters.rawValue] = player.mpv.getString(MPVProperty.af)

    props[PropName.videoFiltersDisabled.rawValue] = player.info.videoFiltersDisabled.values.map({$0.stringFormat}).joined(separator: ",")

    props[PropName.loopPlaylist.rawValue] = player.mpv.getString(MPVOption.PlaybackControl.loopPlaylist)
    props[PropName.loopFile.rawValue] = player.mpv.getString(MPVOption.PlaybackControl.loopFile)
    return props
  }

  static func save(_ player: PlayerCore) {
    guard Preference.UIState.isSaveEnabled else { return }

    var ticket: Int = 0
    player.$saveTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    /// Runs asyncronously in background queue to avoid blocking UI.
    /// Cuts down on duplicate work via delay and ticket check.
    PlayerCore.backgroundQueue.asyncAfter(deadline: DispatchTime.now() + AppData.playerStateSaveDelay) {
      guard ticket == player.saveTicketCounter else {
        return
      }

      guard player.windowController.loaded else {
        if player.log.isTraceEnabled {
          player.log.trace("Skipping player state save: player window is not loaded")
        }
        return
      }
      guard !player.info.isRestoring else {
        if player.log.isTraceEnabled {
          player.log.trace("Skipping player state save: still restoring previous state")
        }
        return
      }
      guard !player.isShuttingDown else {
        player.log.warn("Skipping player state save: player is shutting down")
        return
      }
      guard !player.windowController.isClosing else {
        // mpv core is often still active even after closing, and will send events which
        // can trigger save. Need to make sure we check for this so that we don't un-delete state
        player.log.trace("Skipping player state save: window.isClosing is true")
        return
      }

      let properties = generatePropDict(from: player)
      if player.log.isTraceEnabled {
        player.log.trace("Saving player state (tkt \(ticket)): \(properties)")
      }
      Preference.UIState.savePlayerState(forPlayerID: player.label, properties: properties)
    }
  }

  static func saveSynchronously(_ player: PlayerCore) {
    let properties = generatePropDict(from: player)
    if player.log.isTraceEnabled {
      player.log.trace("Saving player state: \(properties)")
    }
    Preference.UIState.savePlayerState(forPlayerID: player.label, properties: properties)
  }

  // MARK: - Restore State / Deserialize from prefs

  func string(for name: PropName) -> String? {
    return PlayerSaveState.string(for: name, properties)
  }

  /// Relies on `Bool` being serialized to `String` with value `Y` or `N`
  func bool(for name: PropName) -> Bool? {
    return PlayerSaveState.bool(for: name, properties)
  }

  func int(for name: PropName) -> Int? {
    return PlayerSaveState.int(for: name, properties)
  }

  /// Relies on `Double` being serialized to `String`
  func double(for name: PropName) -> Double? {
    return PlayerSaveState.double(for: name, properties)
  }

  /// Expects to parse CSV `String` with two tokens
  func nsSize(for name: PropName) -> NSSize? {
    if let csv = string(for: name) {
      let tokens = csv.split(separator: ",")
      if tokens.count == 2, let width = Double(tokens[0]), let height = Double(tokens[1]) {
        return NSSize(width: width, height: height)
      }
      Logger.log("Failed to parse property as NSSize: \(name.rawValue.quoted)")
    }
    return nil
  }

  static private func string(for name: PropName, _ properties: [String: Any]) -> String? {
    return properties[name.rawValue] as? String
  }

  static private func bool(for name: PropName, _ properties: [String: Any]) -> Bool? {
    return Bool.yn(string(for: name, properties))
  }

  static private func int(for name: PropName, _ properties: [String: Any]) -> Int? {
    if let intString = string(for: name, properties) {
      return Int(intString)
    }
    return nil
  }

  /// Relies on `Double` being serialized to `String`
  static private func double(for name: PropName, _ properties: [String: Any]) -> Double? {
    if let doubleString = string(for: name, properties) {
      return Double(doubleString)
    }
    return nil
  }

  // Utility function for parsing complex object from CSV
  static fileprivate func parseCSV<T>(_ csvString: String?, expectedTokenCount: Int, expectedVersion: String,
                                      errPreamble: String, 
                                      _ parseFunc: (String, inout IndexingIterator<[String]>) throws -> T?) rethrows -> T? {
    guard let csv = csvString else { return nil }
    Logger.log("Parsing CSV: \(csv.quoted)", level: .verbose)
    let tokens = csv.split(separator: ",").map{String($0)}
    guard tokens.count == expectedTokenCount else {
      Logger.log("\(errPreamble) wrong token count (expected \(expectedTokenCount) but found \(tokens.count))", level: .error)
      return nil
    }
    var iter = tokens.makeIterator()

    let version = iter.next()
    guard version == expectedVersion else {
      Logger.log("\(errPreamble) bad version (expected \(expectedVersion.quoted) but found \(version?.quoted ?? "nil"))", level: .error)
      return nil
    }

    return try parseFunc(errPreamble, &iter)
  }

  static private func parsePlaylistVideos(from entryString: String) -> [FileInfo] {
    var videos: [FileInfo] = []

    // Each entry cannot contain spaces, so use that for the first delimiter:
    for csvString in entryString.split(separator: " ") {
      // Do not parse more than the first 2 tokens. The URL can contain commas
      let tokens = csvString.split(separator: ",", maxSplits: 2).map{String($0)}
      guard tokens.count == 3 else {
        Logger.log("Could not parse PlaylistVideoInfo: not enough tokens (expected 3 but found \(tokens.count))", level: .error)
        continue
      }
      guard tokens[0] == playlistVideosCSVVersion else {
        Logger.log("Could not parse PlaylistVideoInfo: wrong version (expected \(playlistVideosCSVVersion) but found \(tokens[0].quoted))", level: .error)
        continue
      }

      guard let prefixLength = Int(tokens[1]),
            let url = URL(string: tokens[2])
      else {
        Logger.log("Could not parse PlaylistVideoInfo url or prefixLength!", level: .error)
        continue
      }

      let fileInfo = FileInfo(url)
      if prefixLength > 0 {
        var string = url.deletingPathExtension().lastPathComponent
        let suffixRange = string.index(string.startIndex, offsetBy: prefixLength)..<string.endIndex
        string.removeSubrange(suffixRange)
        fileInfo.prefix = string
      }
      videos.append(fileInfo)
    }
    return videos
  }

  /// Restore player state from prior launch
  func restoreTo(_ player: PlayerCore) {
    let log = player.log

    guard let urlString = string(for: .url), let url = URL(string: urlString) else {
      log.error("Could not restore player window: no value for property \(PlayerSaveState.PropName.url.rawValue.quoted)")
      return
    }

    if Logger.isEnabled(.verbose) {
      let urlPath: String
      if #available(macOS 13.0, *) {
        urlPath = url.path(percentEncoded: false)
      } else {
        urlPath = url.path
      }

      let filteredProps = properties.filter({
        switch $0.key {
        case PropName.url.rawValue,
          // these are too long and contain PII
          PropName.playlistPaths.rawValue,
          PropName.playlistVideos.rawValue,
          PropName.playlistSubtitles.rawValue,
          PropName.matchedSubtitles.rawValue:
          return false
        default:
          return true
        }
      })

      // log properties but not playlist paths (not very useful, takes up space, is private info)
      log.verbose("Restoring player state from prior launch. URL: \(urlPath.pii.quoted) Properties: \(filteredProps)")
    }
    let info = player.info
    info.priorState = self
    info.isRestoring = true

    let windowController = player.windowController!

    log.verbose("Screens from prior launch: \(self.screens)")

    // TODO: map current geometry to prior screen. Deal with mismatch

    if let hdrEnabled = bool(for: .hdrEnabled) {
      info.hdrEnabled = hdrEnabled
    }

    // Set these here so that play position slider can be restored to prev position when the window is opened - not after
    if let videoPosition = double(for: .playPosition) {
      info.videoPosition = VideoTime(videoPosition)
    }
    if let videoDuration = double(for: .playDuration) {
      info.videoDuration = VideoTime(videoDuration)
    }
    if let paused = bool(for: .paused) {
      info.isPaused = paused
    }

    if let size = nsSize(for: .intendedViewportSize) {
      info.intendedViewportSize = size
    }

    if let videoURLListString = string(for: .playlistVideos) {
      let currentVideosInfo = PlayerSaveState.parsePlaylistVideos(from: videoURLListString)
      info.currentVideosInfo = currentVideosInfo
    }

    if let videoURLList = properties[PlayerSaveState.PropName.playlistSubtitles.rawValue] as? [String] {
      info.currentSubsInfo = videoURLList.compactMap({URL(string: $0)}).compactMap({FileInfo($0)})
    }

    if let matchedSubs = properties[PlayerSaveState.PropName.matchedSubtitles.rawValue] as? [String: [String]] {
      info.$matchedSubs.withLock {
        for (videoPath, subs) in matchedSubs {
          $0[videoPath] = subs.compactMap{urlString in URL(string: urlString)}
        }
      }
    }
    player.log.verbose("Restored info for \(info.currentVideosInfo.count) videos, \(info.currentSubsInfo.count) subs")

    if let videoFiltersDisabledCSV = string(for: .videoFiltersDisabled) {
      let filters = videoFiltersDisabledCSV.split(separator: ",").compactMap({MPVFilter(rawString: String($0))})
      for filter in filters {
        if let label = filter.label {
          info.videoFiltersDisabled[label] = filter
        } else {
          player.log.error("Could not restore disabled video filter: missing label (\(filter.stringFormat.quoted))")
        }
      }
    }

    /// Need to set these in `info` before `openURLs()` is called
    /// (or at least for `aid`, so that volume slider is correct at first draw)
    if let vid = int(for: .vid) {
      info.vid = vid
    }
    if let aid = int(for: .aid) {
      info.aid = aid
    }
    if let sid = int(for: .sid) {
      info.sid = sid
    }
    if let s2id = int(for: .s2id) {
      info.secondSid = s2id
    }

    // Prevent "seek" OSD from appearing unncessarily after loading finishes
    windowController.osdLastPlaybackPosition = info.videoPosition?.second
    windowController.osdLastPlaybackDuration = info.videoDuration?.second

    // totalRotation is needed to quickly calculate & restore video dimensions instead of waiting for mpv to provide it
    info.videoGeo = info.videoGeo.clone(rawWidth: int(for: .videoRawWidth),
                                        rawHeight: int(for: .videoRawHeight),
                                        selectedAspectLabel: string(for: .videoAspectLabel),
                                        totalRotation: int(for: .totalRotation),
                                        userRotation: int(for: .videoRotation),
                                        selectedCropLabel: string(for: .cropLabel))

    if let windowScale = double(for: .windowScale) {
      // Swift has a few rough edges still
      info.videoGeo = info.videoGeo.clone(scale: windowScale)
    }

    // Open the window!
    player.openURLs([url], shouldAutoLoad: false)

    let isOnTop = bool(for: .isOnTop) ?? false
    windowController.setWindowFloatingOnTop(isOnTop, updateOnTopStatus: true)

    if let stateString = string(for: .miscWindowBools) {
      let splitted: [String] = stateString.split(separator: ",").map{String($0)}
      if splitted.count >= 5,
         let isMiniaturized = Bool.yn(splitted[0]),
         let isHidden = Bool.yn(splitted[1]),
         let isInPip = Bool.yn(splitted[2]),
         let isWindowMiniaturizedDueToPip = Bool.yn(splitted[3]),
         let isPausedPriorToInteractiveMode = Bool.yn(splitted[4]) {

        // Process PIP options first, to make sure it's not miniturized due to PIP
        if isInPip {
          let pipOption: Preference.WindowBehaviorWhenPip
          if isHidden {  // currently this will only be true due to PIP
            pipOption = .hide
          } else if isWindowMiniaturizedDueToPip {
            pipOption = .minimize
          } else {
            pipOption = .doNothing
          }
          // Run in queue to avert race condition with window load
          windowController.animationPipeline.submitZeroDuration({
            windowController.enterPIP(usePipBehavior: pipOption)
          })
        } else if isMiniaturized {
          // Not in PIP, but miniturized
          // Run in queue to avert race condition with window load
          windowController.animationPipeline.submitZeroDuration({
            windowController.window?.miniaturize(nil)
          })
        }
        if isPausedPriorToInteractiveMode {
          windowController.isPausedPriorToInteractiveMode = isPausedPriorToInteractiveMode
        }
      } else {
        log.error("Failed to restore property \(PlayerSaveState.PropName.miscWindowBools.rawValue.quoted): could not parse \(stateString.quoted)")
      }
    }

    if let overrideAutoMusicMode = bool(for: .overrideAutoMusicMode) {
      player.overrideAutoMusicMode = overrideAutoMusicMode
    }

    // mpv properties

    /// Must wait until after mpv init, so that the lifetime of these options is limited to the current file.
    /// Otherwise the mpv core will keep the options for the lifetime of the player, which is often undesirable (for example,
    /// `MPVOption.PlaybackControl.start` will skip any files in the playlist which have durations shorter than its start time).
    let mpv: MPVController = player.mpv

    mpv.queue.async { [self] in
      if let videoPosition = string(for: .playPosition) {
        log.verbose("Restoring playback position: \(videoPosition)")
        mpv.setString(MPVOption.PlaybackControl.start, videoPosition)
      }

      // Better to always pause when starting, because there may be a slight delay before it can be enforced later
      mpv.setFlag(MPVOption.PlaybackControl.pause, true)

      /// already read these into `info` up above. Now set in mpv
      if let vid = info.vid {
        mpv.setInt(MPVOption.TrackSelection.vid, vid)
      }
      if let aid = info.aid {
        mpv.setInt(MPVOption.TrackSelection.aid, aid)
      }
      /// Don't set sub tracks until `fileStarted`, after external subtitles are loaded.

      if let hwdec = string(for: .hwdec) {
        mpv.setString(MPVOption.Video.hwdec, hwdec)
      }

      if let deinterlace = bool(for: .deinterlace) {
        mpv.setFlag(MPVOption.Video.deinterlace, deinterlace)
      }

      if let userRotation = int(for: .videoRotation) {
        mpv.setInt(MPVOption.Video.videoRotate, userRotation)
      }

      if let windowScale = double(for: .windowScale) {
        mpv.setDouble(MPVProperty.windowScale, windowScale)
      }

      if let videoAspectLabel = string(for: .videoAspectLabel) {
        // Update videoGeo above first so that UI doesn't alert the user
        if info.videoGeo.aspectRatioOverride != nil {
          let mpvValue = videoAspectLabel == AppData.defaultAspectIdentifier ? "no" : videoAspectLabel
          mpv.setString(MPVOption.Video.videoAspectOverride, mpvValue)
        }
      }

      if let selectedCropLabel = string(for: .cropLabel) {
        // Update videoGeo above first so that UI doesn't alert the user
        player.setCrop(fromLabel: selectedCropLabel)
      }

      if let brightness = int(for: .brightness) {
        mpv.setInt(MPVOption.Equalizer.brightness, brightness)
      }
      if let contrast = int(for: .contrast) {
        mpv.setInt(MPVOption.Equalizer.contrast, contrast)
      }
      if let saturation = int(for: .saturation) {
        mpv.setInt(MPVOption.Equalizer.saturation, saturation)
      }
      if let gamma = int(for: .gamma) {
        mpv.setInt(MPVOption.Equalizer.gamma, gamma)
      }
      if let hue = int(for: .hue) {
        mpv.setInt(MPVOption.Equalizer.hue, hue)
      }

      if let playSpeed = double(for: .playSpeed) {
        mpv.setDouble(MPVOption.PlaybackControl.speed, playSpeed)
      }
      if let volume = double(for: .volume) {
        info.volume = volume
        mpv.setDouble(MPVOption.Audio.volume, volume)
      }
      if let isMuted = bool(for: .isMuted) {
        info.isMuted = isMuted
        mpv.setFlag(MPVOption.Audio.mute, isMuted)
      }
      if let maxVolume = int(for: .maxVolume) {
        mpv.setInt(MPVOption.Audio.volumeMax, maxVolume)
      }
      if let audioDelay = double(for: .audioDelay) {
        mpv.setDouble(MPVOption.Audio.audioDelay, audioDelay)
      }
      if let subDelay = double(for: .subDelay) {
        mpv.setDouble(MPVOption.Subtitles.subDelay, subDelay)
      }
      if let isSubVisible = bool(for: .isSubVisible) {
        mpv.setFlag(MPVOption.Subtitles.subVisibility, isSubVisible)
      }
      if let isSub2Visible = bool(for: .isSub2Visible) {
        mpv.setFlag(MPVOption.Subtitles.secondarySubVisibility, isSub2Visible)
      }
      if let subScale = double(for: .subScale) {
        mpv.setDouble(MPVOption.Subtitles.subScale, subScale)
      }
      if let subPos = int(for: .subPos) {
        mpv.setInt(MPVOption.Subtitles.subPos, subPos)
      }
      if let loopPlaylist = string(for: .loopPlaylist) {
        mpv.setString(MPVOption.PlaybackControl.loopPlaylist, loopPlaylist)
      }
      if let loopFile = string(for: .loopFile) {
        mpv.setString(MPVOption.PlaybackControl.loopFile, loopFile)
      }
      if let abLoopA = double(for: .abLoopA) {
        if let abLoopB = double(for: .abLoopB) {
          mpv.setDouble(MPVOption.PlaybackControl.abLoopB, abLoopB)
        }
        mpv.setDouble(MPVOption.PlaybackControl.abLoopA, abLoopA)
      }

      if let audioFilters = string(for: .audioFilters) {
        mpv.setString(MPVProperty.af, audioFilters)
      }
      if let videoFilters = string(for: .videoFilters) {
        mpv.setString(MPVProperty.vf, videoFilters)
      }
    }
  }
}  /// end `struct PlayerSaveState`

struct ScreenMeta {
  static private let expectedCSVTokenCount = 14
  static private let csvVersion = String(1)

  let displayID: UInt32
  let name: String
  let frame: NSRect
  /// NOTE: `visibleFrame` is highly volatile and will change when Dock or title bar is shown/hidden
  let visibleFrame: NSRect
  let nativeResolution: CGSize
  let cameraHousingHeight: CGFloat

  func toCSV() -> String {
    return [ScreenMeta.csvVersion, String(displayID), name,
            frame.origin.x.stringMaxFrac2, frame.origin.y.stringMaxFrac2, frame.size.width.stringMaxFrac2, frame.size.height.stringMaxFrac2,
            visibleFrame.origin.x.stringMaxFrac2, visibleFrame.origin.y.stringMaxFrac2, visibleFrame.size.width.stringMaxFrac2, visibleFrame.size.height.stringMaxFrac2,
            nativeResolution.width.stringMaxFrac2, nativeResolution.height.stringMaxFrac2,
            cameraHousingHeight.stringMaxFrac2
    ].joined(separator: ",")
  }

  static func from(_ screen: NSScreen) -> ScreenMeta {
    let name: String
    if #available(macOS 10.15, *) {
      // Can't store comma in CSV. Just convert to semicolon
      name = screen.localizedName.replacingOccurrences(of: ",", with: ";")
    } else {
      name = ""
    }
    return ScreenMeta(displayID: screen.displayId, name: name, frame: screen.frame, visibleFrame: screen.visibleFrame,
                      nativeResolution: screen.nativeResolution ?? CGSizeZero, cameraHousingHeight: screen.cameraHousingHeight ?? 0)
  }

  static func from(_ csv: String) -> ScreenMeta? {
    let tokens = csv.split(separator: ",").map{String($0)}
    guard tokens.count == expectedCSVTokenCount else {
      Logger.log("While parsing ScreenMeta from CSV: wrong token count (expected \(expectedCSVTokenCount) but found \(tokens.count))", level: .error)
      return nil
    }
    var iter = tokens.makeIterator()

    let version = iter.next()
    guard version == csvVersion else {
      Logger.log("While parsing ScreenMeta from CSV: bad version (expected \(csvVersion.quoted) but found \(version?.quoted ?? "nil"))", level: .error)
      return nil
    }

      guard let displayID = UInt32(iter.next()!),
            let name = iter.next(),
            let frameX = Double(iter.next()!),
            let frameY = Double(iter.next()!),
            let frameW = Double(iter.next()!),
            let frameH = Double(iter.next()!),
            let visibleFrameX = Double(iter.next()!),
            let visibleFrameY = Double(iter.next()!),
            let visibleFrameW = Double(iter.next()!),
            let visibleFrameH = Double(iter.next()!),
            let nativeResW = Double(iter.next()!),
            let nativeResH = Double(iter.next()!),
            let cameraHousingHeight = Double(iter.next()!) else {
        Logger.log("While parsing ScreenMeta from CSV: could not parse one or more tokens", level: .error)
        return nil
      }

    let frame = NSRect(x: frameX, y: frameY, width: frameW, height: frameH)
    let visibleFrame = NSRect(x: visibleFrameX, y: visibleFrameY, width: visibleFrameW, height: visibleFrameH)
    let nativeResolution = NSSize(width: nativeResW, height: nativeResH)
    return ScreenMeta(displayID: displayID, name: name, frame: frame, visibleFrame: visibleFrame, nativeResolution: nativeResolution, cameraHousingHeight: cameraHousingHeight)
  }
}

extension MusicModeGeometry {

  /// String -> `MusicModeGeometry`
  /// Note to maintainers: if compiler is complaining with the message "nil is not compatible with closure result type MusicModeGeometry",
  /// check the arguments to the `MusicModeGeometry` constructor. For some reason the error lands in the wrong place.
  static func fromCSV(_ csv: String?) -> MusicModeGeometry? {
    guard !(csv?.isEmpty ?? true) else {
      Logger.log("CSV is empty; returning nil for MusicModeGeometry", level: .debug)
      return nil
    }
    return PlayerSaveState.parseCSV(csv, expectedTokenCount: 10,
                                    expectedVersion: PlayerSaveState.windowGeometryPrefStringVersion,
                                    errPreamble: PlayerSaveState.geoErrPre, { errPreamble, iter in

      guard let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let _ = Double(iter.next()!),  /// was `playlistHeight` (defunct as of 1.1)
            let isVideoVisible = Bool.yn(iter.next()!),
            let isPlaylistVisible = Bool.yn(iter.next()!),
            let videoAspect = Double(iter.next()!),
            let screenID = iter.next()
      else {
        Logger.log("\(errPreamble) could not parse one or more tokens", level: .error)
        return nil
      }

      let windowFrame = CGRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      return MusicModeGeometry(windowFrame: windowFrame,
                               screenID: screenID,
                               videoAspect: videoAspect,
                               isVideoVisible: isVideoVisible, isPlaylistVisible: isPlaylistVisible)
    })
  }

  /// `MusicModeGeometry` -> String
  func toCSV() -> String {
    return [PlayerSaveState.musicModeGeoPrefStringVersion,
            self.windowFrame.origin.x.stringMaxFrac2,
            self.windowFrame.origin.y.stringMaxFrac2,
            self.windowFrame.width.stringMaxFrac2,
            self.windowFrame.height.stringMaxFrac2,
            self.playlistHeight.stringMaxFrac2,
            self.isVideoVisible.yn,
            self.isPlaylistVisible.yn,
            self.videoAspect.aspectNormalDecimalString,
            self.screenID
    ].joined(separator: ",")
  }
}

extension PWGeometry {

  /// `PWGeometry` -> String
  func toCSV() -> String {
    return [PlayerSaveState.windowGeometryPrefStringVersion,
            self.topMarginHeight.stringMaxFrac2,
            self.outsideTopBarHeight.stringMaxFrac2,
            self.outsideTrailingBarWidth.stringMaxFrac2,
            self.outsideBottomBarHeight.stringMaxFrac2,
            self.outsideLeadingBarWidth.stringMaxFrac2,
            self.insideTopBarHeight.stringMaxFrac2,
            self.insideTrailingBarWidth.stringMaxFrac2,
            self.insideBottomBarHeight.stringMaxFrac2,
            self.insideLeadingBarWidth.stringMaxFrac2,
            self.viewportMargins.top.stringMaxFrac2,
            self.viewportMargins.trailing.stringMaxFrac2,
            self.viewportMargins.bottom.stringMaxFrac2,
            self.viewportMargins.leading.stringMaxFrac2,
            self.videoAspect.aspectNormalDecimalString,
            self.windowFrame.origin.x.stringMaxFrac2,
            self.windowFrame.origin.y.stringMaxFrac2,
            self.windowFrame.width.stringMaxFrac2,
            self.windowFrame.height.stringMaxFrac2,
            String(self.fitOption.rawValue),
            self.screenID,
            String(self.mode.rawValue)
    ].joined(separator: ",")
  }

  /// String -> `PWGeometry`
  static func fromCSV(_ csv: String?) -> PWGeometry? {
    guard !(csv?.isEmpty ?? true) else {
      Logger.log("CSV is empty; returning nil for geometry", level: .debug)
      return nil
    }
    return PlayerSaveState.parseCSV(csv, expectedTokenCount: 22,
                                    expectedVersion: PlayerSaveState.windowGeometryPrefStringVersion,
                                    errPreamble: PlayerSaveState.geoErrPre, { errPreamble, iter in

      guard let topMarginHeight = Double(iter.next()!),
            let outsideTopBarHeight = Double(iter.next()!),
            let outsideTrailingBarWidth = Double(iter.next()!),
            let outsideBottomBarHeight = Double(iter.next()!),
            let outsideLeadingBarWidth = Double(iter.next()!),
            let insideTopBarHeight = Double(iter.next()!),
            let insideTrailingBarWidth = Double(iter.next()!),
            let insideBottomBarHeight = Double(iter.next()!),
            let insideLeadingBarWidth = Double(iter.next()!),
            let viewportMarginTop = Double(iter.next()!),
            let viewportMarginTrailing = Double(iter.next()!),
            let viewportMarginBottom = Double(iter.next()!),
            let viewportMarginLeading = Double(iter.next()!),
            let videoAspect = Double(iter.next()!),
            let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let fitOptionRawValue = Int(iter.next()!),
            let screenID = iter.next(),
            let modeRawValue = Int(iter.next()!)
      else {
        Logger.log("\(errPreamble) could not parse one or more tokens", level: .error)
        return nil
      }

      guard let mode = PlayerWindowMode(rawValue: modeRawValue) else {
        Logger.log("\(errPreamble) unrecognized PlayerWindowMode: \(modeRawValue)", level: .error)
        return nil
      }
      guard let fitOption = ScreenFitOption(rawValue: fitOptionRawValue) else {
        Logger.log("\(errPreamble) unrecognized ScreenFitOption: \(fitOptionRawValue)", level: .error)
        return nil
      }
      let windowFrame = CGRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      let viewportMargins = MarginQuad(top: viewportMarginTop, trailing: viewportMarginTrailing,
                                    bottom: viewportMarginBottom, leading: viewportMarginLeading)
      return PWGeometry(windowFrame: windowFrame, screenID: screenID, fitOption: fitOption, mode: mode, topMarginHeight: topMarginHeight,
                             outsideTopBarHeight: outsideTopBarHeight, outsideTrailingBarWidth: outsideTrailingBarWidth,
                             outsideBottomBarHeight: outsideBottomBarHeight, outsideLeadingBarWidth: outsideLeadingBarWidth,
                             insideTopBarHeight: insideTopBarHeight, insideTrailingBarWidth: insideTrailingBarWidth,
                             insideBottomBarHeight: insideBottomBarHeight, insideLeadingBarWidth: insideLeadingBarWidth,
                             viewportMargins: viewportMargins,
                             videoAspect: videoAspect)
    })
  }

}

extension PlayerWindowController.LayoutSpec {
  /// `LayoutSpec` -> String
  func toCSV() -> String {
    let leadingSidebarTab: String = self.leadingSidebar.visibleTab?.name ?? "nil"
    let trailingSidebarTab: String = self.trailingSidebar.visibleTab?.name ?? "nil"
    return [PlayerSaveState.specPrefStringVersion,
            leadingSidebarTab,
            trailingSidebarTab,
            String(self.mode.rawValue),
            self.isLegacyStyle.yn,
            String(self.topBarPlacement.rawValue),
            String(self.trailingSidebarPlacement.rawValue),
            String(self.bottomBarPlacement.rawValue),
            String(self.leadingSidebarPlacement.rawValue),
            self.enableOSC.yn,
            String(self.oscPosition.rawValue),
            String(self.interactiveMode?.rawValue ?? 0)
    ].joined(separator: ",")
  }

  /// String -> `LayoutSpec`
  static func fromCSV(_ csv: String?) -> PlayerWindowController.LayoutSpec? {
    guard !(csv?.isEmpty ?? true) else {
      Logger.log("CSV is empty; returning nil for LayoutSpec", level: .debug)
      return nil
    }
    return PlayerSaveState.parseCSV(csv, expectedTokenCount: 12,
                                    expectedVersion: PlayerSaveState.specPrefStringVersion, errPreamble: PlayerSaveState.specErrPre, { errPreamble, iter in

      let leadingSidebarTab = PlayerWindowController.Sidebar.Tab(name: iter.next())
      let traillingSidebarTab = PlayerWindowController.Sidebar.Tab(name: iter.next())

      guard let modeInt = Int(iter.next()!), let mode = PlayerWindowMode(rawValue: modeInt),
            let isLegacyStyle = Bool.yn(iter.next()) else {
        Logger.log("\(errPreamble) could not parse mode or isLegacyStyle", level: .error)
        return nil
      }

      guard let topBarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let trailingSidebarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let bottomBarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let leadingSidebarPlacement = Preference.PanelPlacement(Int(iter.next()!)) else {
        Logger.log("\(errPreamble) could not parse bar placements", level: .error)
        return nil
      }

      guard let enableOSC = Bool.yn(iter.next()),
            let oscPositionInt = Int(iter.next()!),
            let oscPosition = Preference.OSCPosition(rawValue: oscPositionInt) else {
        Logger.log("\(errPreamble) could not parse enableOSC or oscPosition", level: .error)
        return nil
      }

      let interactModeInt = Int(iter.next()!)
      let interactiveMode = PlayerWindowController.InteractiveMode(rawValue: interactModeInt ?? 0) ?? nil  /// `0` === `nil` value

      var leadingTabGroups = PlayerWindowController.Sidebar.TabGroup.fromPrefs(for: .leadingSidebar)
      let leadVis: PlayerWindowController.Sidebar.Visibility = leadingSidebarTab == nil ? .hide : .show(tabToShow: leadingSidebarTab!)
      // If the tab groups prefs changed somehow since the last run, just add it for now so that the geometry can be restored.
      // Will correct this at the end of restore.
      if let visibleTab = leadVis.visibleTab, !leadingTabGroups.contains(visibleTab.group) {
        Logger.log("Restore state is invalid: leadingSidebar has visibleTab \(visibleTab.name) which is outside its configured tab groups", level: .error)
        leadingTabGroups.insert(visibleTab.group)
      }
      let leadingSidebar = PlayerWindowController.Sidebar(.leadingSidebar, tabGroups: leadingTabGroups, placement: leadingSidebarPlacement, visibility: leadVis)

      var trailingTabGroups = PlayerWindowController.Sidebar.TabGroup.fromPrefs(for: .trailingSidebar)
      let trailVis: PlayerWindowController.Sidebar.Visibility = traillingSidebarTab == nil ? .hide : .show(tabToShow: traillingSidebarTab!)
      // Account for invalid visible tab (see note above)
      if let visibleTab = trailVis.visibleTab, !trailingTabGroups.contains(visibleTab.group) {
        Logger.log("Restore state is invalid: trailingSidebar has visibleTab \(visibleTab.name) which is outside its configured tab groups", level: .error)
        trailingTabGroups.insert(visibleTab.group)
      }
      let trailingSidebar = PlayerWindowController.Sidebar(.trailingSidebar, tabGroups: trailingTabGroups, placement: trailingSidebarPlacement, visibility: trailVis)

      return PlayerWindowController.LayoutSpec(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar, mode: mode, isLegacyStyle: isLegacyStyle, topBarPlacement: topBarPlacement, bottomBarPlacement: bottomBarPlacement, enableOSC: enableOSC, oscPosition: oscPosition, interactiveMode: interactiveMode)
    })
  }

}
