//
//  InputConfFile.swift
//  iina
//
//  Created by Matt Svoboda on 2022.08.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Loading all the conf files into memory shouldn't take too much time or space, and it will help avoid
// a bunch of tricky failure points for undo/redo.
class InputConfFileCache {
  fileprivate var storage: [String: InputConfFile] = [:]

  func getConfFile(confName: String) -> InputConfFile? {
    return storage[confName]
  }

  func getOrLoadConfFile(at filePath: String, isReadOnly: Bool = true, confName: String) -> InputConfFile {
    if let cachedConfFile = self.getConfFile(confName: confName) {
      Logger.log("Found \"\(confName)\" in memory cache", level: .verbose)
      return cachedConfFile
    }

    // read-through
    return loadConfFile(at: filePath, confName: confName)
  }

  // Loads file from disk, then adds/updates its cache entry, then returns it.
  @discardableResult
  func loadConfFile(at filePath: String, isReadOnly: Bool = true, confName: String) -> InputConfFile {
    let confFile = loadFile(at: filePath, isReadOnly: isReadOnly, confName: confName)

    Logger.log("Updating memory cache entry for \"\(confName)\" (loadedOK: \(!confFile.failedToLoad))", level: .verbose)
    storage[confName] = confFile
    return confFile
  }

  // Check returned object's `status` property; make sure `!= .failedToLoad`.
  // Don't use this from outside this file. Use `InputFileCache.loadConfFile()`
  fileprivate func loadFile(at path: String, isReadOnly: Bool = true, confName: String? = nil) -> InputConfFile {
    let confNameOrDerived = confName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

    guard let reader = StreamReader(path: path) else {
      // on error
      Logger.log("Error loading key bindings from path: \"\(path)\"", level: .error)
      let fileName = URL(fileURLWithPath: path).lastPathComponent
      let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return InputConfFile(confName: confNameOrDerived, filePath: path, status: .failedToLoad, lines: [])
    }

    var lines: [String] = []
    while let rawLine: String = reader.nextLine() {
      guard lines.count < AppData.maxConfFileLinesAccepted else {
        Logger.log("Maximum number of lines (\(AppData.maxConfFileLinesAccepted)) exceeded: stopping load of file: \"\(path)\"")

        // TODO: more appropriate error msg
        let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [path])
        NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
        return InputConfFile(confName: confNameOrDerived, filePath: path, status: .failedToLoad, lines: [])
      }
      lines.append(rawLine)
    }

    let status: InputConfFile.Status = isReadOnly ? .readOnly : .normal
    return InputConfFile(confName: confNameOrDerived, filePath: path, status: status, lines: lines)
  }

  func saveFile(_ inputConfFile: InputConfFile) throws {
    guard !inputConfFile.isReadOnly else {
      Logger.log("saveFile(): aborting - isReadOnly==true!", level: .error)
      throw IINAError.confFileIsReadOnly
    }

    Logger.log("Updating memory cache entry for conf file: \"\(inputConfFile.confName)\"", level: .verbose)
    InputConfFile.cache.storage[inputConfFile.confName] = inputConfFile

    Logger.log("Saving conf file to disk: \"\(inputConfFile.confName)\"", level: .verbose)
    let newFileContent: String = inputConfFile.lines.joined(separator: "\n")
    try newFileContent.write(toFile: inputConfFile.filePath, atomically: true, encoding: .utf8)
  }

  func renameConfFile(oldConfName: String, newConfName: String) {
    Logger.log("Updating memory cache: moving \"\(oldConfName)\" -> \"\(newConfName)\"", level: .verbose)
    guard let inputConfFile = storage.removeValue(forKey: oldConfName) else {
      Logger.log("Cannot move conf file: no entry in cache for \"\(oldConfName)\" (this should never happen)", level: .error)
      self.sendErrorAlert(key: "error_finding_file", args: ["config"])
      return
    }
    storage[newConfName] = inputConfFile

    let oldFilePath = Utility.buildConfFilePath(for: oldConfName)
    let newFilePath = Utility.buildConfFilePath(for: newConfName)

    let oldExists = FileManager.default.fileExists(atPath: oldFilePath)
    let newExists = FileManager.default.fileExists(atPath: newFilePath)

    if !oldExists && newExists {
      Logger.log("Looks like file has already moved: \"\(oldFilePath)\"")
    } else {
      if !oldExists {
        Logger.log("Can't rename config: could not find file: \"\(oldFilePath)\"", level: .error)
        self.sendErrorAlert(key: "error_finding_file", args: ["config"])
      } else if newExists {
        Logger.log("Can't rename config: a file already exists at the destination: \"\(newFilePath)\"", level: .error)
        // TODO: more appropriate message
        self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
      } else {
        // - Move file on disk
        do {
          Logger.log("Attempting to move InputConf file \"\(oldFilePath)\" to \"\(newFilePath)\"")
          try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
        } catch let error {
          Logger.log("Failed to rename file: \(error)", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: ["config"])
        }
      }
    }
  }

  // Performs removal of files on disk. Throws exception to indicate failure; otherwise success is assumed even if empty dict returned.
  // Returns a copy of each removed files' contents which must be stored for later undo
  func removeConfFiles(confNamesToRemove: Set<String>) -> [String:InputConfFile] {
    // Cache each file's contents in memory before removing it, for potential later use by undo
    var removedFileDict: [String:InputConfFile] = [:]

    for confName in confNamesToRemove {
      // Move file contents out of memory cache and into undo data:
      Logger.log("Removing from cache: \"\(confName)\"", level: .verbose)
      guard let inputConfFile = storage.removeValue(forKey: confName) else {
        Logger.log("Cannot remove conf file: no entry in cache for \"\(confName)\" (this should never happen)", level: .error)
        self.sendErrorAlert(key: "error_finding_file", args: ["config"])
        continue
      }
      removedFileDict[confName] = inputConfFile
      let filePath = inputConfFile.filePath

      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("File exists but could not be deleted: \"\(filePath)\"", level: .error)
          let fileName = URL(fileURLWithPath: filePath).lastPathComponent
          self.sendErrorAlert(key: "error_deleting_file", args: [fileName])
        } else {
          Logger.log("Looks like file was already removed: \"\(filePath)\"")
        }
      }
    }

    return removedFileDict
  }

  // Because the content of removed files was first stored in the undo data, restoring them will always succeed.
  // If disk operations fail, we can continue without immediate data loss - just report the error to user first.
  func restoreRemovedConfFiles(_ confNames: Set<String>, _ filesRemovedByLastAction: [String:InputConfFile]) {
    for (confName, inputConfFile) in filesRemovedByLastAction {
      Logger.log("Restoring file to cache: \(confName)", level: .verbose)
      storage[confName] = inputConfFile
    }

    for confName in confNames {
      guard let inputConfFile = filesRemovedByLastAction[confName] else {
        Logger.log("Cannot restore deleted conf \"\(confName)\": file content missing from undo data (this should never happen)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [Utility.buildConfFilePath(for: confName)])
        continue
      }

      let filePath = inputConfFile.filePath
      do {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("Cannot restore deleted file: file aleady exists: \(filePath)", level: .error)
          // TODO: more appropriate message
          self.sendErrorAlert(key: "config.cannot_create", args: [filePath])
          continue
        }
        try saveFile(inputConfFile)
      } catch {
        Logger.log("Failed to save undeleted file \"\(filePath)\": \(error)", level: .error)
        self.sendErrorAlert(key: "config.cannot_create", args: [filePath])
        continue
      }
    }
  }

  // Utility function: show error popup to user
  private func sendErrorAlert(key alertKey: String, args: [String]) {
    let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
  }
}

