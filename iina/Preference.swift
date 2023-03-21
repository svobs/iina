//
//  Preference.swift
//  iina
//
//  Created by lhc on 17/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

protocol InitializingFromKey {

  static var defaultValue: Self { get }

  init?(key: Preference.Key)

}

struct Preference {

  // MARK: - Keys

  // consider using RawRepresentable, but also need to extend UserDefaults
  struct Key: RawRepresentable, Hashable {

    typealias RawValue = String

    var rawValue: RawValue

    var hashValue: Int {
      return rawValue.hashValue
    }

    init(_ string: String) { self.rawValue = string }

    init?(rawValue: RawValue) { self.rawValue = rawValue }

    func isValid() -> Bool {
      // It is valid if it exists and has a default
      return Preference.defaultPreference[self] != nil
    }

    static let receiveBetaUpdate = Key("receiveBetaUpdate")

    static let actionAfterLaunch = Key("actionAfterLaunch")
    static let alwaysOpenInNewWindow = Key("alwaysOpenInNewWindow")
    static let enableCmdN = Key("enableCmdN")

    /** Record recent files */
    static let recordPlaybackHistory = Key("recordPlaybackHistory")
    static let recordRecentFiles = Key("recordRecentFiles")
    static let trackAllFilesInRecentOpenMenu = Key("trackAllFilesInRecentOpenMenu")

    /** Material for OSC and title bar (Theme(int)) */
    static let themeMaterial = Key("themeMaterial")

    /** Soft volume (int, 0 - 100)*/
    static let softVolume = Key("softVolume")

    /** Pause st first (pause) (bool) */
    static let pauseWhenOpen = Key("pauseWhenOpen")

    /** Enter fill screen when open (bool) */
    static let fullScreenWhenOpen = Key("fullScreenWhenOpen")

    static let useLegacyFullScreen = Key("useLegacyFullScreen")
    static let legacyFullScreenAnimation = Key("legacyFullScreenAnimation")

    /** Black out other monitors while fullscreen (bool) */
    static let blackOutMonitor = Key("blackOutMonitor")

    static let actionWhenNoOpenedWindow = Key("actionWhenNoOpenedWindow")

    /** Keep player window open on end of file / playlist. (bool) */
    static let keepOpenOnFileEnd = Key("keepOpenOnFileEnd")

    /** Resume from last position */
    static let resumeLastPosition = Key("resumeLastPosition")

    static let alwaysFloatOnTop = Key("alwaysFloatOnTop")
    static let alwaysShowOnTopIcon = Key("alwaysShowOnTopIcon")

    static let pauseWhenMinimized = Key("pauseWhenMinimized")
    static let pauseWhenInactive = Key("pauseWhenInactive")
    static let playWhenEnteringFullScreen = Key("playWhenEnteringFullScreen")
    static let pauseWhenLeavingFullScreen = Key("pauseWhenLeavingFullScreen")
    static let pauseWhenGoesToSleep = Key("pauseWhenGoesToSleep")

    /** Show chapter pos in progress bar (bool) */
    static let showChapterPos = Key("showChapterPos")

    static let screenshotSaveToFile = Key("screenshotSaveToFile")
    static let screenshotCopyToClipboard = Key("screenshotCopyToClipboard")
    static let screenshotFolder = Key("screenShotFolder")
    static let screenshotIncludeSubtitle = Key("screenShotIncludeSubtitle")
    static let screenshotFormat = Key("screenShotFormat")
    static let screenshotTemplate = Key("screenShotTemplate")
    static let screenshotShowPreview = Key("screenshotShowPreview")

    static let playlistAutoAdd = Key("playlistAutoAdd")
    static let playlistAutoPlayNext = Key("playlistAutoPlayNext")
    static let playlistShowMetadata = Key("playlistShowMetadata")
    static let playlistShowMetadataInMusicMode = Key("playlistShowMetadataInMusicMode")

    // MARK: - Keys: UI

    /** Horizontal position of control bar. (float, 0 - 1) */
    static let controlBarPositionHorizontal = Key("controlBarPositionHorizontal")

    /** Horizontal position of control bar. In percentage from bottom. (float, 0 - 1) */
    static let controlBarPositionVertical = Key("controlBarPositionVertical")

    /** Whether control bar stick to center when dragging. (bool) */
    static let controlBarStickToCenter = Key("controlBarStickToCenter")

    /** Timeout for auto hiding control bar (float) */
    static let controlBarAutoHideTimeout = Key("controlBarAutoHideTimeout")

    static let controlBarToolbarButtons = Key("controlBarToolbarButtons")

    static let enableOSD = Key("enableOSD")
    static let osdAutoHideTimeout = Key("osdAutoHideTimeout")
    static let osdTextSize = Key("osdTextSize")

    static let usePhysicalResolution = Key("usePhysicalResolution")

    static let initialWindowSizePosition = Key("initialWindowSizePosition")
    static let resizeWindowTiming = Key("resizeWindowTiming")
    static let resizeWindowOption = Key("resizeWindowOption")

    static let titleBarStyle = Key("titleBarStyle")
    static let topPanelPlacementType = Key("topPanelPlacementType")
    static let bottomPanelPlacementType = Key("bottomPanelPlacementType")
    static let enableOSC = Key("enableOSC")
    static let oscPosition = Key("oscPosition")
    static let hideOverlaysWhenOutsideWindow = Key("hideOverlaysWhenOutsideWindow")

