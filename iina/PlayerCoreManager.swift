//
//  PlayerCoreManager.swift
//  iina
//
//  Created by Matt Svoboda on 8/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class PlayerCoreManager {

  // MARK: - Static methods

  static var playerCores: [PlayerCore] {
    return PlayerCore.manager.getPlayerCores()
  }

  static var allPlayersHaveShutdown: Bool {
    for player in playerCores {
      if !player.isShutdown {
        return false
      }
    }
    return true
  }

  // Attempt to exactly restore play state & UI from last run of IINA (for given player)
  static func restoreFromPriorLaunch(playerID id: String) -> PlayerCore {
    Logger.log("Creating new PlayerCore & restoring saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")
    return PlayerCore.manager.createNewPlayerCore(withLabel: id, restore: true)
    /// see `start(restore: Bool)` below
  }

  // MARK: - Since instance

  private let lock = Lock()
  private var playerCoreCounter = 0

  private var playerCores: [PlayerCore] = []

  weak var lastActive: PlayerCore?

  // Returns a copy of the list of PlayerCores, to ensure concurrency
  func getPlayerCores() -> [PlayerCore] {
    var coreList: [PlayerCore]? = nil
    lock.withLock {
      coreList = playerCores
    }
    return coreList!
  }

  func _getOrCreateFirst() -> PlayerCore {
    var core: PlayerCore
    if playerCores.isEmpty {
      core = _createNewPlayerCore()
    } else {
      core = playerCores[0]
    }
    return core
  }

  func getOrCreateFirst() -> PlayerCore {
    var core: PlayerCore? = nil
    lock.withLock {
      core = _getOrCreateFirst()
    }
    core!.start()
    return core!
  }

  func getActiveOrCreateNew() -> PlayerCore {
    var core: PlayerCore? = nil
    lock.withLock {
      if playerCores.isEmpty {
        core = _createNewPlayerCore()
      } else {
        if Preference.bool(for: .alwaysOpenInNewWindow) {
          core = _getIdleOrCreateNew()
        } else {
          core = _getActive()
        }
      }
    }
    core!.start()
    return core!
  }

  private func _findIdlePlayerCore() -> PlayerCore? {
    return playerCores.first { $0.info.isIdle && !$0.info.isFileLoaded && $0.isStopped }
  }

  func getNonIdle() -> [PlayerCore] {
    var cores: [PlayerCore]? = nil
    lock.withLock {
      cores = playerCores.filter { !$0.info.isIdle }
    }
    return cores!
  }

  private func _getIdleOrCreateNew() -> PlayerCore {
    var core: PlayerCore
    if let idleCore = _findIdlePlayerCore() {
      Logger.log("Found idle player: #\(idleCore.label)")
      core = idleCore
    } else {
      core = _createNewPlayerCore()
    }
    return core
  }

  func getIdleOrCreateNew() -> PlayerCore {
    var core: PlayerCore!
    lock.withLock {
      core = _getIdleOrCreateNew()
    }
    core.start()
    return core
  }

  func getActive() -> PlayerCore {
    lock.withLock {
      return _getActive()
    }
  }

  func _getActive() -> PlayerCore {
    if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController {
      return wc.player
    } else {
      let core: PlayerCore! = _getOrCreateFirst()
      core.start()
      return core
    }
  }

  private func _playerExists(withLabel label: String) -> Bool {
    var exists = false
    exists = playerCores.first(where: { $0.label == label }) != nil
    return exists
  }

  private func _createNewPlayerCore(withLabel label: String? = nil) -> PlayerCore {
    Logger.log("Creating PlayerCore instance with ID \(label?.quoted ?? "(no label)")")
    let pc: PlayerCore
    if let label = label {
      if _playerExists(withLabel: label) {
        Logger.fatal("Cannot create new PlayerCore: a player already exists with label \(label.quoted)")
      }
      pc = PlayerCore(label)
    } else {
      let playerLabel = AppData.label(forPlayerCore: playerCoreCounter)
      while _playerExists(withLabel: playerLabel) {
        playerCoreCounter += 1
      }
      pc = PlayerCore(playerLabel)
      playerCoreCounter += 1
    }
    Logger.log("Successfully created PlayerCore \(pc.label)")

    playerCores.append(pc)
    return pc
  }

  func createNewPlayerCore(withLabel label: String? = nil, restore: Bool = false) -> PlayerCore {
    var pc: PlayerCore? = nil
    lock.withLock {
      pc = _createNewPlayerCore(withLabel: label)
    }
    pc!.start(restore: restore)
    return pc!
  }

  func removePlayer(withLabel label: String) {
    lock.withLock {
      playerCores.removeAll(where: { (player) in player.label == label })
    }
  }
}
