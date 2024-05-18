//
//  Data.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

struct AppData {
  static func label(forPlayerCore playerCoreCounter: Int) -> String {
    return "\(Preference.UIState.launchID)c\(playerCoreCounter)"
  }

  /** time interval to sync play pos & other UI */
  struct SyncTimerConfig {
    let interval: TimeInterval
    let tolerance: TimeInterval
  }
  static let syncTimerConfig = SyncTimerConfig(interval: 0.1, tolerance: 0.02)
//  static let syncTimerPreciseConfig = SyncTimerConfig(interval: 0.04, tolerance: 0.01)

  /// If state save is enabled and video is playing, make sure player is saved every this number of secs
  static let playTimeSaveStateIntervalSec: TimeInterval = 10.0
  static let asynchronousModeTimeIntervalSec: TimeInterval = 2.0

  /** speed values when clicking left / right arrow button */

//  static let availableSpeedValues: [Double] = [-32, -16, -8, -4, -2, -1, 1, 2, 4, 8, 16, 32]
  // Stopgap for https://github.com/mpv-player/mpv/issues/4000
  static let availableSpeedValues: [Double] = [0.03125, 0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32]

  /** min/max speed for playback **/
  static let minSpeed = 0.25
  static let maxSpeed = 16.0

  /** For Force Touch. */
  static let minimumPressDuration: TimeInterval = 0.5

  /// Minimum value to set a mpv loop point to.
  ///
  /// Setting a loop point to zero disables looping, so when loop points are being adjusted IINA must ensure the mpv property is not
  /// set to zero. However using `Double.leastNonzeroMagnitude` as the minimum value did not work because mpv truncates
  /// the value when storing the A-B loop points in the watch later file. As a result the state of the A-B loop feature is not properly
  /// restored when the media is played again. Using the following value as the minimum for loop points avoids this issue. 
  static let minLoopPointTime = 0.000001

  static let osdSeekSubSecPrecisionComparison: Double = 1000000

  static let mpvArgNone = "none"

  // These are used internally to identify UI elements. They should not be displayed because they are not localized:
  static let defaultAspectIdentifier = "Default"
  static let noneCropIdentifier = "None"
  static let customCropIdentifier = "Custom"
  /// Used to generate aspect and crop options in menu. Does not include `Default`, `None`, or `Custom`
  static let aspectsInMenu: [String] = ["4:3", "5:4", "16:9", "16:10", "1:1", "3:2", "2.21:1", "2.35:1", "2.39:1",
                                        "3:4", "4:5", "9:16", "10:16", "2:3", "1:2.35", "1:2.39", "21:9"]

  static let rotations: [Int] = [0, 90, 180, 270]
  static let scaleStep: CGFloat = 25

  /** Seek amount */
  static let seekAmountMap = [0, 0.05, 0.1, 0.25, 0.5]
  static let seekAmountMapMouse = [0, 0.5, 1, 2, 4]
  static let volumeMap = [0, 0.25, 0.5, 0.75, 1]

  // Time in seconds to wait before regenerating thumbnails.
  // Each character the user types into the thumbnailWidth text field triggers a new thumb regen request.
  // This should help cut down on unnecessary requests.
  static let thumbnailRegenerationDelay = 0.5
  static let playerStateSaveDelay = 0.2
  // Delay before auto-loading playlist from files in the opened file's directory
  static let autoLoadDelay = 1.0

  static let minThumbnailsPerFile = 1

  static let encodings = CharEncoding.list

  static let userInputConfFolder = "input_conf"
  static let watchLaterFolder = "watch_later"
  static let pluginsFolder = "plugins"
  static let binariesFolder = "bin"
  static let historyFile = "history.plist"
  static let thumbnailCacheFolder = "thumb_cache"
  static let screenshotCacheFolder = "screenshot_cache"

  static let githubLink = "https://github.com/svobs/iina-advance"
  static let contributorsLink = "https://github.com/iina/iina/graphs/contributors"
  static let crowdinMembersLink = "https://crowdin.com/project/iina/members"
  static let wikiLink = "https://github.com/iina/iina/wiki"
  static let websiteLink = "https://iina.io"
  static let emailLink = "developers@iina.io"
  static let ytdlHelpLink = "https://github.com/yt-dlp/yt-dlp/blob/master/README.md"
  static let appcastLink = "https://www.iina.io/appcast.xml"
  static let appcastBetaLink = "https://www.iina.io/appcast-beta.xml"
  static let assrtRegisterLink = "https://secure.assrt.net/user/register.xml?redir=http%3A%2F%2Fassrt.net%2Fusercp.php"
  static let chromeExtensionLink = "https://chrome.google.com/webstore/detail/open-in-iina/pdnojahnhpgmdhjdhgphgdcecehkbhfo"
  static let firefoxExtensionLink = "https://addons.mozilla.org/addon/open-in-iina-x"
  static let toneMappingHelpLink = "https://en.wikipedia.org/wiki/Tone_mapping"
  static let targetPeakHelpLink = "https://mpv.io/manual/stable/#options-target-peak"
  static let algorithmHelpLink = "https://mpv.io/manual/stable/#options-tone-mapping"