    // Sidebars:
    static let leftSidebarPlacementType = Key("leftSidebarPlacementType")
    static let rightSidebarPlacementType = Key("rightSidebarPlacementType")
    /// `Settings` tab group
    static let settingsTabGroupLocation = Key("settingsTabGroupLocation")
    /// `Playlist` tab group
    static let playlistTabGroupLocation = Key("playlistTabGroupLocation")
    static let playlistWidth = Key("playlistWidth")
    static let prefetchPlaylistVideoDuration = Key("prefetchPlaylistVideoDuration")

    static let enableThumbnailPreview = Key("enableThumbnailPreview")
    static let maxThumbnailPreviewCacheSize = Key("maxThumbnailPreviewCacheSize")
    static let enableThumbnailForRemoteFiles = Key("enableThumbnailForRemoteFiles")
    static let thumbnailLength = Key("thumbnailLength")

    static let autoSwitchToMusicMode = Key("autoSwitchToMusicMode")
    static let musicModeShowPlaylist = Key("musicModeShowPlaylist")
    static let musicModeShowAlbumArt = Key("musicModeShowAlbumArt")

    static let displayTimeAndBatteryInFullScreen = Key("displayTimeAndBatteryInFullScreen")

    static let windowBehaviorWhenPip = Key("windowBehaviorWhenPip")
    static let pauseWhenPip = Key("pauseWhenPip")
    static let togglePipByMinimizingWindow = Key("togglePipByMinimizingWindow")

    // MARK: - Keys: Codec

    static let videoThreads = Key("videoThreads")
    static let hardwareDecoder = Key("hardwareDecoder")
    static let forceDedicatedGPU = Key("forceDedicatedGPU")
    static let loadIccProfile = Key("loadIccProfile")
    static let enableHdrSupport = Key("enableHdrSupport")

    static let audioThreads = Key("audioThreads")
    static let audioLanguage = Key("audioLanguage")
    static let maxVolume = Key("maxVolume")

    static let spdifAC3 = Key("spdifAC3")
    static let spdifDTS = Key("spdifDTS")
    static let spdifDTSHD = Key("spdifDTSHD")

    static let audioDevice = Key("audioDevice")
    static let audioDeviceDesc = Key("audioDeviceDesc")

    static let enableInitialVolume = Key("enableInitialVolume")
    static let initialVolume = Key("initialVolume")

    // MARK: - Keys: Subtitle

    static let subAutoLoadIINA = Key("subAutoLoadIINA")
    static let subAutoLoadPriorityString = Key("subAutoLoadPriorityString")
    static let subAutoLoadSearchPath = Key("subAutoLoadSearchPath")
    static let ignoreAssStyles = Key("ignoreAssStyles")
    static let subOverrideLevel = Key("subOverrideLevel")
    static let subTextFont = Key("subTextFont")
    static let subTextSize = Key("subTextSize")
    static let subTextColorString = Key("subTextColorString")
    static let subBgColorString = Key("subBgColorString")
    static let subBold = Key("subBold")
    static let subItalic = Key("subItalic")
    static let subBlur = Key("subBlur")
    static let subSpacing = Key("subSpacing")
    static let subBorderSize = Key("subBorderSize")
    static let subBorderColorString = Key("subBorderColorString")
    static let subShadowSize = Key("subShadowSize")
    static let subShadowColorString = Key("subShadowColorString")
    static let subAlignX = Key("subAlignX")
    static let subAlignY = Key("subAlignY")
    static let subMarginX = Key("subMarginX")
    static let subMarginY = Key("subMarginY")
    static let subPos = Key("subPos")
    static let subLang = Key("subLang")
    static let legacyOnlineSubSource = Key("onlineSubSource")
    static let onlineSubProvider = Key("onlineSubProvider")
    static let displayInLetterBox = Key("displayInLetterBox")
    static let subScaleWithWindow = Key("subScaleWithWindow")
    static let openSubUsername = Key("openSubUsername")
    static let assrtToken = Key("assrtToken")
    static let defaultEncoding = Key("defaultEncoding")
    static let autoSearchOnlineSub = Key("autoSearchOnlineSub")
    static let autoSearchThreshold = Key("autoSearchThreshold")

    // MARK: - Keys: Network

    static let enableCache = Key("enableCache")
    static let defaultCacheSize = Key("defaultCacheSize")
    static let cacheBufferSize = Key("cacheBufferSize")
    static let secPrefech = Key("secPrefech")
    static let userAgent = Key("userAgent")
    static let transportRTSPThrough = Key("transportRTSPThrough")
    static let ytdlEnabled = Key("ytdlEnabled")
    static let ytdlSearchPath = Key("ytdlSearchPath")
    static let ytdlRawOptions = Key("ytdlRawOptions")
    static let httpProxy = Key("httpProxy")

    // MARK: - Keys: Control

    /** Seek option */
    static let useExactSeek = Key("useExactSeek")

    /** Seek speed for non-exact relative seek (Int, 1~5) */
    static let relativeSeekAmount = Key("relativeSeekAmount")

    static let arrowButtonAction = Key("arrowBtnAction")
    /** (1~4) */
    static let volumeScrollAmount = Key("volumeScrollAmount")
    static let verticalScrollAction = Key("verticalScrollAction")
    static let horizontalScrollAction = Key("horizontalScrollAction")

