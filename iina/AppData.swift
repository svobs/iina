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
    return "\(UIState.shared.currentLaunchID)c\(playerCoreCounter)"
  }

  /** time interval to sync play pos & other UI */
  struct SyncTimerConfig {
    let interval: TimeInterval
    let tolerance: TimeInterval
  }
  static let syncTimerConfig = SyncTimerConfig(interval: 0.1, tolerance: 0.02)
//  static let syncTimerPreciseConfig = SyncTimerConfig(interval: 0.04, tolerance: 0.01)

  /** speed values when clicking left / right arrow button */

//  static let availableSpeedValues: [Double] = [-32, -16, -8, -4, -2, -1, 1, 2, 4, 8, 16, 32]
  // Stopgap for https://github.com/mpv-player/mpv/issues/4000
  static let availableSpeedValues: [Double] = [0.03125, 0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32]

  // Min/max speed for playback speed slider in Quick Settings
  static let minSpeed = 0.25
  static let maxSpeed = 16.0

  /// Lowest possible speed allowed by mpv (0.01x)
  static let mpvMinPlaybackSpeed = 0.01

  static let osdSeekSubSecPrecisionComparison: Double = 1000000

  static let mpvArgNone = "none"

  // Used internally as identifiers when communicating with mpv. Should not be displayed because they are not localized:
  static let noneCropIdentifier = "None"
  static let customCropIdentifier = "Custom"
  
  static let rotations: [Int] = [0, 90, 180, 270]
  static let scaleStep: CGFloat = 25

  /** Seek amount */
  static let seekAmountMap = [0, 0.05, 0.1, 0.25, 0.5]
  static let seekAmountMapMouse = [0, 0.5, 1, 2, 4]
  static let volumeMap = [0, 0.25, 0.5, 0.75, 1]

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
  static let crowdinMembersLink = "https://crowdin.com/project/iina"
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
  static let disableAnimationsHelpLink = "https://developer.apple.com/design/human-interface-guidelines/accessibility#Motion"
  static let gainAdjustmentHelpLink = "https://mpv.io/manual/stable/#options-replaygain"
  static let audioDriverHellpLink = "https://mpv.io/manual/stable/#audio-output-drivers-coreaudio"
}

typealias Str = String
typealias TimeInt = TimeInterval
struct Constants {
  struct BuildNumber {
    static let V1_0 = 1
    static let V1_1 = 2
    static let V1_2 = 3
    static let V1_2_1 = 4
    static let V1_2_2 = 5
    static let V1_3 = 6
  }
  struct String {
    static let degree = "°"
    static let dot = "●"
    static let blackRightPointingTriangle = "▶︎"
    static let blackLeftPointingTriangle = "◀"
    static let videoTimePlaceholder = "--:--:--"
    static let trackNone = NSLocalizedString("track.none", comment: "<None>")
    static let chapter = "Chapter"
    static let fullScreen = NSLocalizedString("menu.fullscreen", comment: "Full Screen")
    static let exitFullScreen = NSLocalizedString("menu.exit_fullscreen", comment: "Exit Full Screen")
    static let pause = NSLocalizedString("menu.pause", comment: "Pause")
    static let resume = NSLocalizedString("menu.resume", comment: "Resume")
    static let `default` = NSLocalizedString("quicksetting.item_default", comment: "Default")
    static let none = NSLocalizedString("quicksetting.item_none", comment: "None")
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

    // Pref keys
    static let iinaMpvCategoryFmt = "mpv-%@"
    static let iinaLaunchPrefix = "Launch-"
    static let openWindowListFmt = "\(iinaLaunchPrefix)%d-Windows"
  }
  /// All values are in seconds unless explicitly named differently
  struct TimeInterval {

    /// Minimum value to set a mpv loop point to.
    ///
    /// Setting a loop point to zero disables looping, so when loop points are being adjusted IINA must ensure the mpv property is not
    /// set to zero. However using `Double.leastNonzeroMagnitude` as the minimum value did not work because mpv truncates
    /// the value when storing the A-B loop points in the watch later file. As a result the state of the A-B loop feature is not properly
    /// restored when the media is played again. Using the following value as the minimum for loop points avoids this issue.
    static let minLoopPointTime = 0.000001

    /// Time in seconds to wait before regenerating thumbnails.
    /// Each character the user types into the thumbnailWidth text field triggers a new thumb regen request.
    /// This should help cut down on unnecessary requests.
    static let thumbnailRegenerationDelay = 0.5
    static let playerStateSaveDelay = 0.2
    /// Delay before auto-loading playlist from files in the opened file's directory
    static let autoLoadDelay = 1.0
    static let pastLaunchResponseTimeout = 1.0
    static let seekPreviewHideTimeout = 0.2
    /// How long since the last window finished restoring
    static let restoreWindowsTimeout = 5.0

