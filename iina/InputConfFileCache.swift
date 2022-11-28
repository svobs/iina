//
//  InputConfFile.swift
//  iina
//
//  Created by Matt Svoboda on 2022.08.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Loading all the input conf files into memory shouldn't take too much time or space, and it will help avoid
// a bunch of tricky failure points for undo/redo, as well as unexpected behavior when the files are
// changed outside of IINA.
class InputConfFileCache {
  fileprivate var storage: [String: InputConfFile] = [:]

  // Returns cached file with the given name, or nil if no such entry present
  func getConfFile(confName: String) -> InputConfFile? {
    return storage[confName]
  }

  // First checks the in-memory cache for an entry for `confName`. If found, returns it. If not found in the cache,
  // loads file from disk with the given `filePath`, adds it to the in-memory cache, then returns it.
  // • Always returns an `InputConfFile` object, even on failure. If an error occurs it is handled and returns an object
  // with `failedToLoad` property set to true.
  // • This method must be used for loading all conf files, in order to ensure the in-memory cache is the single source
  // of truth. To update a conf file both on disk and in memory, first load an `InputConfFile` via this method and then
  // call its `overwriteFile()` method.
  // • NOTE: Updating the cache in response to events outside the running application instance is not currently supported.
  // When support is added, it must be done in a way that ties into the `UndoManager` (maybe create an undoable action
  // similar to how conf file imports are currently done),
  @discardableResult
  func getOrLoadConfFile(at filePath: String, isReadOnly: Bool = true, confName: String) -> InputConfFile {
    if let cachedConfFile = self.getConfFile(confName: confName) {
      Logger.log("Found \"\(confName)\" in memory cache", level: .verbose)
      return cachedConfFile
    }

    let confFile = loadFile(at: filePath, isReadOnly: isReadOnly, confName: confName)

    // read-through
    storage[confName] = confFile

    Logger.log("Updating memory cache entry for \"\(confName)\" (loadedOK: \(!confFile.failedToLoad))", level: .verbose)
    return confFile
  }

  func renameConfFile(oldConfName: String, newConfName: String) {
    Logger.log("Updating memory cache: moving \"\(oldConfName)\" -> \"\(newConfName)\"", level: .verbose)
    guard let inputConfFile = storage.removeValue(forKey: oldConfName) else {
      Logger.log("Cannot move conf file: no entry in cache for \"\(oldConfName)\" (this should never happen)", level: .error)
      sendErrorAlert(key: "error_finding_file", args: ["config"])
      return
    }
    storage[newConfName] = inputConfFile


    // TODO: put in async queue

    let oldFilePath = Utility.buildConfFilePath(for: oldConfName)
    let newFilePath = Utility.buildConfFilePath(for: newConfName)

    let oldExists = FileManager.default.fileExists(atPath: oldFilePath)
    let newExists = FileManager.default.fileExists(atPath: newFilePath)

    if !oldExists && newExists {
      Logger.log("Looks like file has already moved: \"\(oldFilePath)\"")
    } else {
      if !oldExists {
        Logger.log("Can't rename config: could not find file: \"\(oldFilePath)\"", level: .error)
        sendErrorAlert(key: "error_finding_file", args: ["config"])
      } else if newExists {
        Logger.log("Can't rename config: a file already exists at the destination: \"\(newFilePath)\"", level: .error)
        // TODO: more appropriate message
        sendErrorAlert(key: "config.cannot_create", args: ["config"])
      } else {
        // - Move file on disk
        do {
          Logger.log("Attempting to move InputConf file \"\(oldFilePath)\" to \"\(newFilePath)\"")
          try FileManager.default.moveItem(atPath: oldFilePath, toPath: newFilePath)
        } catch let error {
          Logger.log("Failed to rename file: \(error)", level: .error)
          // TODO: more appropriate message
          sendErrorAlert(key: "config.cannot_create", args: ["config"])
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
        sendErrorAlert(key: "error_finding_file", args: ["config"])
        continue
      }
      removedFileDict[confName] = inputConfFile
      let filePath = inputConfFile.filePath

      // TODO: put in async queue

      do {
        try FileManager.default.removeItem(atPath: filePath)
      } catch {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("File exists but could not be deleted: \"\(filePath)\"", level: .error)
          let fileName = URL(fileURLWithPath: filePath).lastPathComponent
          sendErrorAlert(key: "error_deleting_file", args: [fileName])
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
        sendErrorAlert(key: "config.cannot_create", args: [Utility.buildConfFilePath(for: confName)])
        continue
      }

      // TODO: put in async queue

      let filePath = inputConfFile.filePath
      do {
        if FileManager.default.fileExists(atPath: filePath) {
          Logger.log("Cannot restore deleted conf: a file aleady exists at \"\(filePath)\"", level: .error)
          // TODO: more appropriate message
          sendErrorAlert(key: "config.cannot_create", args: [filePath])
          continue
        }
        try saveFile(inputConfFile)
      } catch {
        Logger.log("Failed to restore deleted conf at path \"\(filePath)\": \(error)", level: .error)
        sendErrorAlert(key: "config.cannot_create", args: [filePath])
        continue
      }
    }
  }
}

// Internal file loader util func. Check returned object's `status` property; make sure `!= .failedToLoad`.
fileprivate func loadFile(at filePath: String, isReadOnly: Bool = true, confName: String? = nil) -> InputConfFile {
  let confNameOrDerived = confName ?? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent

  guard let reader = StreamReader(path: filePath) else {
    // on error
    Logger.log("Error loading key bindings from path: \"\(filePath)\"", level: .error)
    let fileName = URL(fileURLWithPath: filePath).lastPathComponent
    let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [fileName])
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    return InputConfFile(confName: confNameOrDerived, filePath: filePath, status: .failedToLoad, lines: [])
  }