    static let videoViewAcceptsFirstMouse = Key("videoViewAcceptsFirstMouse")
    static let singleClickAction = Key("singleClickAction")
    static let doubleClickAction = Key("doubleClickAction")
    static let rightClickAction = Key("rightClickAction")
    static let middleClickAction = Key("middleClickAction")
    static let pinchAction = Key("pinchAction")
    static let rotateAction = Key("rotateAction")
    static let forceTouchAction = Key("forceTouchAction")

    static let showRemainingTime = Key("showRemainingTime")
    static let timeDisplayPrecision = Key("timeDisplayPrecision")
    static let touchbarShowRemainingTime = Key("touchbarShowRemainingTime")

    static let followGlobalSeekTypeWhenAdjustSlider = Key("followGlobalSeekTypeWhenAdjustSlider")

    static let enablePlaylistLoop = Key("enablePlaylistLoop")
    static let enableFileLoop = Key("enableFileLoop")

    // Input

    /** Whether catch media keys event (bool) */
    static let useMediaKeys = Key("useMediaKeys")
    static let useAppleRemote = Key("useAppleRemote")

    /** User created input config list (dic) */
    static let inputConfigs = Key("inputConfigs")

    /** Current input config name */
    static let currentInputConfigName = Key("currentInputConfigName")

    // MARK: - Keys: Advanced

    /** Enable advanced settings */
    static let enableAdvancedSettings = Key("enableAdvancedSettings")

    /** Use mpv's OSD (bool) */
    static let useMpvOsd = Key("useMpvOsd")

    /** Log to log folder (bool) */
    static let enableLogging = Key("enableLogging")
    static let logLevel = Key("logLevel")
    static let enablePiiMaskingInLog = Key("enablePiiMaskingInLog")

    /* [advanced] The highest mpv log level which IINA will include mpv log events in its own logfile (mutually exclusive of mpv's logfile) */
    static let iinaMpvLogLevel = Key("iinaMpvLogLevel")

    /* [debugging] If true, enables even more verbose logging so that input bindings computations can be more easily debugged. */
    static let logKeyBindingsRebuild = Key("logKeyBindingsRebuild")

    /* Saved value of checkbox in Key Bindings settings UI */
    static let displayKeyBindingRawValues = Key("displayKeyBindingRawValues")

    /* Behavior when setting the name of a new configuration to the Settings > Key Bindings > Configuration table, when duplicating an
     existing file or adding a new file.
     If true, a new row will be created in the table and a field editor will be displayed in it to allow setting the name (more modern).
     If false, a dialog will pop up containing a prompt and text field for entering the name.
     */
    static let useInlineEditorInsteadOfDialogForNewInputConf = Key("useInlineEditorInsteadOfDialogForNewInputConf")

    /* [advanced] If true, a selection of raw text can be pasted, or dragged from an input config file and dropped as a list of
     input bindings wherever input bindings can be dropped. */
    static let acceptRawTextAsKeyBindings = Key("acceptRawTextAsKeyBindings")

    /* If true, when the Key Bindings table is completely reloaded (as when changing the selected conf file), the changes will be animated using
     a calculated diff of the new contents compared to the old. If false, the contents of the table will be changed without an animation. */
    static let animateKeyBindingTableReloadAll = Key("animateKeyBindingTableReloadAll")

    /* [advanced] If true, enables spreadsheet-like navigation for quickly editing the Key Bindings table.
     When this pref is `true`:
     * When editing the last column of a row, pressing TAB accepts changes and opens a new editor in the first column of the next row.
     * When editing the first column of a row, pressing SHIFT+TAB accepts changes and opens a new editor in the last column of the previous row.
     * When editing any column, pressing RETURN will accept changes and open an editor in the same column of the next row.
     When this pref is `false` (default), each of the above actions will accept changes but will not open a new editor.
     */
    static let tableEditKeyNavContinuesBetweenRows = Key("tableEditKeyNavContinuesBetweenRows")

    /** unused */
    // static let resizeFrameBuffer = Key("resizeFrameBuffer")

    /** User defined options ([string, string]) */
    static let userOptions = Key("userOptions")

    /** User defined conf directory */
    static let useUserDefinedConfDir = Key("useUserDefinedConfDir")
    static let userDefinedConfDir = Key("userDefinedConfDir")

    static let watchProperties = Key("watchProperties")

    static let savedVideoFilters = Key("savedVideoFilters")
    static let savedAudioFilters = Key("savedAudioFilters")

    static let iinaLastPlayedFilePath = Key("iinaLastPlayedFilePath")
    static let iinaLastPlayedFilePosition = Key("iinaLastPlayedFilePosition")

    /** Alerts */
    static let suppressCannotPreventDisplaySleep = Key("suppressCannotPreventDisplaySleep")

    static let iinaEnablePluginSystem = Key("iinaEnablePluginSystem")

    // MARK: - Keys: Internal UI State

    /**
     When saving and restoring the UI state is enabled, we need to first check if other instances of IINA are running so that they
     don't overwrite each other's data. To do that, we can have each instance listen for changes to this counter and respond appropriately.
     */
    static let iinaLaunchCount = Key("iinaLaunchCount")
    static let iinaPing = Key("iinaPing")