  static let confFileExtension = "conf"

  // Immmutable default input configs.
  // TODO: combine into a SortedDictionary when available
  static let defaultConfNamesSorted = ["IINA Default", "mpv Default", "VLC Default", "Movist Default"]
  static let defaultConfs: [String: String] = [
    "IINA Default": Bundle.main.path(forResource: "iina-default-input", ofType: AppData.confFileExtension, inDirectory: "config")!,
    "mpv Default": Bundle.main.path(forResource: "input", ofType: AppData.confFileExtension, inDirectory: "config")!,
    "VLC Default": Bundle.main.path(forResource: "vlc-default-input", ofType: AppData.confFileExtension, inDirectory: "config")!,
    "Movist Default": Bundle.main.path(forResource: "movist-default-input", ofType: AppData.confFileExtension, inDirectory: "config")!
  ]
  // Max allowed lines when reading a single input config file, or reading them from the Clipboard.
  static let maxConfFileLinesAccepted = 10000

  /// Based on mpv default
  static let defaultVideoSize = NSSize(width: 640, height: 480)

  /// Absolute minimum allowed rendered video size. Does not include viewport or any other panels which are outside the video.
  static let minVideoSize = NSMakeSize(8, 8)
}

struct Constants {
  struct String {
    static let degree = "°"
    static let dot = "●"
    static let play = "▶︎"
    static let videoTimePlaceholder = "D-:--:-D"
    static let trackNone = NSLocalizedString("track.none", comment: "<None>")
    static let chapter = "Chapter"
    static let fullScreen = NSLocalizedString("menu.fullscreen", comment: "Full Screen")
    static let exitFullScreen = NSLocalizedString("menu.exit_fullscreen", comment: "Exit Full Screen")
    static let pause = NSLocalizedString("menu.pause", comment: "Pause")
    static let resume = NSLocalizedString("menu.resume", comment: "Resume")
    static let `default` = NSLocalizedString("quicksetting.item_default", comment: "Default")
    static let none = NSLocalizedString("quicksetting.item_none", comment: "None")
    static let audioDelay = "Audio Delay"
    static let subDelay = "Subtitle Delay"
    static let pip = NSLocalizedString("menu.pip", comment: "Enter Picture-in-Picture")
    static let exitPIP = NSLocalizedString("menu.exit_pip", comment: "Exit Picture-in-Picture")
    static let miniPlayer = NSLocalizedString("menu.mini_player", comment: "Enter Music Mode")
    static let exitMiniPlayer = NSLocalizedString("menu.exit_mini_player", comment: "Exit Music Mode")
    static let custom = NSLocalizedString("menu.crop_custom", comment: "Custom crop size")
    static let findOnlineSubtitles = NSLocalizedString("menu.find_online_sub", comment: "Find Online Subtitles")
    static let chaptersPanel = NSLocalizedString("menu.chapters", comment: "Show Chapters Panel")
    static let hideChaptersPanel = NSLocalizedString("menu.hide_chapters", comment: "Hide Chapters Panel")
    static let playlistPanel = NSLocalizedString("menu.playlist", comment: "Show Playlist Panel")
    static let hidePlaylistPanel = NSLocalizedString("menu.hide_playlist", comment: "Hide Playlist Panel")
    static let videoPanel = NSLocalizedString("menu.video", comment: "Show Video Panel")
    static let hideVideoPanel = NSLocalizedString("menu.hide_video", comment: "Hide Video Panel")
    static let audioPanel = NSLocalizedString("menu.audio", comment: "Show Audio Panel")
    static let hideAudioPanel = NSLocalizedString("menu.hide_audio", comment: "Hide Audio Panel")
    static let subtitlesPanel = NSLocalizedString("menu.subtitles", comment: "Show Subtitles Panel")
    static let hideSubtitlesPanel = NSLocalizedString("menu.hide_subtitles", comment: "Hide Subtitles Panel")
    static let hideSubtitles = NSLocalizedString("menu.sub_hide", comment: "Hide Subtitles")
    static let showSubtitles = NSLocalizedString("menu.sub_show", comment: "Show Subtitles")
    static let hideSecondSubtitles = NSLocalizedString("menu.sub_second_hide", comment: "Hide Second Subtitles")
    static let showSecondSubtitles = NSLocalizedString("menu.sub_second_show", comment: "Show Second Subtitles")
  }
  struct SizeLimit {
    static let maxCachedVideoSizes: Int = 100000
  }
  struct Time {
    static let infinite = VideoTime(999, 0, 0)
  }
  struct TimeInterval {
    static let historyTableCompleteFileStatusReload = 600.0
    static let pastLaunchResponseTimeout = 1.0
  }
  struct FilterLabel {
    static let crop = "iina_crop"
    static let flip = "iina_flip"
    static let mirror = "iina_mirror"
    static let audioEq = "iina_aeq"
    static let delogo = "iina_delogo"
  }
  struct Sidebar {
    static let animationDuration: CGFloat = 0.2

