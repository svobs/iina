//
//  InputConfigFileHandler.swift
//  iina
//
//  Created by Matt Svoboda on 9/30/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Encapsulates load/save functionality for the *current* config file
class InputConfigFileHandler {
  private unowned var inputConfigTableStore: InputConfigTableStore {
    AppInputConfig.inputConfigTableStore
  }
  private var currentConfigFileData: InputConfigFile? = nil

  // Input Config File: Load
  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = inputConfigTableStore.currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(inputConfigTableStore.currentConfigName)\"); falling back to default config", level: .error)
      inputConfigTableStore.changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading bindings config from \"\(configFilePath)\"")
    guard let inputConfigFile = InputConfigFile.loadFile(at: configFilePath) else {
      inputConfigTableStore.changeCurrentConfigToDefault()
      return
    }
    self.currentConfigFileData = inputConfigFile

    let defaultSectionBindings = inputConfigFile.parseBindings()
    // By supplying .reloadAll request, we omit the animation and drop the selection. It doesn't make a lot of sense when changing files anyway.
    AppInputConfig.bindingTableStore.pushDefaultSectionChange(defaultSectionBindings, TableChangeByRowIndex(.reloadAll))
  }

  // Input Config File: Save
  public func saveBindingsToCurrentConfigFile(_ defaultSectionBindings: [KeyMapping]) -> [KeyMapping]? {
    guard let configFilePath = inputConfigTableStore.currentConfigFilePath else {
      let alertInfo = Utility.AlertInfo(key: "error_finding_file", args: ["config"])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }
    Logger.log("Saving \(defaultSectionBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentConfigData = self.currentConfigFileData else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      let canonicalPathCurrent = URL(fileURLWithPath: configFilePath).resolvingSymlinksInPath().path
      let canonicalPathLoaded = URL(fileURLWithPath: currentConfigData.filePath).resolvingSymlinksInPath().path
      guard canonicalPathCurrent == canonicalPathLoaded else {
        Logger.log("Failed to save bindings updates to file \"\(canonicalPathCurrent)\": its path does not match currently loaded config's (\"\(canonicalPathLoaded)\")", level: .error)
        let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [configFilePath])
        NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
        return nil
      }

      currentConfigData.replaceAllBindings(with: defaultSectionBindings)
      try currentConfigData.saveToDisk()
      return currentConfigData.parseBindings()  // gets updated line numbers

    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = Utility.AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }
}
