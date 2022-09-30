//
//  InputConfigFileHandler.swift
//  iina
//
//  Created by Matt Svoboda on 9/30/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class InputConfigFileHandler {
  private unowned var inputConfigTableStore: InputConfigTableStore {
    (NSApp.delegate as! AppDelegate).inputConfigTableStore
  }
  private var currentParsedConfigFile: InputConfigFileData? = nil

  // Input Config File: Load
  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = inputConfigTableStore.currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(inputConfigTableStore.currentConfigName)\"); falling back to default config", level: .error)
      inputConfigTableStore.changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading key bindings config from \"\(configFilePath)\"")
    guard let inputConfigFile = InputConfigFileData.loadFile(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings from config \"\(inputConfigTableStore.currentConfigName)\", at path: \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      inputConfigTableStore.changeCurrentConfigToDefault()
      return
    }
    self.currentParsedConfigFile = inputConfigFile

    let defaultSectionBindings = inputConfigFile.parseBindings()
    (NSApp.delegate as! AppDelegate).bindingTableStore.applyDefaultSectionUpdates(defaultSectionBindings, TableChangeByRowIndex(.reloadAll))
  }

  // Input Config File: Save
  public func saveBindingsToCurrentConfigFile(_ defaultSectionBindings: [KeyMapping]) -> [KeyMapping]? {
    guard let configFilePath = inputConfigTableStore.currentConfigFilePath else {
      let alertInfo = AlertInfo(key: "error_finding_file", args: ["config"])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
      return nil
    }
    Logger.log("Saving \(defaultSectionBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentParsedConfig = self.currentParsedConfigFile else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      currentParsedConfig.replaceAllBindings(with: defaultSectionBindings)
      try currentParsedConfig.writeFile(to: configFilePath)
      return currentParsedConfig.parseBindings()  // gets updated line numbers
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }
}