    // How close the cursor has to be horizontally to the edge of the sidebar in order to trigger its resize:
    static let resizeActivationRadius: CGFloat = 10.0

    static let minPlaylistWidth: CGFloat = 240
    static let maxPlaylistWidth: CGFloat = 800
    static let settingsWidth: CGFloat = 360

    /// This needs to fit floating OSC + the margin around it
    static let minWidthBetweenInsideSidebars: CGFloat = 220

    /// Sidebar tab buttons
    static let defaultDownshift: CGFloat = 0
    static let defaultTabHeight: CGFloat = 48
    static let musicModeTabHeight: CGFloat = 32
    static let minTabHeight: CGFloat = 16
    static let maxTabHeight: CGFloat = 70
  }
  struct WindowedMode {
    static let minViewportSize = CGSize(width: 285, height: 120)
  }
  struct InteractiveMode {
    // Need enough space to display all the buttons and field at the bottom:
    static let minWindowWidth: CGFloat = 510
    static let outsideBottomBarHeight: CGFloat = 68
    // Show title bar only in windowed mode
    static let outsideTopBarHeight = PlayerWindowController.standardTitleBarHeight

    // Window's top bezel must be at least as large as the title bar so that dragging the top of crop doesn't drag the window too
    static let viewportMargins = MarginQuad(top: PlayerWindowController.standardTitleBarHeight, trailing: 24,
                                         bottom: PlayerWindowController.standardTitleBarHeight, leading: 24)
  }
  struct Distance {
    // TODO: change to % of screen width
    static let floatingControllerSnapToCenterThreshold = 20.0
    // The minimum distance that the user must drag before their click or tap gesture is interpreted as a drag gesture:
    static let windowControllerMinInitialDragThreshold: CGFloat = 4.0

    static let minOSCBarHeight: CGFloat = 24
    static let minThumbnailHeight: CGFloat = 24

    // TODO: move this outside Distance
    struct MusicMode {
      static let oscHeight: CGFloat = 72
      static let minWindowWidth: CGFloat = Constants.WindowedMode.minViewportSize.width
      static let defaultWindowWidth: CGFloat = minWindowWidth
      // Hide playlist if its height is too small to display at least 3 items:
      static let minPlaylistHeight: CGFloat = 138

      static let playSliderKnobHeight: CGFloat = 12
    }

    struct PWGeometry {
      static let minViewportHeight = PlayerWindowController.standardTitleBarHeight + 80
    }

    static let musicModePlaySliderKnobHeight: CGFloat = 12
    static let floatingOSCPlaySliderKnobHeight: CGFloat = 15
  }
  struct Color {
    static let defaultWindowBackgroundColor = CGColor.black
    static let interactiveModeBackground = NSColor.windowBackgroundColor.cgColor
  }
}

struct Unit {
  let singular: String
  let plural: String

