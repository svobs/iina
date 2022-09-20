//
//  InputConfigFileWriter.swift
//  iina
//
//  Created by Matt Svoboda on 9/20/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class InputConfigFileWriter {
  private var currentParsedConfigFile: ParsedInputConfigFile? = nil

  unowned var inputConfigStore: InputConfigStore! = nil

  // Triggered any time `currentConfigName` is changed
  public func loadBindingsFromCurrentConfigFile() {
    guard let configFilePath = inputConfigStore.currentConfigFilePath else {
      Logger.log("Could not find file for current config (\"\(inputConfigStore.currentConfigName)\"); falling back to default config", level: .error)
      inputConfigStore.changeCurrentConfigToDefault()
      return
    }
    Logger.log("Loading key bindings config from \"\(configFilePath)\"")
    guard let inputConfigFile = ParsedInputConfigFile.loadFile(at: configFilePath) else {
      // on error
      Logger.log("Error loading key bindings from config \"\(inputConfigStore.currentConfigName)\", at path: \"\(configFilePath)\"", level: .error)
      let fileName = URL(fileURLWithPath: configFilePath).lastPathComponent
      let alertInfo = AlertInfo(key: "keybinding_config.error", args: [fileName])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))

      inputConfigStore.changeCurrentConfigToDefault()
      return
    }
    self.currentParsedConfigFile = inputConfigFile

    let defaultSectionBindings = inputConfigFile.parseBindings()
    ActiveBindingStore.get().applyDefaultSectionUpdates(defaultSectionBindings, TableUpdateByRowIndex(.reloadAll))
  }

  public func saveBindingsToCurrentConfigFile(_ defaultSectionBindings: [KeyMapping]) -> [KeyMapping]? {
    guard let configFilePath = requireCurrentFilePath() else {
      return nil
    }
    Logger.log("Saving \(defaultSectionBindings.count) bindings to current config file: \"\(configFilePath)\"", level: .verbose)
    do {
      guard let currentParsedConfig = currentParsedConfigFile else {
        Logger.log("Cannot save bindings updates to file: could not find file in memory!", level: .error)
        return nil
      }
      currentParsedConfig.replaceAllBindings(with: defaultSectionBindings)
      try currentParsedConfig.write(to: configFilePath)
      return currentParsedConfig.parseBindings()  // gets updated line numbers
    } catch {
      Logger.log("Failed to save bindings updates to file: \(error)", level: .error)
      let alertInfo = AlertInfo(key: "config.cannot_write", args: [configFilePath])
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    }
    return nil
  }

  private func requireCurrentFilePath() -> String? {
    if let filePath = inputConfigStore.currentConfigFilePath {
      return filePath
    }
    let alertInfo = AlertInfo(key: "error_finding_file", args: ["config"])
    NotificationCenter.default.post(Notification(name: .iinaKeyBindingErrorOccurred, object: alertInfo))
    return nil
  }

}