  var lines: [String] = []
  while let rawLine: String = reader.nextLine() {
    guard lines.count < AppData.maxConfFileLinesAccepted else {
      Logger.log("Maximum number of lines (\(AppData.maxConfFileLinesAccepted)) exceeded: stopping load of file: \"\(filePath)\"")

      // TODO: more appropriate error msg
      let alertInfo = Utility.AlertInfo(key: "keybinding_config.error", args: [filePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return InputConfFile(confName: confNameOrDerived, filePath: filePath, status: .failedToLoad, lines: [])
    }
    lines.append(rawLine)
  }

  let status: InputConfFile.Status = isReadOnly ? .readOnly : .normal
  return InputConfFile(confName: confNameOrDerived, filePath: filePath, status: status, lines: lines)
}

// Internal file writer util func
fileprivate func saveFile(_ inputConfFile: InputConfFile) throws {
  switch inputConfFile.status {
    case .readOnly:
      Logger.log("Aborting saveFile() for \"\(inputConfFile.filePath)\": isReadOnly==true!", level: .error)
      throw IINAError.confFileIsReadOnly
    case .failedToLoad:
      Logger.log("Aborting saveFile() for \"\(inputConfFile.filePath)\": invalid operation: file never loaded properly!", level: .error)
      throw IINAError.confFileIsReadOnly
    case .normal:
      break
  }

  Logger.log("Updating memory cache entry for conf file: \"\(inputConfFile.confName)\"", level: .verbose)
  InputConfFile.cache.storage[inputConfFile.confName] = inputConfFile

  Logger.log("Saving conf file for \"\(inputConfFile.confName)\" to disk", level: .verbose)
  let newFileContent: String = inputConfFile.lines.joined(separator: "\n")
  try newFileContent.write(toFile: inputConfFile.filePath, atomically: true, encoding: .utf8)
}

// Utility function: show error popup to user
fileprivate func sendErrorAlert(key alertKey: String, args: [String]) {
  let alertInfo = Utility.AlertInfo(key: alertKey, args: args)
  NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
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

    // TODO: put in async queue

    do {
      try saveFile(updatedConfFile)
    } catch {
      Logger.log("Failed to overwrite conf file at \"\(self.filePath)\": \(error)", level: .error)
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
    return !loadFile(at: filePath).failedToLoad
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
