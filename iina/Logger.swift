//
//  Logger.swift
//  iina
//
//  Created by Collider LI on 24/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

/// The IINA Logger.
///
/// Logging to a file is controlled by a preference in `Advanced` preferences and by default is disabled.
///
/// The logger takes a two phase approach to handling errors. During initialization of the logger any failure while creating the log directory,
/// creating the log file and opening the file for writing, is treated as a fatal error. The user will be shown an alert and when the user
/// dismisses the alert the application will terminate. Once the logger is successfully initialized errors involving the file are only printed to
/// the console to avoid disrupting playback.
/// - Important: The `createDirIfNotExist` method in `Utilities` **must not** be used by the logger. If an error occurs
///     that method will attempt to report it using the logger. If the logger is still being initialized this will result in a crash. For that reason
///     the logger uses its own similar method.
class Logger: NSObject {
  static var isTraceEnabled: Bool {
    return Logger.isEnabled(.trace)
  }
  static var isDebugEnabled: Bool {
    return Logger.isEnabled(.debug)
  }

  fileprivate static let sessionDirName: String = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let timeString  = formatter.string(from: Date())
    let launchID = AppDelegate.launchID
    return "\(timeString)_L\(launchID)"
  }()

  /// If true, strings which are indicated to contain personally identifiable information (PII) are replaced with a
  /// unique PII token (see `piiFormat` below) when they are logged to iina.log.
  static var enablePiiMasking: Bool {
    return Preference.bool(for: .enablePiiMaskingInLog)
  }

  /// Is ignored unless `Preference.enablePiiMaskingInLog` is true. If `writeUnmaskedPiiToFile` is true, each PII token and its value is written to
  /// a separate file which can be used to look up the PII tokens from the log; if it is false, then the values are not logged.
  static let writeUnmaskedPiiToFile = true

  // Try to prevent false positives duing search & replace by not allowing matches which are too short to
  // be meaningful
  static let minMatchLength = 3

  fileprivate static let piiFormat: String = "{pii%@}"
  fileprivate static let piiFileVersion: Int = 0
  fileprivate static let piiFirstLineFormat = "# IINA_PII \(piiFileVersion) \(sessionDirName)\n"

  class Log: NSObject {
    @objc dynamic let subsystem: String
    @objc dynamic let level: Int
    @objc dynamic let message: String
    @objc dynamic let date: String
    let logString: String

    init(subsystem: String, level: Int, message: String, date: String, logString: String) {
      self.subsystem = subsystem
      self.level = level
      self.message = message
      self.date = date
      self.logString = logString
    }

    override var description: String {
      return logString
    }
  }

  @Atomic static var logs: [Logger.Log] = []

  class Subsystem: RawRepresentable {
    let rawValue: String
    var added = false

    static let general = Subsystem(rawValue: "iina")
    static let input = Logger.Subsystem(rawValue: "input")

    var isTraceEnabled: Bool {
      return Logger.isTraceEnabled
    }

    required init(rawValue: String) {
      self.rawValue = rawValue
    }

    func trace(_ rawMessage: String) {
      guard isTraceEnabled else { return }
      /// trace is not a "real" level yet. Just use `verbose` for now
      Logger.log(rawMessage, level: .verbose, subsystem: self)
    }

    func verbose(_ rawMessage: String) {
      Logger.log(rawMessage, level: .verbose, subsystem: self)
    }

    func debug(_ rawMessage: String) {
      Logger.log(rawMessage, level: .debug, subsystem: self)
    }

    func warn(_ rawMessage: String) {
      Logger.log(rawMessage, level: .warning, subsystem: self)
    }

     func error(_ rawMessage: String) {
       Logger.log(rawMessage, level: .error, subsystem: self)
    }
  }

  @Atomic static var subsystems: [Subsystem] = [.general]

  static func makeSubsystem(_ rawValue: String) -> Subsystem {
    $subsystems.withLock() { subsystems in
      for (index, subsystem) in subsystems.enumerated() {
        // The first subsystem will always be "iina"
        if index == 0 { continue }
        if rawValue < subsystem.rawValue {
          let newSubsystem = Subsystem(rawValue: rawValue)
          subsystems.insert(newSubsystem, at: index)
          return newSubsystem
        } else if rawValue == subsystem.rawValue {
          return subsystem
        }
      }
      let newSubsystem = Subsystem(rawValue: rawValue)
      subsystems.append(newSubsystem)
      return newSubsystem
    }
  }

  enum Level: Int, Comparable, CustomStringConvertible {
    static func < (lhs: Level, rhs: Level) -> Bool {
      return lhs.rawValue < rhs.rawValue
    }

    static var preferred: Level = .error

    case trace = -1
    case verbose
    case debug
    case warning
    case error

    var description: String {
      switch self {
      case .trace: return "T"
      case .verbose: return "V"
      case .debug: return "D"
      case .warning: return "W"
      case .error: return "E"
      }
    }
  }

  fileprivate static var piiDict: [String: Int] = [:]

  static func getOrCreatePII(for privateString: String) -> String {
    guard enabled && enablePiiMasking && !privateString.isEmpty && privateString.count >= minMatchLength else {
      return privateString
    }

    var piiToken: String = ""
    lock.withLock {
      if let piiID = piiDict[privateString] {
        // Reoccurrence
        piiToken = formatPIIToken(piiID)
      } else {
        // New occurrence
        let piiID = piiDict.count
        piiDict[privateString] = piiID
        let escapedString = privateString.replacingOccurrences(of: "\n", with: "\\n")
        piiToken = formatPIIToken(piiID)

        if writeUnmaskedPiiToFile {
          if piiID == 0 {
            if let data = piiFirstLineFormat.data(using: .utf8) {
              writeToFile(piiFileHandle, data)
            } else {
              print(formatMessage("Could not encode pii header for writing!", .error, Logger.loggerSubsystem, false))
            }
          }
          let line = "\(piiToken)=\(escapedString)\n"
          if let data = line.data(using: .utf8) {
            writeToFile(piiFileHandle, data)
          } else {
            print(formatMessage("Could not encode pii token (\(piiToken)) for writing!", .error, Logger.loggerSubsystem, false))
          }
        }
      }
    }
    return piiToken
  }

  fileprivate static func formatPIIToken(_ piiID: Int) -> String {
    let paddedInt = piiID < 10 ? "0\(piiID)" : "\(piiID)"
    return String(format: piiFormat, paddedInt)
  }

  static private(set) var enabled: Bool = false

  static func updateEnablement() {
    let newValue = Preference.bool(for: .enableAdvancedSettings) && Preference.bool(for: .enableLogging)
    if enabled && !newValue {
      Logger.log("Logging disabled due to settings change")
      enabled = newValue
    } else if !enabled && newValue {
      enabled = newValue
      Logger.log("Logging is now enabled due to settings change")
    }

    Level.preferred = Level(rawValue: Preference.integer(for: .logLevel).clamped(to: Level.trace.rawValue...Level.error.rawValue))!
  }

  static func isEnabled(_ level: Logger.Level) -> Bool {
    #if !DEBUG
    guard enabled else { return false }
    #endif
    
    return Logger.Level.preferred <= level
  }

  static let libraryDirectory: URL = {
    let libraryURLs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
    guard let libraryURL = libraryURLs.first else {
      fatalDuringInit("Cannot get path to Logs directory: \(libraryURLs)")
    }
    return libraryURL
  }()

  static let logDirectory: URL = {
    // get path
    let logsUrl = libraryDirectory.appendingPathComponent("Logs", isDirectory: true)
    let bundleID = Bundle.main.bundleIdentifier!
    let appLogsUrl = logsUrl.appendingPathComponent(bundleID, isDirectory: true)

    // MUST NOT use the similar method in Utilities as that method uses Logger methods. Logger
    // methods must not ever be called while the logger is still initializing.
    createDirIfNotExist(url: logsUrl)

    let sessionDir = appLogsUrl.appendingPathComponent(sessionDirName, isDirectory: true)

    // MUST NOT use the similar method in Utilities. See above for reason.
    createDirIfNotExist(url: sessionDir)
    return sessionDir
  }()

  private static let logFile: URL = logDirectory.appendingPathComponent("iina.log")
  // File for personally identifiable information lookup
  private static let piiFile: URL = logDirectory.appendingPathComponent("pii.txt")

  private static let loggerSubsystem = Logger.makeSubsystem("logger")

  private static var logFileHandle: FileHandle? = {
    FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: nil)
    do {
      return try FileHandle(forWritingTo: logFile)
    } catch  {
      fatalDuringInit("Cannot open log file \(logFile.path) for writing: \(error.localizedDescription)")
    }
  }()

  private static var piiFileHandle: FileHandle? = {
    FileManager.default.createFile(atPath: piiFile.path, contents: nil, attributes: nil)
    do {
      return try FileHandle(forWritingTo: piiFile)
    } catch  {
      fatalDuringInit("Cannot open log file \(piiFile.path) for writing: \(error.localizedDescription)")
    }
  }()

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  // Must coordinate closing of the log file to avoid writing to a closed file handle.
  private static let lock = Lock()

  /// Closes the log file, if logging is enabled,
  /// - Important: Currently IINA does not coordinate threads during termination. This results in a race condition as to whether
  ///     a thread will attempt to log a message after the log file has been closed or not.  Previously this was triggering crashes due
  ///     to writing to a closed file handle. The logger now uses a lock to coordinate closing of the log file. If a log message is logged
  ///     after the log file is closed it will only be logged to the console.
  static func closeLogFiles() {
    guard enabled else { return }
    // Lock to avoid closing the log file while another thread is writing to it.
    lock.withLock {
      close(logFile, logFileHandle)
      /// Do not access `piiFileHandle` unless needed - will throw unnecessary error on app exit if log dir was deleted after launch
      /// (`logFileHandle` will not throw error becasue it was already opened?)
      if !piiDict.isEmpty {
        close(piiFile, piiFileHandle)
      }
    }
  }

  private static func close(_ fileURL: URL, _ fileHandle: FileHandle?) {
    guard let fileHandle = fileHandle else { return }
    do {
      // The deprecated method is used instead of the new close method that throws swift exceptions
      // because testing with the new write method found it failed to convert all objective-c
      // exceptions to swift exceptions.
      try ObjcUtils.catchException { fileHandle.closeFile() }
    } catch {
      // Unusual, but could happen if closing causes a buffer to be flushed to a full disk.
      print(formatMessage("Cannot close log file \(fileURL.path): \(error.localizedDescription)",
                          .error, Logger.loggerSubsystem, true))
    }
  }

  /// Creates a directory at the specified URL along with any nonexistent parent directories.
  ///
  /// If the directory cannot be created then this method will treat the failure as a fatal error. The user will be shown an alert and when
  /// the user dismisses the alert the application will terminate.
  /// - Parameter url: A file URL that specifies the directory to create.
  /// - Important: This method is designed to be usable during logger initialization. The similar method found in `Utilities`
  ///     **must not** be used. If an error occurs that method will attempt to report it using the logger. As the logger is still being
  ///     initialized this will result in a crash.
  private static func createDirIfNotExist(url: URL) {
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalDuringInit("Cannot create directory \(url): \(error.localizedDescription)")
    }
  }

  private static func formatMessage(_ message: String, _ level: Level, _ subsystem: Subsystem,
                                    _ appendNewlineAtTheEnd: Bool, _ date: Date = Date()) -> String {
    let time = dateFormatter.string(from: date)
    return "\(time) |\(subsystem.rawValue) \(level.description)| \(message)\(appendNewlineAtTheEnd ? "\n" : "")"
  }

  private static func writeToFile(_ fileHandle: FileHandle?, _ data: Data) {
    // The logger may be called after it has been closed.
    guard let fileHandle = fileHandle else { return }
    do {
      // The deprecated write method is used instead of the replacement method that throws swift
      // exceptions because testing the new method with macOS 12.5.1 showed that method failed to
      // turn all objective-c exceptions into swift exceptions. The exception thrown for writing
      // to a closed channel was not picked up by the catch block.
      try ObjcUtils.catchException { fileHandle.write(data) }
    } catch {
      print(formatMessage("Cannot write to log file: \(error.localizedDescription)", .error,
                          Logger.loggerSubsystem, false))
    }
  }

  static private func maskAnyPII(_ rawMessage: String) -> String {
    guard enablePiiMasking else { return rawMessage }

    var maskedMessage: String = rawMessage
    lock.withLock {
      for (piiString, piiID) in piiDict {
        maskedMessage = maskedMessage.replacingOccurrences(of: piiString, with: formatPIIToken(piiID))
      }
    }
    return maskedMessage
  }

  static func initLogging() {
    updateEnablement()

    // Mask library URL in subsequent logging
    _ = getOrCreatePII(for: libraryDirectory.path)
  }

  static func log(_ rawMessage: String, level: Level = .debug, subsystem: Subsystem = .general) {
    #if !DEBUG
    guard enabled else { return }
    #endif

    guard isEnabled(level) else { return }

    let message = maskAnyPII(rawMessage)

    let date = Date()
    let string = formatMessage(message, level, subsystem, true, date)
    let log = Log(subsystem: subsystem.rawValue, level: level.rawValue, message: message, date: dateFormatter.string(from: date), logString: string)
    $logs.withLock() { logs in
      if logs.isEmpty {
        DispatchQueue.main.async {
          Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { timer in
            AppDelegate.shared.logWindow.syncLogs()
          }
        }
      }
      logs.append(log)
    }

    print(string, terminator: "")

    #if DEBUG
    guard enabled else { return }
    #endif

    guard let data = string.data(using: .utf8) else {
      print(formatMessage("Cannot encode log string!", .error, Logger.loggerSubsystem, false))
      return
    }
    // Lock to prevent the log file from being closed by another thread while writing to it.
    lock.withLock() {
      writeToFile(logFileHandle, data)
    }
  }

  static func ensure(_ condition: @autoclosure () -> Bool, _ errorMessage: String = "Assertion failed in \(#line):\(#file)", _ cleanup: () -> Void = {}) {
    guard condition() else {
      log(errorMessage, level: .error)
      showAlertAndExit(errorMessage, cleanup)
    }
  }

  static func fatal(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    log(message, level: .error)
    log(Thread.callStackSymbols.joined(separator: "\n"))
    showAlertAndExit(message, cleanup)
  }

  /// Reports a fatal error during logger initialization and stops execution.
  ///
  /// This method will print the given error message to the console and then show an alert to the user. When the user dismisses the
  /// alert this method will terminate the process with an exit code of one.
  /// - Parameter message: The fatal error to report.
  /// - Important: This method differs from the method `fatal` in that it is designed to be safe to call during logger initialization
  ///     and therefore intentionally avoids attempting to log the fatal error message.
  private static func fatalDuringInit(_ message: String) -> Never {
    print(formatMessage(message, .error, Logger.loggerSubsystem, true))
    showAlertAndExit(message)
  }

  private static func showAlertAndExit(_ message: String, _ cleanup: () -> Void = {}) -> Never {
    // Set logAlert to false to avoid recursion
    Utility.showAlert("fatal_error", arguments: [message], logAlert: false)
    cleanup()
    exit(1)
  }
}
