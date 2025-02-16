//
//  PWinGeoSet.swift
//  iina
//
//  Created by Matt Svoboda on 2024/05/25.
//

import Foundation

/// Describes the current panel sizes & locations for all modes of a unique `PlayerWindow`.
struct GeometrySet {
  /// The window geometry, whether in regular  or interactive mode.
  ///
  /// Full screen geometry is not stored in a `GeometrySet`, but is expected to be derived from the properties
  /// of `windowed`
  let windowed: PWinGeometry
  let musicMode: MusicModeGeometry
  let video: VideoGeometry

  init(windowed: PWinGeometry, musicMode: MusicModeGeometry, video: VideoGeometry) {
    self.windowed = windowed
    self.musicMode = musicMode
    self.video = video
  }

  /// Makes a copy of this `GeometrySet` but uses the given `windowed` geometry, and uses its `VideoGeometry`
  /// as the new current video settings.
  func clone(windowed: PWinGeometry) -> GeometrySet {
    return GeometrySet(windowed: windowed, musicMode: self.musicMode, video: windowed.video)
  }

  /// Makes a copy of this `GeometrySet` but uses the given `musicMode` geometry, and uses its `VideoGeometry`
  /// as the new current video settings.
  func clone(musicMode: MusicModeGeometry) -> GeometrySet {
    return GeometrySet(windowed: self.windowed, musicMode: musicMode, video: musicMode.video)
  }
}

extension PlayerWindowController {
  func getLatestWindowFrameAndScreenID(force: Bool = false) -> (NSRect, String)? {
    guard DispatchQueue.isExecutingIn(.main, logError: false) else {
      log.debug("Not executing in main queue; will use cached window frame & screenID")
      return nil
    }
    guard let window else { return nil }
    if !force {
      // Need to check state of current playback to avoid race conditions
      guard loaded, player.isActive, player.info.isFileLoaded,
            window.isOpen else {
        log.trace{"Will use cached windowFrame/screenID instead of latest: playerActive=\(player.isActive) fileLoaded=\(player.info.isFileLoaded) wndOpen=\(window.isOpen.yn)"}
        return nil
      }
      guard !sessionState.isRestoring else {
        // Log this. It can sometimes indicate a bug during launch
        log.debug("Still restoring; will use cached window frame & screenID")
        if !Preference.bool(for: .isRestoreInProgress) {
          log.error("Window still has sessionState==restoring, but isRestoreInProgress==NO. This is a bug!")
        }
        return nil
      }
    }
    return (window.frame, bestScreen.screenID)
  }

  func buildGeoSet(windowed: PWinGeometry? = nil, musicMode: MusicModeGeometry? = nil,
                   video: VideoGeometry? = nil, from inputLayout: LayoutState,
                   baseGeoSet: GeometrySet? = nil) -> GeometrySet {
    let geo = baseGeoSet ?? geo

    let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID() ?? (nil, nil)
    let mode: PlayerWindowMode? = (inputLayout.mode == currentLayout.mode) ? inputLayout.mode : nil

    let windowedNew: PWinGeometry
    if let windowed {
      windowedNew = windowed
    } else if mode?.isWindowed ?? false {
      windowedNew = geo.windowed.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, video: video)
    } else if mode?.isFullScreen ?? false {
      // may have changed screen while in FS
      windowedNew = geo.windowed.clone(screenID: latestScreenID, video: video)
    } else {
      windowedNew = geo.windowed
    }

    let musicModeNew: MusicModeGeometry
    if let musicMode {
      musicModeNew = musicMode
    } else if mode == .musicMode {
      musicModeNew = geo.musicMode.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, video: video)
    } else {
      musicModeNew = geo.musicMode
    }

    return GeometrySet(windowed: windowedNew, musicMode: musicModeNew, video: video ?? geo.video)
  }

  /// If `force=true`, then skip validation checks for latest frame & always use current frame
  func windowedGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil, force: Bool = false) -> PWinGeometry {
    let geo = geo
    if currentLayout.mode.isWindowed, let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID(force: force) {
      log.trace{"Cloning windowed geometry with current windowFrame=\(latestWindowFrame), screenID=\(latestScreenID.quoted)"}
      // If user moved the window recently, window frame might not be completely up to date. Update it & return:
      return geo.windowed.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, video: newVidGeo)
    }
    // Doesn't make sense to update window if currently in FS or some other mode. But update video
    log.trace{"Cloning windowed geometry, updating only videoGeo=\(newVidGeo?.description ?? "nil")"}
    return geo.windowed.clone(video: newVidGeo)
  }


  /// See also `windowedGeoForCurrentFrame`
  func musicModeGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil, force: Bool = false) -> MusicModeGeometry {
    let geo = geo
    if currentLayout.mode == .musicMode, let (latestWindowFrame, latestScreenID) = getLatestWindowFrameAndScreenID(force: force) {
      log.trace{"Cloning musicMode geometry with current windowFrame=\(latestWindowFrame), screenID=\(latestScreenID.quoted)"}
      return geo.musicMode.clone(windowFrame: latestWindowFrame, screenID: latestScreenID, video: newVidGeo)
    }
    return geo.musicMode.clone(video: newVidGeo)
  }

}
