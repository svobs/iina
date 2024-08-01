//
//  PWinGeoSet.swift
//  iina
//
//  Created by Matt Svoboda on 5/25/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

struct GeometrySet {
  /// If in full screen, this is actually the prior windowed geometry. Can be regular or interactive mode.
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

  func buildGeoSet(windowed: PWinGeometry? = nil, musicMode: MusicModeGeometry? = nil,
                   video: VideoGeometry? = nil, from inputLayout: LayoutState? = nil) -> GeometrySet {
    let latestFrame = window?.frame

    let windowedNew: PWinGeometry
    if let windowed {
      windowedNew = windowed
    } else if inputLayout?.mode.isWindowed ?? false {
      windowedNew = windowedModeGeo.clone(windowFrame: latestFrame, screenID: bestScreen.screenID)
    } else if inputLayout?.mode.isFullScreen ?? false {
      // may have changed screen while in FS
      windowedNew = windowedModeGeo.clone(screenID: bestScreen.screenID)
    } else {
      windowedNew = windowedModeGeo
    }

    let musicModeNew: MusicModeGeometry
    if let musicMode {
      musicModeNew = musicMode
    } else if inputLayout?.mode == .musicMode {
      musicModeNew = musicModeGeo.clone(windowFrame: latestFrame, screenID: bestScreen.screenID)
    } else {
      musicModeNew = musicModeGeo
    }

    return GeometrySet(windowed: windowedNew, musicMode: musicModeNew, video: video ?? self.player.videoGeo)
  }

  func windowedGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil) -> PWinGeometry {
    if currentLayout.mode.isWindowed {
      // If user moved the window recently, window frame might not be completely up to date. Update it & return:
      return windowedModeGeo.clone(windowFrame: window?.frame, screenID: bestScreen.screenID, video: newVidGeo)
    }
    // Doesn't make sense to update window if currently in FS or some other mode. But update video
    return geo.windowed.clone(video: newVidGeo)
  }


  /// See also `windowedGeoForCurrentFrame`
  func musicModeGeoForCurrentFrame(newVidGeo: VideoGeometry? = nil) -> MusicModeGeometry {
    if currentLayout.mode == .musicMode {
      return musicModeGeo.clone(windowFrame: window?.frame, screenID: bestScreen.screenID, video: newVidGeo)
    }
    return geo.musicMode.clone(video: newVidGeo)
  }

}