// Represents an input config file which has been loaded into memory.
struct InputConfFile {
  static let cache = InputConfFileCache()

  enum Status {
    case failedToLoad
    case readOnly
    case normal
  }
  let status: Status

  // The name of the conf in the Configuration UI.
  // This should almost always be just the filename without the extension.
  let confName: String

  // The path of the source file on disk
  let filePath: String

  // This should reflect what is on disk at all times
  fileprivate let lines: [String]

  fileprivate init(confName: String, filePath: String, status: Status, lines: [String]) {
    self.confName = confName
    self.filePath = filePath
    self.status = status
    self.lines = lines
  }

  var isReadOnly: Bool {
    return self.status == .readOnly
  }

  var failedToLoad: Bool {
    return self.status == .failedToLoad
  }

  var canonicalFilePath: String {
    URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
  }

  // Notifies the cache as well
  @discardableResult
  func overwriteFile(with newMappings: [KeyMapping]) -> InputConfFile {
    let rawLines = InputConfFile.toRawLines(from: newMappings)

    let updatedConfFile = InputConfFile(confName: self.confName, filePath: self.filePath, status: .normal, lines: rawLines)
    do {
      try InputConfFile.cache.saveFile(updatedConfFile)
    } catch {
      Logger.log("Failed to save conf file: \(error)", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [updatedConfFile.filePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return updatedConfFile
  }

  // This parses the file's lines one by one, skipping lines which are blank or only comments, If a line looks like a key binding,
  // a KeyMapping object is constructed for it, and each KeyMapping makes note of the line number from which it came. A list of the successfully
  // constructed KeyMappings is returned once the entire file has been parsed.
  func parseMappings() -> [KeyMapping] {
    return self.lines.compactMap({ InputConfFile.parseRawLine($0) })
  }

  static func tryLoadingFile(at filePath: String) -> Bool {
    return !InputConfFile.cache.loadFile(at: filePath).failedToLoad
  }

  // Returns a KeyMapping if successful, nil if line has no mapping or is not correct format
  static func parseRawLine(_ rawLine: String) -> KeyMapping? {
    var content = rawLine
    var isIINACommand = false
    if content.trimmingCharacters(in: .whitespaces).isEmpty {
      return nil
    } else if content.hasPrefix("#") {
      if content.hasPrefix(KeyMapping.IINA_PREFIX) {
        // extended syntax
        isIINACommand = true
        content = String(content[content.index(content.startIndex, offsetBy: KeyMapping.IINA_PREFIX.count)...])
      } else {
        // ignore comment line
        return nil
      }
    }
    var comment: String? = nil
    if let sharpIndex = content.firstIndex(of: "#") {
      comment = String(content[content.index(after: sharpIndex)...])
      content = String(content[...content.index(before: sharpIndex)])
    }
    // split
    let splitted = content.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t"})
    if splitted.count < 2 {
      return nil  // no command, wrong format
    }
    let key = String(splitted[0]).trimmingCharacters(in: .whitespaces)
    let action = String(splitted[1]).trimmingCharacters(in: .whitespaces)

    return KeyMapping(rawKey: key, rawAction: action, isIINACommand: isIINACommand, comment: comment)
  }

  private static func toRawLines(from mappings: [KeyMapping]) -> [String] {
    var newLines: [String] = []
    newLines.append("# Generated by IINA")
    newLines.append("")
    for mapping in mappings {
      let rawLine = mapping.confFileFormat
      if InputConfFile.parseRawLine(rawLine) == nil {
        Logger.log("While serializing key mappings: looks like an unfinished addition: \(mapping)", level: .verbose)
      } else {
        // valid binding
        newLines.append(rawLine)
      }
    }
    return newLines
  }
}