    /** If true, saves the state of UI components as they change. This includes things like open windows &
     their sizes & positions, current scroll offsets, search entries, and more.
     NOTE: Do not use this directly. Use `Preference.UIState.isSaveEnabled()` so that runtime overrides can work. */
    fileprivate static let enableSaveUIState = Key("enableSaveUIState")
    /** If true, initializes the state of UI components to their previous values (presumably from the previous launch).
     Note that a saved state must exist for these components (see `enableSaveUIState`).
     NOTE: Do not use this directly. Use `Preference.UIState.isRestoreEnabled()` so that runtime overrides work. */
    fileprivate static let enableRestoreUIState = Key("enableRestoreUIState")

    // Comma-separated list of window names
    static let uiOpenWindowsBackToFrontList = Key("uiOpenWindowsBackToFrontList")

    // Index of currently selected tab in Navigator table
    static let uiPrefWindowNavTableSelectionIndex = Key("uiPrefWindowNavTableSelectionIndex")
    static let uiPrefDetailViewScrollOffsetY = Key("uiPrefDetailViewScrollOffsetY")
    // These must match the identifier of their respective CollapseView's button, except replacing the "Trigger" prefix with "uiCollapseView"
    // `true` == open;  `false` == folded
    static let uiCollapseViewMediaIsOpened = Key("uiCollapseViewMediaIsOpened")
    static let uiCollapseViewPauseResume = Key("uiCollapseViewPauseResume")
    static let uiCollapseViewSubAutoLoadAdvanced = Key("uiCollapseViewSubAutoLoadAdvanced")
    static let uiCollapseViewSubTextSubsAdvanced = Key("uiCollapseViewSubTextSubsAdvanced")
    static let uiPrefBindingsTableSearchString = Key("uiPrefBindingsTableSearchString")
    static let uiPrefBindingsTableScrollOffsetY = Key("uiPrefBindingsTableScrollOffsetY")

    static let uiHistoryTableGroupBy = Key("uiHistoryTableGroupBy")
    static let uiHistoryTableSearchType = Key("uiHistoryTableSearchType")
    static let uiHistoryTableSearchString = Key("uiHistoryTableSearchString")
    static let uiHistoryTableScrollOffsetY = Key("uiHistoryTableScrollOffsetY")

    // Map of modern keys to deprecated keys. Do not reference outside this file.
    fileprivate static let legacyColorKeys: [Key: Key] = [
      Preference.Key.subTextColorString: Key("subTextColor"),
      Preference.Key.subBgColorString: Key("subBgColor"),
      Preference.Key.subBorderColorString: Key("subBorderColor"),
      Preference.Key.subShadowColorString: Key("subShadowColor"),
    ]
  }

  // MARK: - Enums

  enum ActionAfterLaunch: Int, InitializingFromKey {
    case welcomeWindow = 0
    case openPanel
    case none
    case historyWindow

