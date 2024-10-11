//
//  PlayerSaveState.swift
//  iina
//
//  Created by Matt Svoboda on 8/6/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

fileprivate let embeddedSeparator: Character = "|"

// Data structure for saving to prefs / restoring from prefs the UI state of a single player window
struct PlayerSaveState: CustomStringConvertible {
  enum PropName: String {
    case buildNumber = "buildNum"       // Added in v1.2
    case launchID = "launchID"

    case playlistPaths = "playlistPaths"

    case playlistVideos = "playlistVideos"
    case playlistSubtitles = "playlistSubs"
    case matchedSubtitles = "matchedSubs"

    case intendedViewportSize = "intendedViewportSize"
    case layoutSpec = "layoutSpec"
    case videoGeo = "videoGeo"  // Added in v1.2
    case windowedModeGeo = "windowedModeGeo"
    case musicModeGeo = "musicModeGeo"
    case screens = "screens"
    case miscWindowBools = "miscWindowBools"
    case overrideAutoMusicMode = "overrideAutoMusicMode"
    case isOnTop = "onTop"

    case url = "url"
    case playPosition = "playPosition"  /// `MPVOption.PlaybackControl.start`
    case playDuration = "playDuration"  /// `MPVProperty.duration`
    case paused = "paused"              /// `MPVOption.PlaybackControl.pause`

    case vid = "vid"                    /// `MPVOption.TrackSelection.vid`
    case aid = "aid"                    /// `MPVOption.TrackSelection.aid`
    case sid = "sid"                    /// `MPVOption.TrackSelection.sid`
    case s2id = "sid2"                  /// `MPVOption.Subtitles.secondarySid`

    case hwdec = "hwdec"                /// `MPVOption.Video.hwdec`
    case deinterlace = "deinterlace"    /// `MPVOption.Video.deinterlace`
    case hdrEnabled = "hdrEnabled"      /// IINA setting

    case brightness = "brightness"      /// `MPVOption.Equalizer.brightness`
    case contrast = "contrast"          /// `MPVOption.Equalizer.contrast`
    case saturation = "saturation"      /// `MPVOption.Equalizer.saturation`
    case gamma = "gamma"                /// `MPVOption.Equalizer.gamma`
    case hue = "hue"                    /// `MPVOption.Equalizer.hue`

    case videoFilters = "vf"            /// `MPVProperty.vf`
    case audioFilters = "af"            /// `MPVProperty.af`
    case videoFiltersDisabled = "vfDisabled"/// IINA-only

    case playSpeed = "playSpeed"        /// `MPVOption.PlaybackControl.speed`
    case volume = "volume"              /// `MPVOption.Audio.volume`
    case isMuted = "muted"              /// `MPVOption.Audio.mute`
    case maxVolume = "maxVolume"        /// `MPVOption.Audio.volumeMax`
    case audioDelay = "audioDelay"      /// `MPVOption.Audio.audioDelay`
    case abLoopA = "abLoopA"            /// `MPVOption.PlaybackControl.abLoopA`
    case abLoopB = "abLoopB"            /// `MPVOption.PlaybackControl.abLoopB`

    /// Deprecated props, last used in v1.2.2 (replaced by single prop: `.videoGeo`)
    case videoRawWidth = "vidRawW"      /// `MPVProperty.width`
    case videoRawHeight = "vidRawH"     /// `MPVProperty.height`
    case videoAspectLabel = "aspect"    /// Converted into `MPVOption.Video.videoAspectOverride`
    case cropLabel = "cropLabel"        /// Converted into crop filter
    case videoRotation = "videoRotate"  /// `MPVOption.Video.videoRotate`
    case totalRotation = "totalRotation"/// `MPVProperty.videoParamsRotate`

    case isSubVisible = "subVisible"    /// `MPVOption.Subtitles.subVisibility`
    case isSub2Visible = "sub2Visible"  /// `MPVOption.Subtitles.secondarySubVisibility`
    case subDelay = "subDelay"          /// `MPVOption.Subtitles.subDelay`
    case sub2Delay = "sub2Delay"        /// `MPVOption.Subtitles.secondarySubDelay`
    case subPos = "subPos"              /// `MPVOption.Subtitles.subPos`
    case sub2Pos = "sub2Pos"            /// `MPVOption.Subtitles.secondarySubPos`
    case subScale = "subScale"          /// `MPVOption.Subtitles.subScale`

    case loopPlaylist = "loopPlaylist"  /// `MPVOption.PlaybackControl.loopPlaylist`
    case loopFile = "loopFile"          /// `MPVOption.PlaybackControl.loopFile`
  }

  /// Added "1" in v1.2
  static fileprivate let videoGeometryPrefStringVersion1 = "1"
  /// Upgraded to "2" in v1.3
  static fileprivate let videoGeometryPrefStringVersion2 = "2"

  static fileprivate let specPrefStringVersion1 = "1"
  /// Upgraded to "2" in v1.3
  static fileprivate let specPrefStringVersion2 = "2"
  /// Updated to "2" in v1.2
  static fileprivate let windowGeometryPrefStringVersion = "2"
  /// Updated to "2" in v1.2
  static fileprivate let musicModeGeoPrefStringVersion = "2"
  static fileprivate let playlistVideosCSVVersion = "1"

  static let saveQueue = DispatchQueue(label: "IINAPlayerSaveQueue", qos: .background)

  /// IINA general log
  static let log = Logger.log

  /// The player's log
  let log: Logger.Subsystem

  let properties: [String: Any]

  /// Cached values parsed from `properties`

  /// Describes the current layout configuration of the player window.
  /// See `buildWindowInitialLayoutTasks()` in `PlayerWindowLayout.swift`.
  let layoutSpec: LayoutSpec?

  let geoSet: GeometrySet
  let screens: [ScreenMeta]

  init(_ props: [String: Any], playerID: String) {
    self.properties = props
    self.log = Logger.subsystem(forPlayerID: playerID)

    let layoutSpecCSV = PlayerSaveState.string(for: .layoutSpec, props)
    let layoutSpec = LayoutSpec.fromCSV(layoutSpecCSV)
    self.layoutSpec = layoutSpec
    self.geoSet = PlayerSaveState.geoSet(from: props, log)

    self.screens = (props[PropName.screens.rawValue] as? [String] ?? []).compactMap({ScreenMeta.from($0)})
  }