    static let historyTableDelayBeforeLoadingMsgDisplay = 0.25

    /// For Force Touch.
    static let minimumPressDuration: TimeInt = 0.5

    /// If state save is enabled and video is playing, make sure player is saved every this number of secs
    static let playTimeSaveStateFrequency: TimeInt = 10.0
    static let asynchronousModeTimeout: TimeInt = 2.0

    /// For each scroll, how long the scroll wheel needs to be active for the scroll to be enabled.
    /// Set to a larger value to better avoid triggering accidental scrolls while making other trackpad gestures.
    static let minQualifyingScrollWheelDuration = 0.08

    /// When starting another smooth scroll after the last one ends, if less than this amount of time has passed since the last scroll ended,
    /// then `minQualifyingScrollWheelDuration` will be ignored and the new scroll session will start immediately. This increases responsiveness
    /// when the user is trying to scroll long distances by rapidly moving their fingers in a repeated motion.
    static let instantConsecutiveScrollStartWindow = 0.1

    static let windowDidChangeScreenParametersThrottlingDelay = 0.2
    static let windowDidChangeScreenThrottlingDelay = 0.2
    static let windowDidMoveProcessingDelay = 0.2

    /// May need adjustment for optimal results
    static let stepScrollSessionTimeout = 0.1

    /// This is a workaround for limitations of the `NSEvent` API and shouldn't need changing.
    ///
    /// If this amount of time passes from when we receive a `smoothScrollJustEnded` event but do not receive a
    /// `momentumScrollJustStarted` event, the scroll session should be considered ended.
    static let momentumScrollStartTimeout = 0.05

    static let musicModeChangeTrackTimeout = 1.0

    static let historyTableCompleteFileStatusReload = 600.0

    /// Longest time to wait for asynchronous shutdown tasks to finish before giving up on waiting and proceeding with termination.
    ///
    /// Ten seconds was chosen to provide plenty of time for termination and yet not be long enough that users start thinking they will
    /// need to force quit IINA. As termination may involve logging out of an online subtitles provider it can take a while to complete if
    /// the provider is slow to respond to the logout request.
    static let appTerminationTimeout = 10.0
  }
  struct FilterLabel {
    static let crop = "iina_crop"
    static let flip = "iina_flip"
    static let mirror = "iina_mirror"
    static let audioEq = "iina_aeq"
    static let delogo = "iina_delogo"
  }
  struct InputConf {
    // Immmutable default input configs.
    // TODO: combine into an OrderedDictionary when available
    static let defaultConfNamesSorted = ["IINA Default", "mpv Default", "VLC Default", "Movist Default", "Movist v2 Default"]
    static let defaults: [Str: Str] = [
      "IINA Default": resourcePath("iina-default-input"),
      "mpv Default": resourcePath("input"),
      "VLC Default": resourcePath("vlc-default-input"),
      "Movist Default": resourcePath("movist-default-input"),
      "Movist v2 Default": resourcePath("movist-v2-default-input"),
    ]

    static func resourcePath(_ resource: Str) -> Str {
      return Bundle.main.path(forResource: resource, ofType: fileExtension, inDirectory: confDirName)!
    }
    static let fileExtension  = "conf"
    static private let confDirName  = "config"
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

    /// Tab buttons downshift
    static let defaultDownshift: CGFloat = 0
    /// Tab buttons height
    static let defaultTabHeight: CGFloat = 48
    static let musicModeTabHeight: CGFloat = 32
    static let minTabHeight: CGFloat = 16
    static let maxTabHeight: CGFloat = 70
  }
  struct SizeLimit {
    static let maxCachedVideoSizes: Int = 100000
    static let maxWindowNamesInRestoreTimeoutAlert: Int = 8
    static let mpvOptionsTableMaxRowsPerOperation: Int = 1000
    static let inspectorWatchTableMaxRowsPerOperation: Int = 1000

    // Max allowed lines when reading a single input config file, or reading them from the Clipboard.
    static let maxConfFileLinesAccepted = 10000

