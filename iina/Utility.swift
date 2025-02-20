//
//  Utility.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

typealias PK = Preference.Key

class Utility {

  static let supportedFileExt: [MPVTrack.TrackType: [String]] = [
    .video: ["mkv", "mp4", "avi", "m4v", "mov", "3gp", "ts", "mts", "m2ts", "wmv", "flv", "f4v", "asf", "webm", "rm", "rmvb", "qt", "dv", "mpg", "mpeg", "mxf", "vob", "gif", "ogv", "ogm"],
    .audio: ["mp3", "aac", "mka", "dts", "flac", "ogg", "oga", "mogg", "m4a", "ac3", "opus", "wav", "wv", "aiff", "aif", "ape", "tta", "tak"],
    .sub: ["utf", "utf8", "utf-8", "idx", "sub", "srt", "smi", "rt", "ssa", "aqt", "jss", "js", "ass", "mks", "vtt", "sup", "scc", "lrc"]
  ]
  static let playableFileExt = supportedFileExt[.video]! + supportedFileExt[.audio]!
  static let singleFilePlaylistExt = ["cue"]
  static let multipleFilePlaylistExt = ["m3u", "m3u8", "pls"]
  static let playlistFileExt = singleFilePlaylistExt + multipleFilePlaylistExt
  static let blacklistExt = supportedFileExt[.sub]! + multipleFilePlaylistExt
  static let lut3dExt = ["3dl", "cube", "dat", "m3d"]

  enum ValidationResult {
    case ok
    case valueIsEmpty
    case valueAlreadyExists
    case custom(String)
  }

  typealias InputValidator<T> = (T) -> ValidationResult

  // MARK: - Logs, alerts
  static func showAlert(_ key: String, comment: String? = nil, arguments: [CVarArg]? = nil, style: NSAlert.Style = .critical, sheetWindow: NSWindow? = nil, suppressionKey: PK? = nil, disableMenus: Bool = false, logAlert: Bool = true) {
    let alert = NSAlert()
    if let suppressionKey = suppressionKey {
      // This alert includes a suppression button that allows the user to suppress the alert.
      // Do not show the alert if it has been suppressed.
      guard !Preference.bool(for: suppressionKey) else { return }
      alert.showsSuppressionButton = true
    }

    switch style {
    case .critical:
      alert.messageText = NSLocalizedString("alert.title_error", comment: "Error")
    case .informational:
      alert.messageText = NSLocalizedString("alert.title_info", comment: "Information")
    case .warning:
      alert.messageText = NSLocalizedString("alert.title_warning", comment: "Warning")
    @unknown default:
      assertionFailure("Unknown \(type(of: style)) \(style)")
    }

    var format: String
    if let stringComment = comment {
      format = NSLocalizedString("alert." + key, comment: stringComment)
    } else {
      let alertString = NSLocalizedString("alert." + key, comment: key)
      if alertString.starts(with: "alert.") {
        // Kludge to allow printing of non-localized strings. Should be cleaned up at some point...
        format = key
      } else {
        format = alertString
      }
    }

    if let stringArguments = arguments {
      alert.informativeText = String(format: format, arguments: stringArguments)
    } else {
      alert.informativeText = String(format: format)
    }

    if logAlert {
      Logger.log("Showing alert: \"\(alert.informativeText)\"")
    }

    alert.alertStyle = style

    // If an alert occurs early during startup when the first player core is being created then
    // menus must be disabled while the alert is shown as opening certain menus will cause the menu
    // controller to attempt to access the player core while it is being initialized resulting in a
    // crash. See issue #5250.
    if disableMenus {
      AppDelegate.shared.menuController.disableAllMenus()
    }
    if let sheetWindow = sheetWindow {
      alert.beginSheetModal(for: sheetWindow)
    } else {
      alert.runModal()
    }
    if disableMenus {
      AppDelegate.shared.menuController.enableAllMenus()
    }

    // If the user asked for this alert to be suppressed set the associated preference.
    if let suppressionButton = alert.suppressionButton, suppressionButton.state == .on {
      Preference.set(true, for: suppressionKey!)
    }
  }