  var description: String {
    guard let urlString = string(for: .url), let url = URL(string: urlString) else {
      return "PlayerSaveState(url=<ERROR>)"
    }

    let urlPath: String
    if #available(macOS 13.0, *) {
      urlPath = url.path(percentEncoded: false)
    } else {
      urlPath = url.path
    }

    let filteredProps = properties.filter({ prop in
      switch prop.key {
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

    let propsString = filteredProps.compactMap{ (key, valRaw) in
      let valToPrint: String
      if let valStr = valRaw as? String {
        valToPrint = valStr.quoted
      } else {
        valToPrint = "\(valRaw)"
      }
      return "\(key.quoted): \(valToPrint)"
    }.joined(separator: ", ")

    return "PlayerSaveState(url=\(urlPath.pii.quoted) props=[\(propsString)])"
  }

  // MARK: - Save State / Serialize to prefs strings

  /// Generates a Dictionary of properties for storage into a Preference entry
  static private func generatePropDict(from player: PlayerCore, _ geo: GeometrySet) -> [String: Any] {
    var props: [String: Any] = [:]
    let info = player.info
    /// Must *not* access `window`: this is not the main thread
    let wc = player.windowController!
    let layout = wc.currentLayout

    let buildNumber: Int = info.priorStateBuildNumber
    props[PropName.buildNumber.rawValue] = buildNumber
    props[PropName.launchID.rawValue] = Preference.UIState.launchID

    // - Window Layout & Geometry

    /// `layoutSpec`
    props[PropName.layoutSpec.rawValue] = layout.spec.toCSV(buildNumber: buildNumber)

    /// `windowedModeGeo`: use supplied GeometrySet for most up-to-date window frame
    props[PropName.windowedModeGeo.rawValue] = geo.windowed.toCSV()

    /// `musicModeGeo`: use supplied GeometrySet for most up-to-date window frame
    props[PropName.musicModeGeo.rawValue] = geo.musicMode.toCSV()

    /// `videoGeo`: use supplied GeometrySet for most up-to-date data (avoiding complex logic to derive it)
    props[PropName.videoGeo.rawValue] = geo.video.toCSV()

    let screenMetaCSVList: [String] = wc.cachedScreens.values.map{$0.toCSV()}
    props[PropName.screens.rawValue] = screenMetaCSVList

    if let size = info.intendedViewportSize {
      let sizeString = [size.width.stringMaxFrac2, size.height.stringMaxFrac2].joined(separator: ",")
      props[PropName.intendedViewportSize.rawValue] = sizeString
    }

    if player.windowController.isOnTop {
      props[PropName.isOnTop.rawValue] = true.yn
    }

    // - Misc window state

    if Preference.bool(for: .autoSwitchToMusicMode) {
      var overrideAutoMusicMode = player.overrideAutoMusicMode
      let audioStatus = player.info.currentMediaAudioStatus
      if (audioStatus == .notAudio && player.isInMiniPlayer) || (audioStatus.isAudio && !player.isInMiniPlayer) {
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
    let playlistPaths: [String] = playlist.compactMap{ Playback.path(from: $0.url) }
    if !playlistPaths.isEmpty {
      props[PropName.playlistPaths.rawValue] = playlistPaths
    }

    if let playbackPositionSec = info.playbackPositionSec {
      props[PropName.playPosition.rawValue] = playbackPositionSec.stringMaxFrac6
    }
    if let playbackDurationSec = info.playbackDurationSec {
      props[PropName.playDuration.rawValue] = playbackDurationSec.stringMaxFrac6
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
    props[PropName.sub2Delay.rawValue] = info.sub2Delay.stringMaxFrac6

    props[PropName.subScale.rawValue] = player.info.subScale.stringMaxFrac2
    props[PropName.subPos.rawValue] = player.info.subPos.stringMaxFrac2
    props[PropName.sub2Pos.rawValue] = player.info.sub2Pos.stringMaxFrac2

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

    // mpv calls - should cache these instead eventually

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

  // Saves this player's state asynchronously
  static func save(_ player: PlayerCore) {
    guard Preference.UIState.isSaveEnabled else { return }

    var ticket: Int = 0
    player.$saveTicketCounter.withLock {
      $0 += 1
      ticket = $0
    }

    /// Runs asynchronously in background queue to avoid blocking UI.
    /// Cuts down on duplicate work via delay and ticket check.
    saveQueue.asyncAfter(deadline: DispatchTime.now() + AppData.playerStateSaveDelay) {
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
        player.log.verbose("Skipping player state save: player is shutting down")
        return
      }
      guard !player.windowController.isClosing else {
        // mpv core is often still active even after closing, and will send events which
        // can trigger save. Need to make sure we check for this so that we don't un-delete state
        player.log.trace("Skipping player state save: window.isClosing is true")
        return
      }

      DispatchQueue.main.async {
        let wc = player.windowController!
        wc.animationPipeline.submitInstantTask {
          guard !wc.isAnimatingLayoutTransition else {
            /// The transition itself will call `save` when it is done. Just return
            return
          }
          // Retrieve appropriate geometry values, updating to latest window frame if needed:
          let geo = wc.buildGeoSet(from: wc.currentLayout)
          saveQueue.async {
            guard !player.isShuttingDown else { return }

            let properties = generatePropDict(from: player, geo)
            if player.log.isTraceEnabled {
              player.log.trace("Saving player state (tkt \(ticket)): \(properties)")
            }
            Preference.UIState.saveState(forPlayerID: player.label, properties: properties)
          }
        }
      }
    }
  }

  static func saveSynchronously(_ player: PlayerCore) {
    assert(DispatchQueue.isExecutingIn(.main))
    player.log.debug("Saving player state synchronously")
    let wc = player.windowController!
    /// Using `sync` here should delay shutdown & makes sure any existing async saves aren't killed mid-write!
    saveQueue.sync {
      // Retrieve appropriate geometry values, updating to latest window frame if needed:
      let geo: GeometrySet
      if wc.isAnimatingLayoutTransition {
        geo = wc.geo
      } else {
        geo = wc.buildGeoSet(from: wc.currentLayout)
      }
      let properties = generatePropDict(from: player, geo)
      if player.log.isTraceEnabled {
        player.log.trace("Saving player state: \(properties)")
      }
      Preference.UIState.saveState(forPlayerID: player.label, properties: properties)
      player.log.debug("Done saving player state synchronously")
    }
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
      log.debug("Failed to parse property as NSSize: \(name.rawValue.quoted)")
    }
    return nil
  }

  func url(for name: PropName) -> URL? {
    if let string = string(for: name) {
      return URL(string: string)
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

  /// Returns IINA-Advance build number associated with stored player's properties (param).
  ///
  /// `2`: default for v1.0 & v1.1, because `buildNumber` property was not added until v1.2.
  /// See: `Constants.BuildNumber`
  static private func buildNumber(from properties: [String: Any]) -> Int {
    return int(for: .buildNumber, properties) ?? Constants.BuildNumber.V1_1
  }

  static private func geoSet(from props: [String: Any], _ log: Logger.Subsystem) -> GeometrySet {
    // VideoGeometry is needed to quickly calculate & restore video dimensions instead of waiting for mpv to provide it
    let buildNumber = buildNumber(from: props)
    let videoGeo: VideoGeometry
    if let parsedVideoGeo = VideoGeometry.fromCSV(PlayerSaveState.string(for: .videoGeo, props), log) {
      videoGeo = parsedVideoGeo
    } else {
      if buildNumber < Constants.BuildNumber.V1_2 {
        // Older than IINA 1.2
        log.debug("Failed to restore VideoGeometry from CSV (build \(buildNumber) properties). Will attempt to build it from legacy properties instead")
      } else {
        log.error("Failed to restore VideoGeometry from CSV (build \(buildNumber) properties)! Possible tampering occurred with the prefs, or a backwards-incompatible version of of IINA Advance was run. Will attempt to build VideoGeometry from legacy properties instead...")
      }
      let defaultGeo = VideoGeometry.defaultGeometry(log)
      let totalRotation = PlayerSaveState.int(for: .totalRotation, props)
      let userRotation = PlayerSaveState.int(for: .videoRotation, props)
      let codecRotation = (totalRotation ?? 0) - (userRotation ?? 0)
      videoGeo = defaultGeo.clone(rawWidth: PlayerSaveState.int(for: .videoRawWidth, props),
                                  rawHeight: PlayerSaveState.int(for: .videoRawHeight, props),
                                  userAspectLabel: PlayerSaveState.string(for: .videoAspectLabel, props),
                                  codecRotation: codecRotation,
                                  userRotation: userRotation,
                                  selectedCropLabel: PlayerSaveState.string(for: .cropLabel, props))
    }

    let windowedCSV = PlayerSaveState.string(for: .windowedModeGeo, props)
    let savedWindowedGeo = PWinGeometry.fromCSV(windowedCSV, videoGeoFallback: videoGeo, log)
    let windowedGeo: PWinGeometry
    if let savedWindowedGeo {
      windowedGeo = savedWindowedGeo
    } else {
      log.error("Failed to restore PWinGeometry from CSV! Will fall back to last closed geometry")
      windowedGeo = PlayerWindowController.windowedModeGeoLastClosed
    }

    let musicModeCSV = PlayerSaveState.string(for: .musicModeGeo, props)
    let savedMusicModeGeo = MusicModeGeometry.fromCSV(musicModeCSV, videoGeoFallback: videoGeo, log)
    let musicModeGeo: MusicModeGeometry
    if let savedMusicModeGeo {
      musicModeGeo = savedMusicModeGeo
    } else {
      log.error("Failed to restore MusicModeGeometry from CSV! Will fall back to last closed geometry")
      musicModeGeo = PlayerWindowController.musicModeGeoLastClosed
    }
    return GeometrySet(windowed: windowedGeo, musicMode: musicModeGeo, video: videoGeo)
  }

  // Utility function for parsing complex object from CSV
  static fileprivate func parseCSV<T>(_ csv: String?, separator: Character = ",",
                                      expectedTokenCount: Int, expectedVersion: String,
                                      targetObjName: String,
                                      _ parseFunc: (String, inout IndexingIterator<[String]>) throws -> T?) rethrows -> T? {
    guard let csv else { return nil }
    log.verbose("Parsing CSV as \(targetObjName): \(csv.quoted)")
    let errPreamble = "Failed to parse \(targetObjName) CSV:"
    let tokens = csv.split(separator: separator).map{String($0)}
    // Check version first, for a cleaner error msg
    guard tokens.count > 0 else {
      log.error("\(errPreamble) could not parse any tokens from CSV for \(targetObjName)! (CSV: \(csv))")
      return nil
    }
    var iter = tokens.makeIterator()
    let version = iter.next()
    guard version == expectedVersion else {
      if let version, let vInt = Int(version), let evInt = Int(expectedVersion), vInt < evInt {
        // Not an error to encounter an old version
        log.verbose("\(errPreamble) version (\(version.quoted)) is older than expected (\(expectedVersion.quoted))")
      } else {
        log.error("\(errPreamble) version found (\(version?.quoted ?? "nil")) too new (expected \(expectedVersion.quoted))")
      }
      return nil
    }

    guard tokens.count == expectedTokenCount else {
      log.error("\(errPreamble) wrong token count (expected \(expectedTokenCount) but found \(tokens.count))")
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
        log.error("Could not parse PlaylistVideoInfo: not enough tokens (expected 3 but found \(tokens.count))")
        continue
      }
      guard tokens[0] == playlistVideosCSVVersion else {
        log.error("Could not parse PlaylistVideoInfo: wrong version (expected \(playlistVideosCSVVersion) but found \(tokens[0].quoted))")
        continue
      }

      guard let prefixLength = Int(tokens[1]),
            let url = URL(string: tokens[2])
      else {
        log.error("Could not parse PlaylistVideoInfo url or prefixLength!")
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
    assert(DispatchQueue.isExecutingIn(.main))

    let log = player.log

    guard let urlString = string(for: .url), let url = URL(string: urlString) else {
      log.error("Could not restore player window: no value for property \(PlayerSaveState.PropName.url.rawValue.quoted)")
      return
    }

    let playback = Playback(url: url)

    if Logger.isEnabled(.verbose) {
      // Log properties
      log.verbose("Restoring from prior launch: \(self)")
    }
    let info = player.info
    info.priorState = self
    info.isRestoring = true

    info.priorStateBuildNumber = int(for: .buildNumber) ?? info.priorStateBuildNumber

    let windowController = player.windowController!
    windowController.geo = self.geoSet

    log.verbose("Screens from prior launch: \(self.screens)")

    if Preference.bool(for: .alwaysPauseMediaWhenRestoringAtLaunch) {
      player.pendingResumeWhenShowingWindow = false
    } else if let wasPaused = bool(for: .paused) {
      player.pendingResumeWhenShowingWindow = !wasPaused
    } else {
      player.pendingResumeWhenShowingWindow = !Preference.bool(for: .pauseWhenOpen)
    }

    // TODO: map current geometry to prior screen. Deal with mismatch

    if let hdrEnabled = bool(for: .hdrEnabled) {
      info.hdrEnabled = hdrEnabled
    }

    // Set these here so that play position slider can be restored to prev position when the window is opened - not after
    if let playbackPositionSec = double(for: .playPosition) {
      info.playbackPositionSec = playbackPositionSec
    }
    if let playbackDurationSec = double(for: .playDuration) {
      info.playbackDurationSec = playbackDurationSec
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
    player.log.verbose("Restored playlist info for \(info.currentVideosInfo.count) videos, \(info.currentSubsInfo.count) subs")

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
    windowController.osd.lastPlaybackPosition = info.playbackPositionSec
    windowController.osd.lastPlaybackDuration = info.playbackDurationSec

    // IINA restore supercedes mpv watch-later.
    // Need to delete the watch-later file before mpv loads it or else things get very buggy
    let watchLaterFileURL = Utility.watchLaterURL.appendingPathComponent(playback.mpvMD5).path
    if FileManager.default.fileExists(atPath: watchLaterFileURL) {
      player.log.debug("Found mpv watch-later file. Deleting it because we are using IINA restore...")
      try? FileManager.default.removeItem(atPath: watchLaterFileURL)
    }

    if let overrideAutoMusicMode = bool(for: .overrideAutoMusicMode) {
      player.overrideAutoMusicMode = overrideAutoMusicMode
    }

    // Open the window!
    player.openURLs([url], shouldAutoLoadPlaylist: false, mpvRestoreWorkItem: { restoreMpvProperties(to: player) })
  }

  /// Restore mpv properties.
  /// Must wait until after mpv init, so that the lifetime of these options is limited to the current file.
  /// Otherwise the mpv core will keep the options for the lifetime of the player, which is often undesirable (for example,
  /// `MPVOption.PlaybackControl.start` will skip any files in the playlist which have durations shorter than its start time).
  private func restoreMpvProperties(to player: PlayerCore) {
    let mpv: MPVController = player.mpv
    let log = player.log

    if let playbackPositionSec = string(for: .playPosition) {
      log.verbose("Restoring playback position: \(playbackPositionSec)")
      mpv.setString(MPVOption.PlaybackControl.start, playbackPositionSec)
    }

    // Better to always pause when starting, because there may be a slight delay before it can be enforced later
    mpv.setFlag(MPVOption.PlaybackControl.pause, true)

    if let hwdec = string(for: .hwdec) {
      mpv.setString(MPVOption.Video.hwdec, hwdec)
    }

    if let deinterlace = bool(for: .deinterlace) {
      mpv.setFlag(MPVOption.Video.deinterlace, deinterlace)
    }

    mpv.setInt(MPVOption.Video.videoRotate, self.geoSet.video.userRotation)

    let userAspectLabel = self.geoSet.video.userAspectLabel
    let mpvValue = Aspect.mpvVideoAspectOverride(fromAspectLabel: userAspectLabel)
    mpv.setString(MPVOption.Video.videoAspectOverride, mpvValue)

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
      player.info.volume = volume
      mpv.setDouble(MPVOption.Audio.volume, volume)
    }
    if let isMuted = bool(for: .isMuted) {
      player.info.isMuted = isMuted
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
    if let sub2Delay = double(for: .sub2Delay) {
      mpv.setDouble(MPVOption.Subtitles.secondarySubDelay, sub2Delay)
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
    if let subPos = double(for: .subPos) {
      mpv.setDouble(MPVOption.Subtitles.subPos, subPos)
    }
    if let sub2Pos = double(for: .sub2Pos) {
      mpv.setDouble(MPVOption.Subtitles.secondarySubPos, sub2Pos)
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

    if let vid = int(for: .vid) {
      mpv.setInt(MPVOption.TrackSelection.vid, vid)
    }
    if let aid = int(for: .aid) {
      mpv.setInt(MPVOption.TrackSelection.aid, aid)
    }
    if let audioFilters = string(for: .audioFilters) {
      mpv.setString(MPVProperty.af, audioFilters)
    }
    if let videoFilters = string(for: .videoFilters) {
      // This includes crop
      mpv.setString(MPVProperty.vf, videoFilters)
    }
  }
}  /// end `struct PlayerSaveState`

struct ScreenMeta {
  static private let expectedCSVTokenCount = 15
  static private let csvVersion: Int = 2

  let displayID: UInt32
  let name: String
  let frame: NSRect
  /// NOTE: `visibleFrame` is highly volatile and will change when Dock or title bar is shown/hidden
  let visibleFrame: NSRect
  let nativeResolution: CGSize
  let cameraHousingHeight: CGFloat
  let backingScaleFactor: CGFloat

  func toCSV() -> String {
    return [String(ScreenMeta.csvVersion), String(displayID), name,
            frame.origin.x.stringMaxFrac2, frame.origin.y.stringMaxFrac2, frame.size.width.stringMaxFrac2, frame.size.height.stringMaxFrac2,
            visibleFrame.origin.x.stringMaxFrac2, visibleFrame.origin.y.stringMaxFrac2, visibleFrame.size.width.stringMaxFrac2, visibleFrame.size.height.stringMaxFrac2,
            nativeResolution.width.stringMaxFrac2, nativeResolution.height.stringMaxFrac2,
            cameraHousingHeight.stringMaxFrac2,
            backingScaleFactor.stringMaxFrac2
    ].joined(separator: ",")
  }

  static func from(_ screen: NSScreen) -> ScreenMeta {
      // Can't store comma in CSV. Just convert to semicolon
    let name: String = screen.localizedName.replacingOccurrences(of: ",", with: ";")
    return ScreenMeta(displayID: screen.displayId, name: name, frame: screen.frame, visibleFrame: screen.visibleFrame,
                      nativeResolution: screen.nativeResolution ?? CGSizeZero, cameraHousingHeight: screen.cameraHousingHeight ?? 0,
                      backingScaleFactor: screen.backingScaleFactor)
  }

  static func from(_ csv: String) -> ScreenMeta? {
    let tokens = csv.split(separator: ",").map{String($0)}
    var iter = tokens.makeIterator()

    guard let versionStr = iter.next(), let version = Int(versionStr) else {
      Logger.log.error("While parsing ScreenMeta from CSV: failed to parse version")
      return nil
    }
    guard version == csvVersion else {
      if version == 1 {
        Logger.log.error("Discarding ScreenMeta from CSV: format is obsolete (expected version \(csvVersion) but found \(version))")
      } else {
        Logger.log.error("While parsing ScreenMeta from CSV: bad version (expected \(csvVersion) but found \(version))")
      }
      return nil
    }
    // Check this after parsing version, for cleaner error messages
    guard tokens.count == expectedCSVTokenCount else {
      Logger.log.error("While parsing ScreenMeta from CSV: wrong token count (expected \(expectedCSVTokenCount) but found \(tokens.count))")
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
          let cameraHousingHeight = Double(iter.next()!),
          let backingScaleFactor = Double(iter.next()!) else {
      Logger.log.error("While parsing ScreenMeta from CSV: could not parse one or more tokens")
      return nil
    }

    let frame = NSRect(x: frameX, y: frameY, width: frameW, height: frameH)
    let visibleFrame = NSRect(x: visibleFrameX, y: visibleFrameY, width: visibleFrameW, height: visibleFrameH)
    let nativeResolution = NSSize(width: nativeResW, height: nativeResH)
    return ScreenMeta(displayID: displayID, name: name, frame: frame, visibleFrame: visibleFrame, nativeResolution: nativeResolution, cameraHousingHeight: cameraHousingHeight, backingScaleFactor: backingScaleFactor)
  }
}

extension VideoGeometry {
  /// `String`, `Logger.Subsystem` -> `VideoGeometry`
  /// Note to maintainers: if compiler is complaining with the message "nil is not compatible with closure result type VideoGeometry",
  /// check the arguments to the `VideoGeometry` constructor. For some reason the error lands in the wrong place.
  static func fromCSV(_ csv: String?, _ log: Logger.Subsystem, separator: Character = ",") -> VideoGeometry? {
    guard let csv, !csv.isEmpty else {
      log.debug("CSV is empty; returning nil for VideoGeometry")
      return nil
    }
    if let vidGeoV2: VideoGeometry = PlayerSaveState.parseCSV(csv, separator: separator, expectedTokenCount: 8,
                                                              expectedVersion: PlayerSaveState.videoGeometryPrefStringVersion2,
                                                              targetObjName: "VideoGeometry v2", { errPreamble, iter in

      guard let rawWidth = Int(iter.next()!),
            let rawHeight = Int(iter.next()!),
            let codecRotation = Int(iter.next()!),
            let userRotation = Int(iter.next()!),
            let codecAspectLabel = iter.next(),
            let userAspectLabel = iter.next(),
            let selectedCropLabel = iter.next()
      else {
        /// NOTE: if Xcode shows the error `'nil' is not compatible with closure result type 'MusicModeGeometry'`
        /// here, it means that the wrong args are being supplied to the`MusicModeGeometry` constructor below.
        log.error("\(errPreamble) could not parse one or more tokens")
        return nil
      }

      return VideoGeometry(rawWidth: rawWidth, rawHeight: rawHeight,
                           codecAspectLabel: codecAspectLabel, userAspectLabel: userAspectLabel,
                           codecRotation: codecRotation, userRotation: userRotation, selectedCropLabel: selectedCropLabel, log: log)
    }) {
      return vidGeoV2
    }

    log.debug("Failed to parse VideoGeometry v2; falling back to v1")
    return PlayerSaveState.parseCSV(csv, separator: separator, expectedTokenCount: 7,
                                    expectedVersion: PlayerSaveState.videoGeometryPrefStringVersion1,
                                    targetObjName: "VideoGeometry v1") { errPreamble, iter in

      guard let rawWidth = Int(iter.next()!),
            let rawHeight = Int(iter.next()!),
            let codecRotation = Int(iter.next()!),
            let userRotation = Int(iter.next()!),
            let userAspectLabel = iter.next(),
            let selectedCropLabel = iter.next()
      else {
        /// NOTE: if Xcode shows the error `'nil' is not compatible with closure result type 'MusicModeGeometry'`
        /// here, it means that the wrong args are being supplied to the`MusicModeGeometry` constructor below.
        log.error("\(errPreamble) could not parse one or more tokens")
        return nil
      }

      let codecAspectLabel = (Double(rawWidth) / Double(rawHeight)).mpvAspectString

      return VideoGeometry(rawWidth: rawWidth, rawHeight: rawHeight,
                           codecAspectLabel: codecAspectLabel, userAspectLabel: userAspectLabel,
                           codecRotation: codecRotation, userRotation: userRotation, selectedCropLabel: selectedCropLabel, log: log)
    }
  }

  /// `VideoGeometry` -> `String`
  func toCSV() -> String {
    "\(PlayerSaveState.videoGeometryPrefStringVersion2),\(fieldStrings.joined(separator: ","))"
  }

  // MARK: Embedded CSV

  fileprivate var fieldStrings: [String] {
    [
      "\(rawWidth)",
      "\(rawHeight)",
      "\(codecRotation)",
      "\(userRotation)",
      "\(codecAspectLabel)",
      "\(userAspectLabel)",
      "\(selectedCropLabel)"
    ]
  }

  /// `VideoGeometry` -> `String` (without version token)
  fileprivate func toEmbeddedCSV() -> String {
    fieldStrings.joined(separator: String(embeddedSeparator))
  }

  /// Assumes embedded CSV is current version (but will fall back & try to parse as prev version if that fails)
  static func fromEmbeddedCSV(_ csvEmbedded: String?, _ log: Logger.Subsystem) -> VideoGeometry? {
    guard let csvEmbedded, !csvEmbedded.isEmpty else {
      log.debug("CSV is empty; returning nil for embedded VideoGeometry")
      return nil
    }
    let csv2 = "\(PlayerSaveState.videoGeometryPrefStringVersion2)\(embeddedSeparator)\(csvEmbedded)"
    if let videoGeoV2 = fromCSV(csv2, log, separator: embeddedSeparator) {
      return videoGeoV2
    } else {
      log.debug("Could not parse embedded VideoGeometry v2; trying v1")
      let csv1 = "\(PlayerSaveState.videoGeometryPrefStringVersion1)\(embeddedSeparator)\(csvEmbedded)"
      return fromCSV(csv1, log, separator: embeddedSeparator)
    }
  }
}

extension MusicModeGeometry {

  /// v2: `String` -> `MusicModeGeometry`
  /// v1: (`String`, `VideoGeometry`) -> `MusicModeGeometry`
  /// Note to maintainers: if compiler is complaining with the message "nil is not compatible with closure result type MusicModeGeometry",
  /// check the arguments to the `MusicModeGeometry` constructor. For some reason the error lands in the wrong place.
  static func fromCSV(_ csv: String?, videoGeoFallback: VideoGeometry? = nil, _ log: Logger.Subsystem) -> MusicModeGeometry? {
    guard let csv, !csv.isEmpty else {
      log.debug("CSV is empty; returning nil for MusicModeGeometry")
      return nil
    }

    // Try v2 first.
    let mmGeo: MusicModeGeometry? = PlayerSaveState.parseCSV(csv, expectedTokenCount: 9,
                                         expectedVersion: PlayerSaveState.musicModeGeoPrefStringVersion,
                                         targetObjName: "MusicModeGeometry(v2)") { errPreamble, iter in

      guard let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let isVideoVisible = Bool.yn(iter.next()!),
            let isPlaylistVisible = Bool.yn(iter.next()!),
            let screenID = iter.next(),
            let videoGeoEmbeddedCSV = iter.next()
      else {
        /// NOTE: if Xcode shows the error `'nil' is not compatible with closure result type 'MusicModeGeometry'`
        /// here, it means that the wrong args are being supplied to the`MusicModeGeometry` constructor below.
        log.error("\(errPreamble) could not parse one or more tokens")
        return nil
      }

      guard let videoGeo = VideoGeometry.fromEmbeddedCSV(videoGeoEmbeddedCSV, log) else {
        Logger.log.error("\(errPreamble) could not parse VideoGeometry")
        return nil
      }

      let windowFrame = CGRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      return MusicModeGeometry(windowFrame: windowFrame,
                               screenID: screenID, video: videoGeo,
                               isVideoVisible: isVideoVisible, isPlaylistVisible: isPlaylistVisible)
    }

    if let mmGeo {
      return mmGeo
    }

    // Fall back to v1
    return PlayerSaveState.parseCSV(csv, expectedTokenCount: 10,
                                    expectedVersion: "1",
                                    targetObjName: "MusicModeGeometry(v1)") { errPreamble, iter in

      guard let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let _ = Double(iter.next()!),  /// was `playlistHeight` (defunct as of 1.1)
            let isVideoVisible = Bool.yn(iter.next()!),
            let isPlaylistVisible = Bool.yn(iter.next()!),
            let _ = Double(iter.next()!),  /// was `videoAspect` (defunct as of 1.2)
            let screenID = iter.next()
      else {
        /// NOTE: if Xcode shows the error `'nil' is not compatible with closure result type 'MusicModeGeometry'`
        /// here, it means that the wrong args are being supplied to the`MusicModeGeometry` constructor below.
        log.error("\(errPreamble) could not parse one or more tokens")
        return nil
      }

      let videoGeo: VideoGeometry
      if let videoGeoFallback {
        videoGeo = videoGeoFallback
      } else {
        log.warn("No VideoGeometry given for legacy v1 MusicModeGeometry! Falling back to default VideoGeometry")
        videoGeo = VideoGeometry.defaultGeometry()
      }

      let windowFrame = CGRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      return MusicModeGeometry(windowFrame: windowFrame,
                               screenID: screenID, video: videoGeo,
                               isVideoVisible: isVideoVisible, isPlaylistVisible: isPlaylistVisible)
    }
  }

  /// `MusicModeGeometry` -> `String`
  func toCSV() -> String {
    return [PlayerSaveState.musicModeGeoPrefStringVersion,
            self.windowFrame.origin.x.stringMaxFrac2,
            self.windowFrame.origin.y.stringMaxFrac2,
            self.windowFrame.width.stringMaxFrac2,
            self.windowFrame.height.stringMaxFrac2,
            self.isVideoVisible.yn,
            self.isPlaylistVisible.yn,
            self.screenID.replacingOccurrences(of: ",", with: ";"),  // ensure it's CSV-compatible
            self.video.toEmbeddedCSV()
    ].joined(separator: ",")
  }
}

extension PWinGeometry {

  /// `PWinGeometry` -> `String`
  func toCSV() -> String {
    return [PlayerSaveState.windowGeometryPrefStringVersion,
            self.topMarginHeight.stringMaxFrac2,
            self.outsideBars.top.stringMaxFrac2,
            self.outsideBars.trailing.stringMaxFrac2,
            self.outsideBars.bottom.stringMaxFrac2,
            self.outsideBars.leading.stringMaxFrac2,
            self.insideBars.top.stringMaxFrac2,
            self.insideBars.trailing.stringMaxFrac2,
            self.insideBars.bottom.stringMaxFrac2,
            self.insideBars.leading.stringMaxFrac2,
            self.viewportMargins.top.stringMaxFrac2,
            self.viewportMargins.trailing.stringMaxFrac2,
            self.viewportMargins.bottom.stringMaxFrac2,
            self.viewportMargins.leading.stringMaxFrac2,
            self.windowFrame.origin.x.stringMaxFrac2,
            self.windowFrame.origin.y.stringMaxFrac2,
            self.windowFrame.width.stringMaxFrac2,
            self.windowFrame.height.stringMaxFrac2,
            String(self.fitOption.rawValue),
            self.screenID.replacingOccurrences(of: ",", with: ";"),  // ensure it's CSV-compatible
            String(self.mode.rawValue),
            self.video.toEmbeddedCSV()
    ].joined(separator: ",")
  }

  /// (`String`, `VideoGeometry`) -> `PWinGeometry`
  /// `log` is needed to construct embedded `VideoGeometry`.
  /// `videoGeoFallback` is only used if CSV is legacy version
  static func fromCSV(_ csv: String?, videoGeoFallback: VideoGeometry? = nil, _ log: Logger.Subsystem) -> PWinGeometry? {
    guard let csv, !csv.isEmpty else {
      Logger.log.debug("CSV is empty; returning nil for geometry")
      return nil
    }

    /// Try v2 first.
    /// Version 2 removes `videoAspect` field and adds 6 `videoGeometry` fields.
    let pwinGeo: PWinGeometry? = PlayerSaveState.parseCSV(csv, expectedTokenCount: 22,
                             expectedVersion: PlayerSaveState.windowGeometryPrefStringVersion,
                                           targetObjName: "PWinGeometry(v2)") { errPreamble, iter in

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
            let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let fitOptionRawValue = Int(iter.next()!),
            let screenID = iter.next(),
            let modeRawValue = Int(iter.next()!),
            let videoGeoEmbeddedCSV = iter.next()
      else {
        Logger.log.error("\(errPreamble) could not parse one or more tokens")
        /// NOTE: if Xcode shows a weird error here, it means that the wrong args are being supplied
        /// to the`PWinGeometry` constructor below, or the constructor of any object passed to it.
        return nil
      }

      guard let mode = PlayerWindowMode(rawValue: modeRawValue) else {
        Logger.log.error("\(errPreamble) unrecognized PlayerWindowMode: \(modeRawValue)")
        return nil
      }
      guard let fitOption = ScreenFitOption(rawValue: fitOptionRawValue) else {
        Logger.log.error("\(errPreamble) unrecognized ScreenFitOption: \(fitOptionRawValue)")
        return nil
      }
      let windowFrame = CGRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      let viewportMargins = MarginQuad(top: viewportMarginTop, trailing: viewportMarginTrailing,
                                       bottom: viewportMarginBottom, leading: viewportMarginLeading)
      let outsideBars = MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                                   bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)
      let insideBars = MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                                  bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)

      guard let videoGeo = VideoGeometry.fromEmbeddedCSV(videoGeoEmbeddedCSV, log) else {
        Logger.log.error("\(errPreamble) could not parse VideoGeometry")
        return nil
      }

      return PWinGeometry(windowFrame: windowFrame, screenID: screenID, fitOption: fitOption, mode: mode, topMarginHeight: topMarginHeight,
                          outsideBars: outsideBars, insideBars: insideBars,
                          viewportMargins: viewportMargins, video: videoGeo)
    }
    if let pwinGeo {
      return pwinGeo
    }

    // Fall back to v1, which did not include embedded VideoGeometry CSV.
    return PlayerSaveState.parseCSV(csv, expectedTokenCount: 22,
                                    expectedVersion: "1",
                                    targetObjName: "PWinGeometry(v1)") { errPreamble, iter in

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
            let _ = iter.next(),  /// was `videoAspect` (defunct as of 1.2)
            let winOriginX = Double(iter.next()!),
            let winOriginY = Double(iter.next()!),
            let winWidth = Double(iter.next()!),
            let winHeight = Double(iter.next()!),
            let fitOptionRawValue = Int(iter.next()!),
            let screenID = iter.next(),
            let modeRawValue = Int(iter.next()!)
      else {
        Logger.log.error("\(errPreamble) could not parse one or more tokens")
        /// NOTE: if Xcode shows a weird error here, it means that the wrong args are being supplied
        /// to the`PWinGeometry` constructor below, or the constructor of any object passed to it.
        return nil
      }

      guard let mode = PlayerWindowMode(rawValue: modeRawValue) else {
        Logger.log.error("\(errPreamble) unrecognized PlayerWindowMode: \(modeRawValue)")
        return nil
      }
      guard let fitOption = ScreenFitOption(rawValue: fitOptionRawValue) else {
        Logger.log.error("\(errPreamble) unrecognized ScreenFitOption: \(fitOptionRawValue)")
        return nil
      }
      let windowFrame = NSRect(x: winOriginX, y: winOriginY, width: winWidth, height: winHeight)
      let viewportMargins = MarginQuad(top: viewportMarginTop, trailing: viewportMarginTrailing,
                                       bottom: viewportMarginBottom, leading: viewportMarginLeading)
      let outsideBars = MarginQuad(top: outsideTopBarHeight, trailing: outsideTrailingBarWidth,
                                   bottom: outsideBottomBarHeight, leading: outsideLeadingBarWidth)
      let insideBars = MarginQuad(top: insideTopBarHeight, trailing: insideTrailingBarWidth,
                                  bottom: insideBottomBarHeight, leading: insideLeadingBarWidth)

      let video: VideoGeometry
      if let videoGeoFallback {
        video = videoGeoFallback
      } else {
        // we will do our best but our best may not be good enough
        Logger.log.error("VideoGeometry for legacy PWinGeometry is nil! Will try to derive it")
        let viewportSize = PWinGeometry.deriveViewportSize(from: windowFrame, topMarginHeight: topMarginHeight, outsideBars: outsideBars)
        let videoSize = viewportSize - viewportMargins.totalSize
        let defaultVideoGeo: VideoGeometry = VideoGeometry.defaultGeometry(log)
        video = defaultVideoGeo.clone(rawWidth: Int(videoSize.width), rawHeight: Int(videoSize.height))
      }

      let pwinGeo = PWinGeometry(windowFrame: windowFrame, screenID: screenID, fitOption: fitOption, mode: mode, topMarginHeight: topMarginHeight,
                          outsideBars: outsideBars, insideBars: insideBars,
                          viewportMargins: viewportMargins, video: video)
      return pwinGeo
    }
  }

}

extension LayoutSpec {
  /// `LayoutSpec` -> `String`
  func toCSV(buildNumber: Int) -> String {
    let leadingSidebarTab: String = self.leadingSidebar.visibleTab?.name ?? "nil"
    let trailingSidebarTab: String = self.trailingSidebar.visibleTab?.name ?? "nil"
    var csvItems = [leadingSidebarTab,
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
    ]

    if buildNumber < Constants.BuildNumber.V1_3 {
      csvItems = [PlayerSaveState.specPrefStringVersion1] + csvItems
    } else { // v1.3
      csvItems = [PlayerSaveState.specPrefStringVersion2] + csvItems + [
        String(moreSidebarState.selectedSubSegment),
        String(moreSidebarState.playlistSidebarWidth)
      ]
    }
    return csvItems.joined(separator: ",")
  }

  /// `String` -> `LayoutSpec`
  static func fromCSV(_ csv: String?) -> LayoutSpec? {
    guard let csv, !csv.isEmpty else {
      Logger.log.debug("CSV is empty; returning nil for LayoutSpec")
      return nil
    }
    let parsingFunc: (String, inout IndexingIterator<[String]>) throws -> LayoutSpec? = { errPreamble, iter in

      let leadingSidebarTab = Sidebar.Tab(name: iter.next())
      let traillingSidebarTab = Sidebar.Tab(name: iter.next())

      guard let modeInt = Int(iter.next()!), let mode = PlayerWindowMode(rawValue: modeInt),
            let isLegacyStyle = Bool.yn(iter.next()) else {
        Logger.log.error("\(errPreamble) could not parse mode or isLegacyStyle")
        return nil
      }

      guard let topBarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let trailingSidebarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let bottomBarPlacement = Preference.PanelPlacement(Int(iter.next()!)),
            let leadingSidebarPlacement = Preference.PanelPlacement(Int(iter.next()!)) else {
        Logger.log.error("\(errPreamble) could not parse bar placements")
        return nil
      }

      guard let enableOSC = Bool.yn(iter.next()),
            let oscPositionInt = Int(iter.next()!),
            let oscPosition = Preference.OSCPosition(rawValue: oscPositionInt) else {
        Logger.log.error("\(errPreamble) could not parse enableOSC or oscPosition")
        return nil
      }

      let interactModeInt = Int(iter.next()!)
      let interactiveMode = InteractiveMode(rawValue: interactModeInt ?? 0) ?? nil  /// `0` === `nil` value

      var leadingTabGroups = Sidebar.TabGroup.fromPrefs(for: .leadingSidebar)
      let leadVis: Sidebar.Visibility = leadingSidebarTab == nil ? .hide : .show(tabToShow: leadingSidebarTab!)
      // If the tab groups prefs changed somehow since the last run, just add it for now so that the geometry can be restored.
      // Will correct this at the end of restore.
      if let visibleTab = leadVis.visibleTab, !leadingTabGroups.contains(visibleTab.group) {
        Logger.log.error("Restore state is invalid: leadingSidebar has visibleTab \(visibleTab.name) which is outside its configured tab groups")
        leadingTabGroups.insert(visibleTab.group)
      }
      let leadingSidebar = Sidebar(.leadingSidebar, tabGroups: leadingTabGroups, placement: leadingSidebarPlacement, visibility: leadVis)

      var trailingTabGroups = Sidebar.TabGroup.fromPrefs(for: .trailingSidebar)
      let trailVis: Sidebar.Visibility = traillingSidebarTab == nil ? .hide : .show(tabToShow: traillingSidebarTab!)
      // Account for invalid visible tab (see note above)
      if let visibleTab = trailVis.visibleTab, !trailingTabGroups.contains(visibleTab.group) {
        Logger.log.error("Restore state is invalid: trailingSidebar has visibleTab \(visibleTab.name) which is outside its configured tab groups")
        trailingTabGroups.insert(visibleTab.group)
      }
      let trailingSidebar = Sidebar(.trailingSidebar, tabGroups: trailingTabGroups, placement: trailingSidebarPlacement, visibility: trailVis)

      let moreSidebarState: Sidebar.SidebarMiscState

      if let selectedSubSegment = Int(iter.next() ?? ""), let playlistWidth = Int(iter.next() ?? "") {
        moreSidebarState = Sidebar.SidebarMiscState(playlistSidebarWidth: playlistWidth,
                                                                   selectedSubSegment: selectedSubSegment)
      } else {
        // v1 of the CSV lacked this info. Fall back to default
        moreSidebarState = Sidebar.SidebarMiscState.fromDefaultPrefs()
      }

      return LayoutSpec(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar, mode: mode, isLegacyStyle: isLegacyStyle, topBarPlacement: topBarPlacement, bottomBarPlacement: bottomBarPlacement, enableOSC: enableOSC, oscPosition: oscPosition, interactiveMode: interactiveMode, moreSidebarState: moreSidebarState)
    }

    do {
      if let specV2 = try PlayerSaveState.parseCSV(csv, expectedTokenCount: 14,
                                                   expectedVersion: PlayerSaveState.specPrefStringVersion2,
                                                   targetObjName: "LayoutSpec", parsingFunc) {
        return specV2
      } else {
        let specV1 = try PlayerSaveState.parseCSV(csv, expectedTokenCount: 12,
                                                  expectedVersion: PlayerSaveState.specPrefStringVersion1,
                                                  targetObjName: "LayoutSpec", parsingFunc)
        return specV1
      }
    } catch {
      Logger.log.error("Caught error while parsing LayoutSpec: \(error)")
      return nil
    }
  }

}