    /// Absolute minimum allowed rendered video size. Does not include viewport or any other panels which are outside the video.
    static let minVideoSize = NSMakeSize(8, 8)
  }
  /// Based on mpv default
  struct DefaultVideoSize {
    static let rawWidth: Int = 640
    static let rawHeight: Int = 480
    static let aspectLabel = "4:3"
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
  struct AlbumArt {
    static let rawWidth: Int = 1600
    static let rawHeight: Int = 1600
  }
  struct Distance {
    // TODO: change to % of screen width
    static let floatingControllerSnapToCenterThreshold = 20.0
    // The minimum distance that the user must drag before their click or tap gesture is interpreted as a drag gesture:
    static let windowControllerMinInitialDragThreshold: CGFloat = 4.0

    static let floatingOSCPlaySliderKnobHeight: CGFloat = 15

    static let minOSCBarHeight: CGFloat = 24
    static let maxOSCBarHeight: CGFloat = 200

    // When opening multiple windows simultaneously & no other layout is applied, how much to offset one window from the one before
    static let multiWindowOpenOffsetIncrement = 20.0

    /// If OSC is shorter than this, never show the speed label
    static let minOSCBarHeightForSpeedLabel: CGFloat = 30

    /// Distance between traffic light buttons (their alignment rects, which does not include some extra padding around
    /// their images)
    static let titleBarIconHSpacing: CGFloat = 6

    /**
     `NSWindow` doesn't provide title bar height directly, but we can derive it by asking `NSWindow` for
     the dimensions of a prototypical window with titlebar, then subtracting the height of its `contentView`.
     Note that we can't use this trick to get it from our window instance directly, because our window has the
     `fullSizeContentView` style and so its `frameRect` does not include any extra space for its title bar.
     */
    static let standardTitleBarHeight: CGFloat = {
      // Probably doesn't matter what dimensions we pick for the dummy contentRect, but to be safe let's make them nonzero.
      let dummyContentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
      let dummyFrameRect = NSWindow.frameRect(forContentRect: dummyContentRect, styleMask: .titled)
      let titleBarHeight = dummyFrameRect.height - dummyContentRect.height
      return titleBarHeight
    }()

    static let reducedTitleBarHeight: CGFloat = {
      if let heightOfCloseButton = NSWindow.standardWindowButton(.closeButton, for: .titled)?.frame.height {
        // add 2 because button's bounds seems to be a bit larger than its visible size
        return standardTitleBarHeight - ((standardTitleBarHeight - heightOfCloseButton) / 2 + 2)
      }
      Logger.log("reducedTitleBarHeight may be incorrect (could not get close button)", level: .error)
      return standardTitleBarHeight
    }()

    struct Thumbnail {
      static let minHeight: CGFloat = 24
      static let extraOffsetX: CGFloat = 15
      static let extraOffsetY: CGFloat = 15
    }

    struct MusicMode {
      static let oscHeight: CGFloat = 72
      static let minWindowWidth: CGFloat = Constants.WindowedMode.minViewportSize.width
      static let defaultWindowWidth: CGFloat = minWindowWidth
      // Hide playlist if its height is too small to display at least 3 items:
      static let minPlaylistHeight: CGFloat = 138

      static let playSliderKnobHeight: CGFloat = 12
    }
  }  /// end `struct Distance`
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
  /// User changed System Settings > Appearance > Accent Color (`controlAccentColor`.
  /// Must handle via DistributedNotificationCenter.
  static let appleColorPreferencesChangedNotification = Notification.Name("AppleColorPreferencesChangedNotification")

