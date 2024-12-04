//
//  NowPlayingInfoManager.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-03.
//  Copyright © 2024 lhc. All rights reserved.
//
import Foundation
import MediaPlayer

class MediaPlayerIntegration {
  static let shared = MediaPlayerIntegration()

  @Atomic private var enabled = false
  private let remoteCommand = MPRemoteCommandCenter.shared()

  func update() {
    DispatchQueue.execSyncOrAsyncIfNotIn(.main) { [self] in
      guard !AppDelegate.shared.isTerminating else { return }
      let newEnablement = Preference.bool(for: .useMediaKeys)
      updateEnablement(to: newEnablement)
    }
  }

  private func updateEnablement(to newEnablement: Bool) {
    assert(DispatchQueue.isExecutingIn(.main))

    let didChange: Bool = $enabled.withLock {
      let didChange = $0 != newEnablement
      if didChange {
        $0 = newEnablement
      }
      return didChange
    }
    if didChange {
      if newEnablement {
        attachRemoteCommands()
      } else {
        detachAllCommands()
      }
    }

    if newEnablement {
      updateNowPlayingInfo()
    }
  }

  func shutdown() {
    updateEnablement(to: false)
  }

  private func attachRemoteCommands() {
    Logger.log("Attaching MediaPlayer remote commands")
    remoteCommand.playCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.resume()
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.pauseCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.pause()
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.togglePlayPauseCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.togglePause()
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.stopCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.stop()
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.nextTrackCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.navigateInPlaylist(nextMedia: true)
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.previousTrackCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.navigateInPlaylist(nextMedia: false)
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.changeRepeatModeCommand.addTarget { [self] _ in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.nextLoopMode()
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.changeShuffleModeCommand.isEnabled = false
    // remoteCommand.changeShuffleModeCommand.addTarget {})
    remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
    remoteCommand.changePlaybackRateCommand.addTarget { [self] event in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.setSpeed(Double((event as! MPChangePlaybackRateCommandEvent).playbackRate))
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.skipForwardCommand.preferredIntervals = [15]
    remoteCommand.skipForwardCommand.addTarget { [self] event in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.seek(relativeSecond: (event as! MPSkipIntervalCommandEvent).interval, option: .defaultValue)
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.skipBackwardCommand.preferredIntervals = [15]
    remoteCommand.skipBackwardCommand.addTarget { [self] event in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.seek(relativeSecond: -(event as! MPSkipIntervalCommandEvent).interval, option: .defaultValue)
      updateCommandEnablements(for: player)
      return .success
    }
    remoteCommand.changePlaybackPositionCommand.addTarget { [self] event in
      guard let player = PlayerCore.lastActive else { return .commandFailed }
      player.seek(absoluteSecond: (event as! MPChangePlaybackPositionCommandEvent).positionTime)
      updateCommandEnablements(for: player)
      return .success
    }
  }

  private func detachAllCommands() {
    Logger.log("Detaching MediaPlayer remote commands")
    remoteCommand.playCommand.removeTarget(nil)
    remoteCommand.pauseCommand.removeTarget(nil)
    remoteCommand.togglePlayPauseCommand.removeTarget(nil)
    remoteCommand.stopCommand.removeTarget(nil)
    remoteCommand.nextTrackCommand.removeTarget(nil)
    remoteCommand.previousTrackCommand.removeTarget(nil)
    remoteCommand.changeRepeatModeCommand.removeTarget(nil)
//    remoteCommand.changeShuffleModeCommand.removeTarget(nil)
    remoteCommand.changePlaybackRateCommand.removeTarget(nil)
    remoteCommand.skipForwardCommand.removeTarget(nil)
    remoteCommand.skipBackwardCommand.removeTarget(nil)
    remoteCommand.changePlaybackPositionCommand.removeTarget(nil)
  }


  /// Update the information shown by macOS in `Now Playing`.
  ///
  /// The macOS [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// contains a `Now Playing` module. This module can also be configured to be directly accessible from the menu bar.
  /// `Now Playing` displays the title of the media currently  playing and other information about the state of playback. It also can be
  /// used to control playback. IINA is fully integrated with the macOS `Now Playing` module.
  ///
  /// - Note: See [Becoming a Now Playable App](https://developer.apple.com/documentation/mediaplayer/becoming_a_now_playable_app)
  ///         and [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
  ///         for more information.
  ///
  /// - Important: This method **must** be run on the main thread because it references `PlayerCore.lastActive`.
  func updateNowPlayingInfo() {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [String: Any]()

    guard let activePlayer = PlayerCore.lastActive, !activePlayer.isStopping else {
      center.playbackState = .unknown
      center.nowPlayingInfo = nil
      updateEnablement(to: false)
      return
    }

    if activePlayer.info.currentMediaAudioStatus.isAudio {
      info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
      let (title, album, artist) = activePlayer.getMusicMetadata()
      info[MPMediaItemPropertyTitle] = title
      info[MPMediaItemPropertyAlbumTitle] = album
      info[MPMediaItemPropertyArtist] = artist
    } else {
      info[MPMediaItemPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
      info[MPMediaItemPropertyTitle] = activePlayer.getMediaTitle(withExtension: false)
    }
    let artwork = MPMediaItemArtwork(boundsSize: activePlayer.videoGeo.videoSizeCAR, requestHandler: { displaySize in
      // Use thumbnail if available
      // TODO: cache this
      if let currentPosition = activePlayer.info.playbackPositionSec, activePlayer.info.isVideoTrackSelected,
         let thumbImg = activePlayer.info.currentPlayback?.thumbnails?.getThumbnail(forSecond: currentPosition)?.image {
        // Crop to aspect ratio of requested size, rather than stretching/squeezing. Then resize
        let cropRect = thumbImg.size().getCropRect(withAspect: displaySize.aspect)
        if let previewImg = thumbImg.cropping(to: cropRect)?.resized(newWidth: displaySize.widthInt, newHeight: displaySize.heightInt).toNSImage() {
          return previewImg
        }
      }
      // Default album art
      return #imageLiteral(resourceName: "default-album-art").resized(newWidth: displaySize.widthInt, newHeight: displaySize.heightInt)
    })
    info[MPMediaItemPropertyArtwork] = artwork

    let duration = activePlayer.info.playbackDurationSec ?? 0
    let time = activePlayer.info.playbackPositionSec ?? 0
    let speed = activePlayer.info.playSpeed

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    info[MPNowPlayingInfoPropertyPlaybackRate] = speed
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1

    center.nowPlayingInfo = info

    if activePlayer.info.isFileLoaded {
      center.playbackState = activePlayer.info.isPaused ? .paused : .playing
    } else {
      center.playbackState = .unknown
    }

    updateCommandEnablements(for: activePlayer)
  }

  private func updateCommandEnablements(for player: PlayerCore) {
    remoteCommand.skipBackwardCommand.isEnabled = player.canSkipBackward
    remoteCommand.skipForwardCommand.isEnabled = player.canSkipForward
    remoteCommand.previousTrackCommand.isEnabled = player.canPlayPrevTrack
    remoteCommand.nextTrackCommand.isEnabled = player.canPlayNextTrack
  }
}