  // MARK: - Panels, Alerts

  /**
   Pop up an ask panel.
   - Parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
     - sheetWindow: (Optional) The window on which to display the sheet; if this value is nil then run modal.
     - callback: (Optional) Completion handler used by sheet modal.
   - Returns: Whether user dismissed the panel by clicking OK, discardable when using sheet.
   */
  @discardableResult
  static func quickAskPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, titleArgs: [CVarArg]? = nil, messageArgs: [CVarArg]? = nil, alertStyle: NSAlert.Style? = nil, useCustomButtons: Bool = false, sheetWindow: NSWindow? = nil, callback: ((NSApplication.ModalResponse) -> Void)? = nil) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    let titleFormat = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    let messageFormat = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    if let args = titleArgs {
      panel.messageText = String(format: titleFormat, arguments: args)
    } else {
      panel.messageText = titleFormat
    }
    if let args = messageArgs {
      panel.informativeText = String(format: messageFormat, arguments: args)
    } else {
      panel.informativeText = messageFormat
    }

    if let alertStyle {
      panel.alertStyle = alertStyle
    }

    let ok = NSLocalizedString(useCustomButtons ? "alert.\(key).ok" : "general.ok", comment: "OK")
    let cancel = NSLocalizedString(useCustomButtons ? "alert.\(key).cancel" : "general.cancel", comment: "Cancel")
    panel.addButton(withTitle: ok)
    panel.addButton(withTitle: cancel)

    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow, completionHandler: callback)
      return false
    } else {
      return panel.runModal() == .alertFirstButtonReturn
    }
  }

  /// `key` == localization key
  static func buildThreeButtonAskPanel(_ key: String, msgArgs: [String], alertStyle: NSAlert.Style? = nil) -> NSAlert {
    let panel = NSAlert()
    let titleKey = "alert.\(key).title"
    let messageKey = "alert.\(key).message"
    let titleFormat = NSLocalizedString(titleKey, comment: titleKey)
    let messageFormat = NSLocalizedString(messageKey, comment: messageKey)
    panel.messageText = String(format: titleFormat)
    panel.informativeText = String(format: messageFormat, arguments: msgArgs)
    if let alertStyle {
      panel.alertStyle = alertStyle
    }

    let okBtnTitle = NSLocalizedString("alert.\(key).ok", comment: "OK")
    panel.addButton(withTitle: okBtnTitle)
    let middleBtnTitle = NSLocalizedString("alert.\(key).middle", comment: "Middle")
    panel.addButton(withTitle: middleBtnTitle)
    let cancelBtnTitle = NSLocalizedString("alert.\(key).cancel", comment: "Cancel")
    panel.addButton(withTitle: cancelBtnTitle)

    return panel
  }

  /**
   Pop up an open panel.
   - Parameters:
     - title: Title of the panel.
     - chooseDir: Chooses directories or not; if false, then only choose files.
     - dir: (Optional) Base directory.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   */
  static func quickOpenPanel(title: String, chooseDir: Bool, dir: URL? = nil, sheetWindow: NSWindow? = nil, allowedFileTypes: [String]? = nil, callback: @escaping (URL) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = !chooseDir
    panel.canChooseDirectories = chooseDir
    panel.resolvesAliases = true
    panel.allowedFileTypes = allowedFileTypes
    panel.allowsMultipleSelection = false
    panel.level = .modalPanel
    if let dir = dir {
      panel.directoryURL = dir
    }
    let handler: (NSApplication.ModalResponse) -> Void = { result in
      if result == .OK, let url = panel.url {
        callback(url)
      }
    }
    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow, completionHandler: handler)
    } else {
      panel.begin(completionHandler: handler)
    }
  }

  /**
   Pop up an open panel.
   - Parameters
     - title: Title of the panel.
     - dir: (Optional) Base directory.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   */
  static func quickMultipleOpenPanel(title: String, dir: URL? = nil, canChooseDir: Bool, callback: @escaping ([URL]) -> Void) {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canCreateDirectories = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = canChooseDir
    panel.resolvesAliases = true
    panel.allowsMultipleSelection = true
    if let dir = dir {
      panel.directoryURL = dir
    }
    panel.begin() { result in
      if result == .OK {
        callback(panel.urls)
      }
    }
  }

  /// Pop up a Save As panel.
  static func quickSavePanel(title: String, filename: String? = nil,
                             allowedFileExtensions: [String]? = nil,
                             sheetWindow: NSWindow? = nil, callback: @escaping (URL) -> Void) {
    let panel = NSSavePanel()
    panel.title = title
    panel.canCreateDirectories = true
    panel.allowedFileTypes = allowedFileExtensions
    if filename != nil {
      panel.nameFieldStringValue = filename!
    }
    let handler: (NSApplication.ModalResponse) -> Void = { result in
      if result == .OK, let url = panel.url {
        callback(url)
      }
    }
    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow, completionHandler: handler)
    } else {
      panel.begin(completionHandler: handler)
    }
  }

  /**
   Pop up a prompt panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
     - sheetWindow: (Optional) The window on which to display the sheet.
     - callback: (Optional) Completion handler.
   - Returns: Whether user dismissed the panel by clicking OK. Only works when using `.modal` mode.
   */
  @discardableResult
  static func quickPromptPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil,
                               inputValue: String? = nil, validator: InputValidator<String>? = nil,
                               sheetWindow: NSWindow? = nil, callback: @escaping (String) -> Void) -> Bool {
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)

    // accessory view
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 16))
    input.translatesAutoresizingMaskIntoConstraints = false
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    if let inputValue = inputValue {
      input.stringValue = inputValue
    }
    let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 240, height: 20))
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.addArrangedSubview(input)

    // buttons
    let okButton = panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    let _ = panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input

    // validation
    var observer: NSObjectProtocol?
    if let validator = validator {
      let label = NSTextField(labelWithString: "label")
      label.textColor = .secondaryLabelColor
      label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      stackView.addArrangedSubview(label)
      stackView.frame = NSRect(x: 0, y: 0, width: 240, height: 42)

      let validateInput = {
        switch validator(input.stringValue) {
        case .ok:
          okButton.isEnabled = true
          label.stringValue = ""
        case .valueIsEmpty:
          okButton.isEnabled = false
          label.stringValue = NSLocalizedString("input.value_is_empty", comment: "Value is empty.")
        case .valueAlreadyExists:
          okButton.isEnabled = false
          label.stringValue = NSLocalizedString("input.already_exists", comment: "Value already exists.")
        case .custom(let message):
          label.stringValue = message
          okButton.isEnabled = false
        }
      }
      observer = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: input, queue: .main) { _ in
        validateInput()
      }
      validateInput()
    }

    stackView.translatesAutoresizingMaskIntoConstraints = true
    panel.accessoryView = stackView

    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow) { response in
        if response == .alertFirstButtonReturn {
          callback(input.stringValue)
        }
        if let observer = observer {
          NotificationCenter.default.removeObserver(observer)
        }
      }
    } else {
      if panel.runModal() == .alertFirstButtonReturn {
        callback(input.stringValue)
        if let observer = observer {
          NotificationCenter.default.removeObserver(observer)
        }
        return true
      }
    }
    return false
  }

  /**
   Pop up a username and password panel.
   - parameters:
     - key: A localization key. "alert.`key`.title" will be used as alert title, and "alert.`key`.message" will be the informative text.
     - titleComment: (Optional) Comment for title key.
     - messageComment: (Optional) Comment for message key.
   - Returns: Whether user dismissed the panel by clicking OK.
   */
  static func quickUsernamePasswordPanel(_ key: String, titleComment: String? = nil, messageComment: String? = nil, sheetWindow: NSWindow? = nil, callback: @escaping (String, String) -> Void) {
    let quickLabel: (String, Int) -> NSTextField = { title, yPos in
      let label = NSTextField(frame: NSRect(x: 0, y: yPos, width: 240, height: 14))
      label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
      label.stringValue = title
      label.drawsBackground = false
      label.isBezeled = false
      label.isSelectable = false
      label.isEditable = false
      return label
    }
    let panel = NSAlert()
    let titleKey = "alert." + key + ".title"
    let messageKey = "alert." + key + ".message"
    panel.messageText = NSLocalizedString(titleKey, comment: titleComment ?? titleKey)
    panel.informativeText = NSLocalizedString(messageKey, comment: messageComment ?? messageKey)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 82))
    view.addSubview(quickLabel(NSLocalizedString("general.username", comment: "Username") + ":", 68))
    let input = NSTextField(frame: NSRect(x: 0, y: 42, width: 240, height: 24))
    input.lineBreakMode = .byClipping
    input.usesSingleLineMode = true
    input.cell?.isScrollable = true
    view.addSubview(input)
    view.addSubview(quickLabel(NSLocalizedString("general.password", comment: "Password") + ":", 26))
    let pwField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    view.addSubview(pwField)
    input.nextKeyView = pwField
    panel.accessoryView = view
    panel.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
    panel.addButton(withTitle: NSLocalizedString("general.cancel", comment: "Cancel"))
    panel.window.initialFirstResponder = input
    if let sheetWindow = sheetWindow {
      panel.beginSheetModal(for: sheetWindow) { response in
        if response == .alertFirstButtonReturn {
          callback(input.stringValue, pwField.stringValue)
        }
      }
    } else {
      let response = panel.runModal()
      if response == .alertFirstButtonReturn {
        callback(input.stringValue, pwField.stringValue)
      }
    }
  }

  /**
   Pop up a font picker panel.
   - parameters:
     - callback: A closure accepting the font name.
   */
  static func quickFontPickerWindow(callback: @escaping (String?) -> Void) {
    let appDelegate = AppDelegate.shared
    appDelegate.fontPicker.finishedPicking = callback
    appDelegate.fontPicker.showWindow(self)
  }

  // MARK: - App functions

  static func createDirIfNotExist(url: URL) {
    let path = url.path
    // check exist
    if !FileManager.default.fileExists(atPath: path) {
      do {
        Logger.log.debug{"Creating directory: \(url.path.pii.quoted)"}
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
      } catch {
        Logger.fatal("Cannot create directory: \(url)")
      }
    }
  }

  static func createFileIfNotExist(url: URL) {
    let path = url.path
    // check exist
    if !FileManager.default.fileExists(atPath: path) {
      FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
    }
  }

  static private let allTypes: [MPVTrack.TrackType] = [.video, .audio, .sub]

  static func mediaType(forExtension ext: String) -> MPVTrack.TrackType? {
    return allTypes.first { supportedFileExt[$0]!.contains(ext.lowercased()) }
  }

  static func buildConfFilePath(for userConfName: String) -> String {
    return Utility.userInputConfDirURL.appendingPathComponent(userConfName).appendingPathExtension(Constants.InputConf.fileExtension).path
  }

  static let appSupportDirUrl: URL = {
    // get path
    let asPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    Logger.ensure(asPath.count >= 1, "Cannot get path to Application Support directory")
    let bundleID = Bundle.main.bundleIdentifier!
    let appAsUrl = asPath.first!.appendingPathComponent(bundleID)
    createDirIfNotExist(url: appAsUrl)
    return appAsUrl
  }()

  static let userInputConfDirURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.userInputConfFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let watchLaterURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.watchLaterFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    Logger.log("Watch Later directory: \(url.path.pii.quoted)")
    return url
  }()

  static let pluginsURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.pluginsFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let binariesURL: URL = {
    let url = Utility.appSupportDirUrl.appendingPathComponent(AppData.binariesFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let cacheURL: URL = {
    let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    Logger.ensure(cachesPath.count >= 1, "Cannot get path to Caches directory")
    let bundleID = Bundle.main.bundleIdentifier!
    let appCachesUrl = cachesPath.first!.appendingPathComponent(bundleID, isDirectory: true)
    return appCachesUrl
  }()

  static let thumbnailCacheURL: URL = {
    let appThumbnailCacheUrl = cacheURL.appendingPathComponent(AppData.thumbnailCacheFolder, isDirectory: true)
    createDirIfNotExist(url: appThumbnailCacheUrl)
    Logger.log.debug{"Using thumb cache dir: \(appThumbnailCacheUrl.path.pii.quoted)"}
    return appThumbnailCacheUrl
  }()

  static let screenshotCacheURL: URL = {
    let url = cacheURL.appendingPathComponent(AppData.screenshotCacheFolder, isDirectory: true)
    createDirIfNotExist(url: url)
    return url
  }()

  static let playbackHistoryURL: URL = {
    return Utility.appSupportDirUrl.appendingPathComponent(AppData.historyFile, isDirectory: false)
  }()

  static let tempDirURL: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

  static let exeDirURL: URL = URL(fileURLWithPath: Bundle.main.executablePath!).deletingLastPathComponent()


  // MARK: - Util functions

  static func setBoldTitle(for button: NSButton, _ active: Bool) {
    button.attributedTitle = NSAttributedString(string: button.title,
                                                attributes: FontAttributes(font: active ? .systemBold : .system, size: .system, align: .center).value)
  }

  static func toDisplaySubScale(fromRealSubScale realScale: Double) -> Double {
    return realScale >= 1 ? realScale : -1 / realScale
  }

  static func format(_ unit: Unit, _ unitCount: Int, _ format: UnitActionFormat) -> String {
    // 3 forms: if count==0, count==1, or count>1
    if unitCount == 0 {
      return format.none
    }
    if unitCount == 1 {  // single
      return String(format: format.single, unit.singular)
    }
    // multiple
    return String(format: format.multiple, unitCount, unit.plural)
  }

  static func quickConstraints(_ constraints: [String], _ views: [String: NSView]) {
    constraints.forEach { c in
      let cc = NSLayoutConstraint.constraints(withVisualFormat: c, options: [], metrics: nil, views: views)
      NSLayoutConstraint.activate(cc)
    }
  }

  /// See `mp_get_playback_resume_config_filename` in mpv/configfiles.c
  static func mpvWatchLaterMd5(_ filename: String) -> String {
    // mp_is_url
    // if(!Regex.mpvURL.matches(filename)) {
      // ignore_path_in_watch_later_config
    // }
    // handle dvd:// and bd://
    return filename.md5
  }

  /// Returns saved playback progress (in seconds) or `nil` if not found in `watch-later` data.
  static func playbackProgressFromWatchLater(_ mpvMd5: String) -> Double? {
    // No point in loading/showing this if it's not used
    guard Preference.bool(for: .resumeLastPosition) else { return nil }

    let fileURL = Utility.watchLaterURL.appendingPathComponent(mpvMd5)
    if let reader = StreamReader(path: fileURL.path),
      let firstLine = reader.nextLine(),
      firstLine.hasPrefix("start="),
      let progressString = firstLine.components(separatedBy: "=").last,
      let progress = Double(progressString) {
      return progress
    } else {
      return nil
    }
  }

  static func getLatestScreenshot(from path: String) -> URL? {
    let folder = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: [.creationDateKey],
      options: .skipsSubdirectoryDescendants),
          !contents.isEmpty else { return nil }
    return contents.filter { $0.creationDate != nil }.max { $0.creationDate! < $1.creationDate! }
  }

  /// Make sure the block is executed on the main thread. Be careful since it uses `sync`. Keep the block minimal.
  @discardableResult
  static func executeOnMainThread<T>(block: () -> T) -> T {
    if Thread.isMainThread {
      return block()
    } else {
      return DispatchQueue.main.sync {
        block()
      }
    }
  }

  static func icon(for url: URL?, optimizingForHeight height: CGFloat) -> NSImage {
    let baseIcon = icon(for: url)
    return baseIcon.getBestRepresentation(height: height)
  }

  static func icon(for url: URL?) -> NSImage {
    if #available(macOS 11.0, *) {
      if let url {
        let uttypeList = UTType.types(tag: url.pathExtension, tagClass: .filenameExtension, conformingTo: nil)
        for uttype in uttypeList {
          if uttype.identifier.starts(with: "io.iina.") {
            return NSWorkspace.shared.icon(for: uttype)
          }
        }
        if let firstUTType = uttypeList.first {
          return NSWorkspace.shared.icon(for: firstUTType)
        }
      }
      return NSWorkspace.shared.icon(for: .data)
    } else {
      return NSWorkspace.shared.icon(forFileType: url?.pathExtension ?? "")
    }
  }

  // MARK: - Util classes

  class Stopwatch: CustomStringConvertible {
    let startTime: CFAbsoluteTime
    init() {
      startTime = CFAbsoluteTimeGetCurrent()
    }

    var secElapsed: Double {
      return CFAbsoluteTimeGetCurrent() - startTime
    }

    var msElapsed: Double {
      return secElapsed * 1000
    }

    var secElapsedString: String {
      return "\(secElapsed.stringMaxFrac2)s"
    }

    var description: String {
      return msElapsed.stringMaxFrac2
    }
  }

  class AlertInfo {
    let key: String
    let comment: String?
    let args: [CVarArg]?
    let style: NSAlert.Style

    init(key: String, comment: String? = nil, args: [CVarArg]? = nil, _ style: NSAlert.Style = .critical) {
      self.key = key
      self.comment = comment
      self.args = args
      self.style = style
    }
  }

  class FontAttributes {
    struct AttributeType {
      enum Align {
        case left
        case center
        case right
      }
      enum Size {
        case system
        case small
        case mini
        case pt(Float)
      }
      enum Font {
        case system
        case systemBold
        case name(String)
      }
    }

    var align: AttributeType.Align
    var size: AttributeType.Size
    var font: AttributeType.Font

    init(font: AttributeType.Font, size: AttributeType.Size, align: AttributeType.Align) {
      self.font = font
      self.size = size
      self.align = align
    }

    var value : [NSAttributedString.Key : Any]? {
      get {
        let f: NSFont?
        let s: CGFloat
        let a = NSMutableParagraphStyle()
        switch self.size {
        case .system:
          s = NSFont.systemFontSize
        case .small:
          s = NSFont.systemFontSize(for: .small)
        case .mini:
          s = NSFont.systemFontSize(for: .mini)
        case .pt(let point):
          s = CGFloat(point)
        }
        switch self.font {
        case .system:
          f = NSFont.systemFont(ofSize: s)
        case .systemBold:
          f = NSFont.boldSystemFont(ofSize: s)
        case .name(let n):
          f = NSFont(name: n, size: s)
        }
        switch self.align {
        case .left:
          a.alignment = .left
        case .center:
          a.alignment = .center
        case .right:
          a.alignment = .right
        }
        if let f = f {
          NSFont.systemFont(ofSize: NSFont.systemFontSize)
          return [
            .font: f,
            .paragraphStyle: a
          ]
        } else {
          return nil
        }
      }
    }
  }


  // http://stackoverflow.com/questions/31701326/

  struct ShortCodeGenerator {

    private static let base62chars = [Character]("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let maxBase : UInt32 = 62

    static func getCode(withBase base: UInt32 = maxBase, length: Int) -> String {
      var code = ""
      for _ in 0..<length {
        let random = Int(arc4random_uniform(min(base, maxBase)))
        code.append(base62chars[random])
      }
      return code
    }
  }

  static func resolvePaths(_ paths: [String]) -> [String] {
    return paths.map { (try? URL(resolvingAliasFileAt: URL(fileURLWithPath: $0)))?.path ?? $0 }
  }

  static func resolveURLs(_ urls: [URL]) -> [URL] {
    return urls.map { (try? URL(resolvingAliasFileAt: $0)) ?? $0 }
  }
}

// http://stackoverflow.com/questions/33294620/
func rawPointerOf<T : AnyObject>(obj : T) -> UnsafeRawPointer {
  return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

func mutableRawPointerOf<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
  return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}


func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
  return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
}

func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
  return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
}

func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
  return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
}

enum LoopMode {
  case off
  case file
  case playlist

  func next() -> LoopMode {
    switch self {
    case .off:      return .file
    case .file:     return .playlist
    default:        return .off
    }
  }
}