  static let config = Unit(singular: "Config", plural: "Configs")
  static let keyBinding = Unit(singular: "Binding", plural: "Bindings")
}
struct UnitActionFormat {
  let none: String      // action only
  let single: String    // action, unit.singular
  let multiple: String  // action, count, unit.plural
  static let cut = UnitActionFormat(none: "Cut", single: "Cut %@", multiple: "Cut %d %@")
  static let copy = UnitActionFormat(none: "Copy", single: "Copy %@", multiple: "Copy %d %@")
  static let paste = UnitActionFormat(none: "Paste", single: "Paste %@", multiple: "Paste %d %@")
  static let pasteAbove = UnitActionFormat(none: "Paste Above", single: "Paste %@ Above", multiple: "Paste %d %@ Above")
  static let pasteBelow = UnitActionFormat(none: "Paste Below", single: "Paste %@ Below", multiple: "Paste %d %@ Below")
  static let delete = UnitActionFormat(none: "Delete", single: "Delete %@", multiple: "Delete %d %@")
  static let add = UnitActionFormat(none: "Add", single: "Add %@", multiple: "Add %d %@")
  static let insertNewAbove = UnitActionFormat(none: "Insert Above", single: "Insert New %@ Above", multiple: "Insert %d New %@ Above")
  static let insertNewBelow = UnitActionFormat(none: "Insert Below", single: "Insert New %@ Below", multiple: "Insert %d New %@ Below")
  static let move = UnitActionFormat(none: "Move", single: "Move %@", multiple: "Move %d %@")
  static let update = UnitActionFormat(none: "Update", single: "%@ Update", multiple: "%d %@ Updates")
  static let copyToFile = UnitActionFormat(none: "Copy to File", single: "Copy %@ to File", multiple: "Copy %d %@ to File")
}

extension Notification.Name {
  // User changed System Settings > Appearance > Accent Color. Must handle via DistributedNotificationCenter
  static let appleColorPreferencesChangedNotification = Notification.Name("AppleColorPreferencesChangedNotification")

  static let iinaPlayerWindowChanged = Notification.Name("IINAPlayerWindowChanged")
  static let iinaPlaylistChanged = Notification.Name("IINAPlaylistChanged")
  static let iinaTracklistChanged = Notification.Name("IINATracklistChanged")
  static let iinaVIDChanged = Notification.Name("iinaVIDChanged")
  static let iinaAIDChanged = Notification.Name("iinaAIDChanged")
  static let iinaSIDChanged = Notification.Name("iinaSIDChanged")
  static let iinaMediaTitleChanged = Notification.Name("IINAMediaTitleChanged")
  static let iinaVFChanged = Notification.Name("IINAVfChanged")
  static let iinaAFChanged = Notification.Name("IINAAfChanged")
  // An error occurred in the key bindings page and needs to be displayed:
  static let iinaKeyBindingErrorOccurred = Notification.Name("IINAKeyBindingErrorOccurred")
  // Supports auto-complete for key binding editing:
  static let iinaKeyBindingInputChanged = Notification.Name("IINAKeyBindingInputChanged")
  // Contains a TableUIChange which should be applied to the Input Conf table:
  // user input conf additions, subtractions, a rename, or the selection changed
  static let iinaPendingUIChangeForConfTable = Notification.Name("IINAPendingUIChangeForConfTable")
  // Contains a TableUIChange which should be applied to the Key Bindings table
  static let iinaPendingUIChangeForBindingTable = Notification.Name("IINAPendingUIChangeForBindingTable")
  // Requests that the search field above the Key Bindings table change its text to the contained string
  static let iinaKeyBindingSearchFieldShouldUpdate = Notification.Name("IINAKeyBindingSearchFieldShouldUpdate")
  // The AppInputConfig was rebuilt
  static let iinaAppInputConfigDidChange = Notification.Name("IINAAppInputConfigDidChange")
  static let iinaFileLoaded = Notification.Name("IINAFileLoaded")
  static let iinaHistoryUpdated = Notification.Name("IINAHistoryUpdated")
  static let iinaFileHistoryDidUpdate = Notification.Name("IINAFileHistoryDidUpdate")
  static let iinaLegacyFullScreen = Notification.Name("IINALegacyFullScreen")
  static let iinaPluginChanged = Notification.Name("IINAPluginChanged")
  static let iinaPlayerStopped = Notification.Name("iinaPlayerStopped")
  static let iinaPlayerShutdown = Notification.Name("iinaPlayerShutdown")
  static let iinaPlaySliderLoopKnobChanged = Notification.Name("iinaPlaySliderLoopKnobChanged")
  static let iinaLogoutCompleted = Notification.Name("iinaLoggedOutOfSubtitleProvider")
  static let windowIsReadyToShow = Notification.Name("windowIsReadyToShow")
  static let watchLaterDirDidChange = Notification.Name("watchLaterDirDidChange")
  static let watchLaterOptionsDidChange = Notification.Name("watchLaterOptionsDidChange")
  static let recentDocumentsDidChange = Notification.Name("recentDocumentsDidChange")
}