    static var defaultValue = ActionAfterLaunch.welcomeWindow

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ArrowButtonAction: Int, InitializingFromKey {
    case speed = 0
    case playlist = 1
    case seek = 2

    static var defaultValue = ArrowButtonAction.speed

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ActionWhenNoOpenedWindow: Int, InitializingFromKey {
    case welcomeWindow = 0
    case quit
    case none
    case historyWindow

    static var defaultValue = ActionWhenNoOpenedWindow.none

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum Theme: Int, InitializingFromKey {
    case dark = 0
    case ultraDark // 1
    case light // 2
    case mediumLight // 3
    case system // 4

    static var defaultValue = Theme.dark

    init?(key: Key) {
      let value = Preference.integer(for: key)
      if #available(macOS 10.14, *) {
        if value == 1 || value == 3 {
          return nil
        }
      } else {
        if value == 4 {
          return nil
        }
      }
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum SidebarLocation: Int, InitializingFromKey {
    case leftSidebar = 1
    case rightSidebar

    static var defaultValue = SidebarLocation.rightSidebar

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum PanelPlacementType: Int, InitializingFromKey {
    case insideVideo = 1
    case outsideVideo

    static var defaultValue = PanelPlacementType.insideVideo

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum TitleBarStyle: Int, InitializingFromKey {
    case none = 0
    case full
    case minimal

    static var defaultValue = TitleBarStyle.full

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum OSCPosition: Int, InitializingFromKey {
    case floating = 0
    case top
    case bottom

    static var defaultValue = OSCPosition.floating

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum SeekOption: Int, InitializingFromKey {
    case relative = 0
    case exact
    case auto

    static var defaultValue = SeekOption.relative

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum MouseClickAction: Int, InitializingFromKey {
    case none = 0
    case fullscreen
    case pause
    case hideOSC
    case togglePIP

    static var defaultValue = MouseClickAction.none

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ScrollAction: Int, InitializingFromKey {
    case volume = 0
    case seek
    case none
    case passToMpv

    static var defaultValue = ScrollAction.volume

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum PinchAction: Int, InitializingFromKey {
    case windowSize = 0
    case fullscreen
    case none

    static var defaultValue = PinchAction.windowSize

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum RotateAction: Int, InitializingFromKey {
    case none = 0
    case rotateVideoByQuarters

    static var defaultValue = RotateAction.rotateVideoByQuarters

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum IINAAutoLoadAction: Int, InitializingFromKey {
    case disabled = 0
    case mpvFuzzy
    case iina

    static var defaultValue = IINAAutoLoadAction.iina

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    func shouldLoadSubsContainingVideoName() -> Bool {
      return self != .disabled
    }

    func shouldLoadSubsMatchedByIINA() -> Bool {
      return self == .iina
    }
  }

  enum AutoLoadAction: Int, InitializingFromKey {
    case no = 0
    case exact
    case fuzzy
    case all

    static var defaultValue = AutoLoadAction.fuzzy

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var string: String {
      get {
        switch self {
        case .no: return "no"
        case .exact: return "exact"
        case .fuzzy: return "fuzzy"
        case .all: return "all"
        }
      }
    }
  }

  enum SubOverrideLevel: Int, InitializingFromKey {
    case yes = 0
    case force
    case strip

    static var defaultValue = SubOverrideLevel.yes

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var string: String {
      get {
        switch self {
        case .yes: return "yes"
        case .force : return "force"
        case .strip: return "strip"
        }
      }
    }
  }

  enum SubAlign: Int, InitializingFromKey {
    case top = 0  // left
    case center
    case bottom  // right

    static var defaultValue = SubAlign.center

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var stringForX: String {
      get {
        switch self {
        case .top: return "left"
        case .center: return "center"
        case .bottom: return "right"
        }
      }
    }

    var stringForY: String {
      get {
        switch self {
        case .top: return "top"
        case .center: return "center"
        case .bottom: return "bottom"
        }
      }
    }
  }

  enum RTSPTransportation: Int, InitializingFromKey {
    case lavf = 0
    case tcp
    case udp
    case http

    static var defaultValue = RTSPTransportation.tcp

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var string: String {
      get {
        switch self {
        case .lavf: return "lavf"
        case .tcp: return "tcp"
        case .udp: return "udp"
        case .http: return "http"
        }
      }
    }
  }

  enum ScreenshotFormat: Int, InitializingFromKey {
    case png = 0
    case jpg
    case jpeg
    case ppm
    case pgm
    case pgmyuv
    case tga

    static var defaultValue = ScreenshotFormat.png

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var string: String {
      get {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .jpeg: return "jpeg"
        case .ppm: return "ppm"
        case .pgm: return "pgm"
        case .pgmyuv: return "pgmyuv"
        case .tga: return "tga"
        }
      }
    }
  }

  enum HardwareDecoderOption: Int, InitializingFromKey {
    case disabled = 0
    case auto
    case autoCopy

    static var defaultValue = HardwareDecoderOption.auto

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var mpvString: String {
      switch self {
      case .disabled: return "no"
      case .auto: return "auto"
      case .autoCopy: return "auto-copy"
      }
    }

    var localizedDescription: String {
      return NSLocalizedString("hwdec." + mpvString, comment: mpvString)
    }
  }

  enum ResizeWindowTiming: Int, InitializingFromKey {
    case always = 0
    case onlyWhenOpen
    case never

    static var defaultValue = ResizeWindowTiming.onlyWhenOpen

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ResizeWindowOption: Int, InitializingFromKey {
    case fitScreen = 0
    case videoSize05
    case videoSize10
    case videoSize15
    case videoSize20

    static var defaultValue = ResizeWindowOption.videoSize10

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }

    var ratio: Double {
      switch self {
      case .fitScreen: return -1
      case .videoSize05: return 0.5
      case .videoSize10: return 1
      case .videoSize15: return 1.5
      case .videoSize20: return 2
      }
    }
  }

  enum WindowBehaviorWhenPip: Int, InitializingFromKey {
    case doNothing = 0
    case hide
    case minimize

    static var defaultValue = WindowBehaviorWhenPip.doNothing

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum ToolBarButton: Int {
    case settings = 0
    case playlist
    case pip
    case fullScreen
    case musicMode
    case subTrack

    func image() -> NSImage {
      switch self {
      case .settings: return NSImage(named: NSImage.actionTemplateName)!
      case .playlist: return #imageLiteral(resourceName: "playlist")
      case .pip: return #imageLiteral(resourceName: "pip")
      case .fullScreen: return #imageLiteral(resourceName: "fullscreen")
      case .musicMode: return #imageLiteral(resourceName: "toggle-album-art")
      case .subTrack: return #imageLiteral(resourceName: "sub-track")
      }
    }

    func description() -> String {
      let key: String
      switch self {
      case .settings: key = "settings"
      case .playlist: key = "playlist"
      case .pip: key = "pip"
      case .fullScreen: key = "full_screen"
      case .musicMode: key = "music_mode"
      case .subTrack: key = "sub_track"
      }
      return NSLocalizedString("osc_toolbar.\(key)", comment: key)
    }

    // Width will be identical
    static let frameHeight: CGFloat = 24

  }

  enum HistoryGroupBy: Int, InitializingFromKey {
    case lastPlayedDay = 0
    case parentFolder

    static var defaultValue = HistoryGroupBy.lastPlayedDay

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  enum HistorySearchType: Int, InitializingFromKey {
    case fullPath = 0
    case filename

    static var defaultValue = HistorySearchType.fullPath

    init?(key: Key) {
      self.init(rawValue: Preference.integer(for: key))
    }
  }

  // MARK: - Defaults

  static let defaultPreference: [Preference.Key: Any] = [
    .receiveBetaUpdate: false,
    .actionAfterLaunch: ActionAfterLaunch.welcomeWindow.rawValue,
    .alwaysOpenInNewWindow: true,
    .enableCmdN: false,
    .recordPlaybackHistory: true,
    .recordRecentFiles: true,
    .trackAllFilesInRecentOpenMenu: true,
    .controlBarPositionHorizontal: Float(0.5),
    .controlBarPositionVertical: Float(0.1),
    .controlBarStickToCenter: true,
    .controlBarAutoHideTimeout: Float(2.5),
    .controlBarToolbarButtons: [ToolBarButton.pip.rawValue, ToolBarButton.playlist.rawValue, ToolBarButton.settings.rawValue],
    .enableOSC: true,
    .titleBarStyle: TitleBarStyle.full.rawValue,
    .topPanelPlacementType: PanelPlacementType.insideVideo.rawValue,
    .bottomPanelPlacementType: PanelPlacementType.insideVideo.rawValue,
    .oscPosition: OSCPosition.floating.rawValue,
    .hideOverlaysWhenOutsideWindow: true,
    .playlistWidth: 270,
    .settingsTabGroupLocation: SidebarLocation.rightSidebar.rawValue,
    .playlistTabGroupLocation: SidebarLocation.rightSidebar.rawValue,
    .leftSidebarPlacementType: PanelPlacementType.insideVideo.rawValue,
    .rightSidebarPlacementType: PanelPlacementType.insideVideo.rawValue,
    .prefetchPlaylistVideoDuration: true,
    .themeMaterial: Theme.system.rawValue,
    .enableOSD: true,
    .osdAutoHideTimeout: Float(1),
    .osdTextSize: Float(20),
    .softVolume: 100,
    .arrowButtonAction: ArrowButtonAction.speed.rawValue,
    .pauseWhenOpen: false,
    .fullScreenWhenOpen: false,
    .useLegacyFullScreen: false,
    .legacyFullScreenAnimation: false,
    .showChapterPos: false,
    .resumeLastPosition: true,
    .useMediaKeys: true,
    .useAppleRemote: false,
    .alwaysFloatOnTop: false,
    .alwaysShowOnTopIcon: false,
    .blackOutMonitor: false,
    .pauseWhenMinimized: false,
    .pauseWhenInactive: false,
    .pauseWhenLeavingFullScreen: false,
    .pauseWhenGoesToSleep: true,
    .playWhenEnteringFullScreen: false,

    .playlistAutoAdd: true,
    .playlistAutoPlayNext: true,
    .playlistShowMetadata: true,
    .playlistShowMetadataInMusicMode: true,

    .usePhysicalResolution: true,
    .initialWindowSizePosition: "",
    .resizeWindowTiming: ResizeWindowTiming.onlyWhenOpen.rawValue,
    .resizeWindowOption: ResizeWindowOption.videoSize10.rawValue,
    .showRemainingTime: false,
    .timeDisplayPrecision: 0,
    .touchbarShowRemainingTime: true,
    .enableThumbnailPreview: true,
    .maxThumbnailPreviewCacheSize: 500,
    .enableThumbnailForRemoteFiles: false,
    .thumbnailLength: 240,
    .autoSwitchToMusicMode: true,
    .musicModeShowPlaylist: false,
    .musicModeShowAlbumArt: true,
    .displayTimeAndBatteryInFullScreen: false,

    .windowBehaviorWhenPip: WindowBehaviorWhenPip.doNothing.rawValue,
    .pauseWhenPip: false,
    .togglePipByMinimizingWindow: false,

    .videoThreads: 0,
    .hardwareDecoder: HardwareDecoderOption.auto.rawValue,
    .forceDedicatedGPU: false,
    .loadIccProfile: true,
    .enableHdrSupport: true,
    .audioThreads: 0,
    .audioLanguage: "",
    .maxVolume: 100,
    .spdifAC3: false,
    .spdifDTS: false,
    .spdifDTSHD: false,
    .audioDevice: "auto",
    .audioDeviceDesc: "Autoselect device",
    .enableInitialVolume: false,
    .initialVolume: 100,
    .enablePlaylistLoop: false,
    .enableFileLoop: false,

    .subAutoLoadIINA: IINAAutoLoadAction.iina.rawValue,
    .subAutoLoadPriorityString: "",
    .subAutoLoadSearchPath: "./*",
    .ignoreAssStyles: false,
    .subOverrideLevel: SubOverrideLevel.strip.rawValue,
    .subTextFont: "sans-serif",
    .subTextSize: Float(55),
    .subTextColorString: convertFromLegacyColor(.subTextColorString) ?? NSColor.white.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subBgColorString: convertFromLegacyColor(.subBgColorString) ?? NSColor.clear.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subBold: false,
    .subItalic: false,
    .subBlur: Float(0),
    .subSpacing: Float(0),
    .subBorderSize: Float(3),
    .subBorderColorString: convertFromLegacyColor(.subBorderColorString) ?? NSColor.black.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subShadowSize: Float(0),
    .subShadowColorString: convertFromLegacyColor(.subShadowColorString) ?? NSColor.clear.usingColorSpace(.deviceRGB)!.mpvColorString,
    .subAlignX: SubAlign.center.rawValue,
    .subAlignY: SubAlign.bottom.rawValue,
    .subMarginX: Float(25),
    .subMarginY: Float(22),
    .subPos: Float(100),
    .subLang: "",
    .legacyOnlineSubSource: 1, /* openSub */
    .onlineSubProvider: OnlineSubtitle.Providers.openSub.id,
    .displayInLetterBox: true,
    .subScaleWithWindow: true,
    .openSubUsername: "",
    .assrtToken: "",
    .defaultEncoding: "auto",
    .autoSearchOnlineSub: false,
    .autoSearchThreshold: 20,

    .enableCache: true,
    .defaultCacheSize: 153600,
    .cacheBufferSize: 153600,
    .secPrefech: 36000,
    .userAgent: "",
    .transportRTSPThrough: RTSPTransportation.tcp.rawValue,
    .ytdlEnabled: true,
    .ytdlSearchPath: "",
    .ytdlRawOptions: "",
    .httpProxy: "",

    .inputConfigs: [:],
    .currentInputConfigName: "IINA Default",

    .enableAdvancedSettings: false,
    .useMpvOsd: false,
    .enableLogging: false,
    .logLevel: Logger.Level.debug.rawValue,
    .enablePiiMaskingInLog: true,
    .iinaMpvLogLevel: MPVLogLevel.warn.rawValue,
    .logKeyBindingsRebuild: false,
    .displayKeyBindingRawValues: false,
    .useInlineEditorInsteadOfDialogForNewInputConf: true,
    .acceptRawTextAsKeyBindings: false,
    .animateKeyBindingTableReloadAll: true,
    .tableEditKeyNavContinuesBetweenRows: false,
    .iinaLaunchCount: 0,
    .iinaPing: "",
    .enableSaveUIState: true,
    .enableRestoreUIState: true,
    .uiOpenWindowsBackToFrontList: "",
    .uiPrefWindowNavTableSelectionIndex: 0,
    .uiPrefDetailViewScrollOffsetY: 0.0,
    .uiCollapseViewMediaIsOpened: true,
    .uiCollapseViewPauseResume: true,
    .uiCollapseViewSubAutoLoadAdvanced: false,
    .uiCollapseViewSubTextSubsAdvanced: false,
    .uiPrefBindingsTableSearchString: "",
    .uiPrefBindingsTableScrollOffsetY: 0,
    .uiHistoryTableGroupBy: HistoryGroupBy.lastPlayedDay.rawValue,
    .uiHistoryTableSearchType: HistorySearchType.fullPath.rawValue,
    .uiHistoryTableSearchString: "",
    .uiHistoryTableScrollOffsetY: 0,
    .userOptions: [],
    .useUserDefinedConfDir: false,
    .userDefinedConfDir: "~/.config/mpv/",
    .iinaEnablePluginSystem: false,

    .keepOpenOnFileEnd: true,
    .actionWhenNoOpenedWindow: ActionWhenNoOpenedWindow.none.rawValue,
    .useExactSeek: SeekOption.relative.rawValue,
    .followGlobalSeekTypeWhenAdjustSlider: false,
    .relativeSeekAmount: 3,
    .volumeScrollAmount: 3,
    .verticalScrollAction: ScrollAction.volume.rawValue,
    .horizontalScrollAction: ScrollAction.seek.rawValue,
    .videoViewAcceptsFirstMouse: false,
    .singleClickAction: MouseClickAction.hideOSC.rawValue,
    .doubleClickAction: MouseClickAction.fullscreen.rawValue,
    .rightClickAction: MouseClickAction.pause.rawValue,
    .middleClickAction: MouseClickAction.none.rawValue,
    .pinchAction: PinchAction.windowSize.rawValue,
    .rotateAction: RotateAction.defaultValue.rawValue,
    .forceTouchAction: MouseClickAction.none.rawValue,

    .screenshotSaveToFile: true,
    .screenshotCopyToClipboard: false,
    .screenshotFolder: "~/Pictures/Screenshots",
    .screenshotIncludeSubtitle: true,
    .screenshotFormat: ScreenshotFormat.png.rawValue,
    .screenshotTemplate: "%F-%n",
    .screenshotShowPreview: true,

    .watchProperties: [],
    .savedVideoFilters: [],
    .savedAudioFilters: [],

    .suppressCannotPreventDisplaySleep: false
  ]


  static private let ud = UserDefaults.standard

  static func object(for key: Key) -> Any? {
    return ud.object(forKey: key.rawValue)
  }

  static func array(for key: Key) -> [Any]? {
    return ud.array(forKey: key.rawValue)
  }

  static func url(for key: Key) -> URL? {
    return ud.url(forKey: key.rawValue)
  }

  static func dictionary(for key: Key) -> [String : Any]? {
    return ud.dictionary(forKey: key.rawValue)
  }

  static func string(for key: Key) -> String? {
    return ud.string(forKey: key.rawValue)
  }

  static func stringArray(for key: Key) -> [String]? {
    return ud.stringArray(forKey: key.rawValue)
  }

  static func data(for key: Key) -> Data? {
    return ud.data(forKey: key.rawValue)
  }

  static func bool(for key: Key) -> Bool {
    return ud.bool(forKey: key.rawValue)
  }

  static func integer(for key: Key) -> Int {
    return ud.integer(forKey: key.rawValue)
  }

  static func float(for key: Key) -> Float {
    return ud.float(forKey: key.rawValue)
  }

  static func double(for key: Key) -> Double {
    return ud.double(forKey: key.rawValue)
  }

  static func value(for key: Key) -> Any? {
    return ud.value(forKey: key.rawValue)
  }

  static func typedValue<T>(for key: Key) -> T {
    if let val = Preference.value(for: key) as? T {
      return val
    }
    fatalError("Unexpected type or missing default for preference key \(key.rawValue.quoted)")
  }

  static func typedDefault<T>(for key: Key) -> T {
    if let defaultVal = Preference.defaultPreference[key] as? T {
      return defaultVal
    }
    fatalError("Unexpected type or missing default for preference key \(key.rawValue.quoted)")
  }

  static func set(_ value: Bool, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Int, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: String, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Float, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Double, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: URL, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func set(_ value: Any?, for key: Key) {
    ud.set(value, forKey: key.rawValue)
  }

  static func `enum`<T: InitializingFromKey>(for key: Key) -> T {
    return T.init(key: key) ?? T.defaultValue
  }

  /**
   Older versions of IINA converted mpv color data into NSObject binary using the now-deprecated `NSUnarchiver` class.
   This method will transition to the new format which consists of the color components written to a `String`.
   To do this in a way which does not corrupt the values for older versions of IINA, we'll store the new format under a new `Preference.Key`,
   and leave the legacy pref entry as-is.

   This method will be executed on each of the affected prefs when IINA starts up. It will first check if there is already an entry for the new
   pref key. If it finds one, then it will assume that the migration has already occurred, and will just return that.
   Otherwise it will look for an entry for the legacy pref key. If it finds that, if will convert its value into the new format and store it under
   the new pref key, and then return that.

   This wil have the effect of automatically migrating older versions of IINA into the new format with no loss of data.
   However, it is worth noting that this migration will only happen once, and afterwards newer versions of IINA will not look at the old pref entry.
   And since older verions of IINA will only use the old pref entry, users who mix old and new versions of IINA may experience different values
   for these keys.
   */
  private static func convertFromLegacyColor(_ key: Key) -> String? {
    if let newValue = Preference.object(for: key) as? String {
      return newValue
    }
    guard let legacyKey = Preference.Key.legacyColorKeys[key] else { return nil }
    // Look for legacy pref:
    guard let data = ud.data(forKey: legacyKey.rawValue) else { return nil }
    guard let color = NSUnarchiver.unarchiveObject(with: data) as? NSColor else { return nil }
    guard let mpvColorString = color.usingColorSpace(.deviceRGB)?.mpvColorString else {
      Logger.log("Failed to convert color value from legacy key \(legacyKey.rawValue)", level: .error)
      return nil
    }
    // Store converted value in current format for future use:
    set(mpvColorString, for: key)
    Logger.log("Converted color value from legacyKey \(legacyKey.rawValue) and stored in key \(key.rawValue)")
    return mpvColorString
  }

  /** Notes on performance:
   Apple's `NSUserDefaults`, when getting & saving preference values, utilizes an in-memory cache which is very fast.
   And although it periodically saves "dirty" values to disk, and the interval between writes is unclear, this doesn't appear to cause
   a significant performance penalty, and certainly can't be much improved upon by IINA. Also, as playing video is by its nature very
   data-intensive, writes to the .plist should be trivial by comparison. */
  class UIState {
    /// This value, when set to true, disables state loading & saving for the remaining lifetime of this instance of IINA
    /// (overriding any user settings); calls to `set()` will not be saved for the next launch, and any new get() requests
    /// will return the default values.
    private static var disableForThisInstance = false

    static var isSaveEnabled: Bool {
      return !disableForThisInstance && Preference.bool(for: .enableSaveUIState)
    }

    static var isRestoreEnabled: Bool {
      return !disableForThisInstance && Preference.bool(for: .enableRestoreUIState)
    }

    static func disablePersistentStateUntilNextLaunch() {
      disableForThisInstance = true
    }

    // Convenience method. If restoring UI state is enabled, returns the saved value; otherwise returns the saved value.
    // Note: doesn't work for enums.
    static func get<T>(_ key: Key) -> T {
      if isRestoreEnabled {
        if let val = Preference.value(for: key) as? T {
          return val
        }
      }
      return Preference.typedDefault(for: key)
    }

    // Convenience method. If saving UI state is enabled, saves the given value. Otherwise does nothing.
    static func set<T: Equatable>(_ value: T, for key: Key) {
      guard isSaveEnabled else { return }
      if let existing = Preference.object(for: key) as? T, existing == value {
        return
      }
      Preference.set(value, for: key)
    }

    // Returns the autosave names of windows which have been saved in the set of open windows
    static func getSavedOpenWindowsBackToFront() -> [String] {
      guard isRestoreEnabled else {
        return []
      }

      let csv = Preference.string(for: Key.uiOpenWindowsBackToFrontList)?.trimmingCharacters(in: .whitespaces) ?? ""
      if csv.isEmpty {
        return []
      }
      return csv.components(separatedBy: ",").map{ $0.trimmingCharacters(in: .whitespaces)}
    }

    static func saveOpenWindowList(windowNamesBackToFront: [String]) {
      guard isSaveEnabled else { return }
      Logger.log("Saving open windows: \(windowNamesBackToFront)", level: .verbose)
      let csv = windowNamesBackToFront.map{ $0 }.joined(separator: ",")
      Preference.set(csv, for: Key.uiOpenWindowsBackToFrontList)
    }

    static func clearOpenWindowList() {
      saveOpenWindowList(windowNamesBackToFront: [])
    }
  }
}
