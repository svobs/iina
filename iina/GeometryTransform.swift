//
//  GeometryTransform.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-08.
//


struct GeometryTransform {
  /// Can be used for `VideoGeometry` transforms, `PWinGeometry` transforms, or `MusicModeGeometry` transforms.
  struct Context {
    /// Name of the transform
    let name: String
    /// Contains most up-to-date version of the geometries (as well as possibly unapplied changes), which transforms should build
    /// on top of. (The `PlayerWindowController`'s `geo` field should not be referenced).
    let oldGeo: GeometrySet

    // Other state at the time of transform (immutable)

    let sessionState: PWinSessionState
    let currentPlayback: Playback
    let vidTrackID: Int
    let currentMediaAudioStatus: PlaybackInfo.CurrentMediaAudioStatus

    let player: PlayerCore

    var log: Logger.Subsystem { player.log }

    func clone(oldGeo: GeometrySet? = nil, sessionState: PWinSessionState? = nil) -> Context {
      return Context(name: self.name, oldGeo: oldGeo ?? self.oldGeo,
                     sessionState: sessionState ?? self.sessionState, currentPlayback: self.currentPlayback,
                     vidTrackID: self.vidTrackID, currentMediaAudioStatus: self.currentMediaAudioStatus,
                     player: player)
    }

    /// If current media is file, this should be called after it is done loading.
    /// If current media is network resource, should be called immediately & show buffering msg.
    /// If current media's vid track changed, may need to apply new geometry
    func trackChanged() -> VideoGeometry? {
      assert(DispatchQueue.isExecutingIn(player.mpv.queue))

      guard let videoGeo = syncVideoParamsFromMpv() else { return nil }
      if currentMediaAudioStatus.isAudio || vidTrackID == 0 {
        // Square album art
        return videoGeo
      }

      // Use cached video info (if it is available) to set the correct video geometry right away and without waiting for mpv.
      // This is optional but provides a better viewer experience.
      let ffMeta = currentPlayback.isNetworkResource ? nil : MediaMetaCache.shared.getOrReadVideoMeta(forURL: currentPlayback.url, log)

      if let ffMeta {
        log.debug{"[applyVideoGeo \(name)] Substituting ffMeta \(ffMeta) into videoGeo \(videoGeo)"}
        return videoGeo.substituting(ffMeta)
      } else {
        log.debug{"[applyVideoGeo \(name)] Derived videoGeo \(videoGeo)"}
        return videoGeo
      }
    }  // end of transform block

    func syncVideoParamsFromMpv() -> VideoGeometry? {
      log.verbose{"[applyVideoGeo \(name)] Starting transform, vid=\(String(vidTrackID))|\(currentMediaAudioStatus), sessionState=\(sessionState)"}
      let vid = Int(player.mpv.getInt(MPVOption.TrackSelection.vid))
      guard vidTrackID == vid else {
        log.debug{"[applyVideoGeo \(name)] Aborting transform, vid=\(String(vidTrackID)) != actual vid \(vidTrackID)"}
        return nil
      }

      if currentMediaAudioStatus.isAudio || vidTrackID == 0 {
        // Square album art
        log.debug{"[applyVideoGeo \(name)] Using albumArtGeometry ∵ isAudio=\(currentMediaAudioStatus.isAudio.yn) vid=\(vidTrackID)"}
        return VideoGeometry.albumArtGeometry(log)
      }

      // Sync video's raw dimensions from mpv.
      // This is especially important for streaming videos, which won't have cached ffMeta
      let vidWidth = player.mpv.getInt(MPVProperty.width)
      let vidHeight = player.mpv.getInt(MPVProperty.height)
      let rawWidth: Int?
      let rawHeight: Int?
      if vidWidth > 0 && vidHeight > 0 {
        rawWidth = vidWidth
        rawHeight = vidHeight
      } else {
        if vidTrackID != 0 {
          log.warn("[applyVideoGeo \(name)]: mpv returned 0 for video dimensions, using cached video info instead")
        }
        rawWidth = nil
        rawHeight = nil
      }

      // TODO: sync video-crop (actually, add support for video-crop...)

      // Do NOT use video-params/aspect-name! As of mpv 0.39.0 it may not match video-params/aspect!
      let codecAspect: String? = player.mpv.getString(MPVProperty.videoParamsAspect)  // will be nil if no video track

      // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
      var userAspectLabelDerived = ""
      if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
        userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
        if userAspectLabelDerived != oldGeo.video.userAspectLabel {
          // Not necessarily an error? Need to improve aspect name matching logic
          log.debug{"[applyVideoGeo \(name)] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(oldGeo.video.userAspectLabel.quoted))"}
        }
      }

      // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
      let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

      // If opening window, videoGeo may still have the global (default) log. Update it
      let videoGeo = oldGeo.video.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                                codecAspectLabel: codecAspect,
                                                userAspectLabel: userAspectLabelDerived,
                                                userRotation: userRotation,
                                                log)

      // FIXME: audioStatus==notAudio for playlist which auto-plays audio
      if !currentMediaAudioStatus.isAudio, vidTrackID != 0 {
        let dwidth = player.mpv.getInt(MPVProperty.dwidth)
        let dheight = player.mpv.getInt(MPVProperty.dheight)

        let ours = videoGeo.videoSizeCA
        // Apparently mpv can sometimes add a pixel. Not our fault...
        if (Int(ours.width) - dwidth).magnitude > 1 || (Int(ours.height) - dheight).magnitude > 1 {
          player.log.errorDebugAlert{"[applyVideoGeo \(name)] ❌ Sanity check for VideoGeometry failed: mpv dsize (\(dwidth)x\(dheight)) ≠ our videoSizeCA (\(ours)). VidTrack=\(vidTrackID) \(currentMediaAudioStatus) vidAspect=\(codecAspect ?? "nil")"}
        }
      }

      return videoGeo
    }
  }

  let name: String

  /// If func returns `nil`, transition should be aborted. But if func is `nil`, treat as no-op.
  let changeState: ((Context) -> PWinSessionState?)?
  let videoTransform: ((Context) -> VideoGeometry?)?
  let windowedTransform: ((Context) -> PWinGeometry?)?
  let musicModeTransform: ((Context) -> MusicModeGeometry?)?

  init(name: String,
       changeState: ((Context) -> PWinSessionState?)? = nil,
       videoTransform: ((Context) -> VideoGeometry?)? = nil,
       windowedTransform: ((Context) -> PWinGeometry?)? = nil,
       musicModeTransform: ((Context) -> MusicModeGeometry?)? = nil) {
    self.name = name
    self.changeState = changeState
    self.videoTransform = videoTransform
    self.windowedTransform = windowedTransform
    self.musicModeTransform = musicModeTransform
  }

  private static func defaultVideoTransform(_ context: Context) -> VideoGeometry? {
    return context.oldGeo.video
  }

  private static func defaultWindowedGeoTransform(_ context: Context) -> PWinGeometry? {
    return context.oldGeo.windowed
  }

  private static func defaultMusicModeTransform(_ context: Context) -> MusicModeGeometry? {
    return context.oldGeo.musicMode
  }

  static func trackChanged(_ context: Context) -> VideoGeometry? {
    context.trackChanged()
  }
}
