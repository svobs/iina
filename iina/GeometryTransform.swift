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

  private static func windowedGeoTransform(_ context: Context) -> PWinGeometry? {
    return context.oldGeo.windowed
  }

  private static func musicModeTransform(_ context: Context) -> MusicModeGeometry? {
    return context.oldGeo.musicMode
  }

  /// If current media is file, this should be called after it is done loading.
  /// If current media is network resource, should be called immediately & show buffering msg.
  /// If current media's vid track changed, may need to apply new geometry
  static func trackChanged(_ context: Context) -> VideoGeometry? {
    let player = context.player
    let log = context.log
    assert(DispatchQueue.isExecutingIn(player.mpv.queue))

    let vidTrackID = context.vidTrackID
    let currentPlayback = context.currentPlayback
    log.verbose{"[applyVideoGeo \(context.name)] Starting transform, vid=\(String(vidTrackID))|\(context.currentMediaAudioStatus), sessionState=\(context.sessionState)"}
    let vid = Int(player.mpv.getInt(MPVOption.TrackSelection.vid))
    guard vidTrackID == vid else {
      log.debug{"[applyVideoGeo \(context.name)] Aborting transform, vid=\(String(vidTrackID)) != actual vid \(vidTrackID)"}
      return nil
    }

    if context.currentMediaAudioStatus.isAudio || vidTrackID == 0 {
      // Square album art
      log.debug{"[applyVideoGeo \(context.name)] Using albumArtGeometry because current media is audio"}
      return VideoGeometry.albumArtGeometry(log)
    }

    // Use cached video info (if it is available) to set the correct video geometry right away and without waiting for mpv.
    // This is optional but provides a better viewer experience.
    let ffMeta = currentPlayback.isNetworkResource ? nil : MediaMetaCache.shared.getOrReadVideoMeta(forURL: currentPlayback.url, log)

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
        log.warn("[applyVideoGeo \(context.name)]: mpv returned 0 for video dimensions, using cached video info instead")
      }
      rawWidth = nil
      rawHeight = nil
    }

    // TODO: sync video-crop (actually, add support for video-crop...)

    // Try video-params/aspect-name first, for easier lookup. But always store as ratio or decimal number
    let mpvVideoParamsAspectName = player.mpv.getString(MPVProperty.videoParamsAspectName)
    var codecAspect: String?
    if let mpvVideoParamsAspectName, Aspect.isValid(mpvVideoParamsAspectName) {
      codecAspect = Aspect.resolvingMpvName(mpvVideoParamsAspectName)
    } else {
      codecAspect = player.mpv.getString(MPVProperty.videoParamsAspect)  // will be nil if no video track
    }

    // Sync video-aspect-override. This does get synced from an mpv notification, but there is a noticeable delay
    var userAspectLabelDerived = ""
    if let mpvVideoAspectOverride = player.mpv.getString(MPVOption.Video.videoAspectOverride) {
      userAspectLabelDerived = Aspect.bestLabelFor(mpvVideoAspectOverride)
      if userAspectLabelDerived != context.oldGeo.video.userAspectLabel {
        // Not necessarily an error? Need to improve aspect name matching logic
        log.debug{"[applyVideoGeo \(context.name)] Derived userAspectLabel \(userAspectLabelDerived.quoted) from mpv video-aspect-override (\(mpvVideoAspectOverride)), but it does not match existing userAspectLabel (\(context.oldGeo.video.userAspectLabel.quoted))"}
      }
    }

    // Sync from mpv's rotation. This is essential when restoring from watch-later, which can include video geometries.
    let userRotation = player.mpv.getInt(MPVOption.Video.videoRotate)

    // If opening window, videoGeo may still have the global (default) log. Update it
    let videoGeo = context.oldGeo.video.clone(rawWidth: rawWidth, rawHeight: rawHeight,
                                              codecAspectLabel: codecAspect,
                                              userAspectLabel: userAspectLabelDerived,
                                              userRotation: userRotation,
                                              log)

    // FIXME: audioStatus==notAudio for playlist which auto-plays audio
    if !context.currentMediaAudioStatus.isAudio, vidTrackID != 0 {
      let dwidth = player.mpv.getInt(MPVProperty.dwidth)
      let dheight = player.mpv.getInt(MPVProperty.dheight)

      let ours = videoGeo.videoSizeCA
      // Apparently mpv can sometimes add a pixel. Not our fault...
      if (Int(ours.width) - dwidth).magnitude > 1 || (Int(ours.height) - dheight).magnitude > 1 {
        player.log.error{"❌ Sanity check for VideoGeometry failed: mpv dsize (\(dwidth) x \(dheight)) != our videoSizeCA \(ours), videoTrack=\(vidTrackID)|\(context.currentMediaAudioStatus)"}
      }
    }

    if let ffMeta {
      log.debug{"[applyVideoGeo \(context.name)] Substituting ffMeta \(ffMeta) into videoGeo \(videoGeo)"}
      return videoGeo.substituting(ffMeta)
    } else {
      log.debug{"[applyVideoGeo \(context.name)] Derived videoGeo \(videoGeo)"}
      return videoGeo
    }
  }  // end of transform block

}