  static let iinaPlayerWindowChanged = Notification.Name("IINAPlayerWindowChanged")
  static let iinaPlaylistChanged = Notification.Name("IINAPlaylistChanged")
  static let iinaTracklistChanged = Notification.Name("IINATracklistChanged")
  static let iinaVIDChanged = Notification.Name("iinaVIDChanged")
  static let iinaAIDChanged = Notification.Name("iinaAIDChanged")
  static let iinaSIDChanged = Notification.Name("iinaSIDChanged")
  static let iinaSSIDChanged = Notification.Name("iinaSSIDChanged")
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
  static let pendingUIChangeForInspectorTable = Notification.Name("pendingUIChangeForInspectorTable")
  static let pendingUIChangeForMpvOptionsTable = Notification.Name("pendingUIChangeForMpvOptionsTable")
  // Requests that the search field above the Key Bindings table change its text to the contained string
  static let iinaKeyBindingSearchFieldShouldUpdate = Notification.Name("IINAKeyBindingSearchFieldShouldUpdate")
  // The AppInputConfig was rebuilt
  static let iinaAppInputConfigDidChange = Notification.Name("IINAAppInputConfigDidChange")
  static let iinaFileLoaded = Notification.Name("IINAFileLoaded")
  static let iinaHistoryUpdated = Notification.Name("IINAHistoryUpdated")
  /// Similar to `iinaHistoryUpdated` but for a single file
  static let iinaFileHistoryDidUpdate = Notification.Name("IINAFileHistoryDidUpdate")
  static let iinaThumbnailCacheDidUpdate = Notification.Name("IINAThumbnailCacheDidUpdate")
  static let iinaLegacyFullScreen = Notification.Name("IINALegacyFullScreen")
  static let iinaPluginChanged = Notification.Name("IINAPluginChanged")
  static let iinaPlayerStopped = Notification.Name("iinaPlayerStopped")
  static let iinaPlayerShutdown = Notification.Name("iinaPlayerShutdown")
  static let iinaPlaySliderLoopKnobChanged = Notification.Name("iinaPlaySliderLoopKnobChanged")
  static let iinaLogoutCompleted = Notification.Name("iinaLoggedOutOfSubtitleProvider")
  static let windowIsReadyToShow = Notification.Name("windowIsReadyToShow")
  static let windowMustCancelShow = Notification.Name("windowMustCancelShow")
  static let watchLaterDirDidChange = Notification.Name("watchLaterDirDidChange")
  static let watchLaterOptionsDidChange = Notification.Name("watchLaterOptionsDidChange")
  static let recentDocumentsDidChange = Notification.Name("recentDocumentsDidChange")
  static let savedWindowStateDidChange = Notification.Name("savedWindowStateDidChange")
  static let iinaSecondSubVisibilityChanged = Notification.Name("iinaSecondSubVisibilityChanged")
  static let iinaSubVisibilityChanged = Notification.Name("iinaSubVisibilityChanged")
  static let iinaHistoryTasksFinished = Notification.Name("iinaHistoryTasksFinished")
}

struct Images {
  static func makeSymbol(named name: String, fallbackName: String? = nil, desc: String) -> NSImage {
    if #available(macOS 11.0, *) {
      if let sysImg = NSImage(systemSymbolName: name, accessibilityDescription: desc) {
        return sysImg
      }
    }
    let fallbackName = fallbackName ?? name
    Logger.log("Falling back to asset image \(fallbackName) instead of \(name)")
    return NSImage(named: name)!
  }

  // Use single instance of each for efficiency
  static let play = makeSymbol(named: "play.fill", fallbackName: "play", desc: "Play")
  static let pause = makeSymbol(named: "pause.fill", fallbackName: "pause", desc: "Pause")
  static let replay: NSImage = makeSymbol(named: "arrow.counterclockwise", desc: "Restart from beginning")
  static let stepForward10: NSImage = makeSymbol(named: "goforward.10", fallbackName: "speed", desc: "Step Forward 10s")
  static let stepBackward10: NSImage = makeSymbol(named: "gobackward.10", fallbackName: "speedl", desc: "Step Backward 10s")
  static let onTopOn = NSImage(imageLiteralResourceName: "ontop")
  static let onTopOff = NSImage(imageLiteralResourceName: "ontop_off")
  static let settingsFill = NSImage(imageLiteralResourceName: "gearshape.fill")
  static let sidebarLeading = NSImage(imageLiteralResourceName: "sidebar.leading")
  static let sidebarTrailing = NSImage(imageLiteralResourceName: "sidebar.trailing")

//  static let mute = makeSymbol(named: "speaker.slash.fill", fallbackName: "mute", desc: "Mute")
  static let mute = NSImage(named: "mute")!
  static let volume0 = makeSymbol(named: "speaker.fill", fallbackName: "volume-0", desc: "Volume None")
  static let volume1 = makeSymbol(named: "speaker.wave.1.fill", fallbackName: "volume-1", desc: "Volume 1 Wave")
  static let volume2 = makeSymbol(named: "speaker.wave.2.fill", fallbackName: "volume-2", desc: "Volume 2 Waves")
  static let volume3 = makeSymbol(named: "speaker.wave.3.fill", fallbackName: "volume", desc: "Volume Full")
}

struct DebugConfig {

  /// If `true`, add extra logging specific to input bindings build. Useful for debugging.
  /// Can toggle at run time by updating boolean pref key `logKeyBindingsRebuild`.
  static var logBindingsRebuild: Bool { Preference.bool(for: .logKeyBindingsRebuild) }

#if DEBUG
  /// Skip the Approve Restore prompt and retry restore if a failed previous restore was detected.
  static let alwaysApproveRestore = true
  static let enableScrollWheelDebug = false

  static let addHistoryWindowLoadingDelay = false
#endif
}

