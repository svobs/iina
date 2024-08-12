//
//  PlayerCoreManager.swift
//  iina
//
//  Created by Matt Svoboda on 8/4/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

class PlayerCoreManager {
  static var shared = PlayerCoreManager()

  private let lock = Lock()
  private var playerCoreCounter = 0

  private var _playerCores: [PlayerCore] = []
  private var _demoPlayer: PlayerCore? = nil

  /// Audio-only player. Needed for listing audio devices when no player windows are open.
  /// Should not be used for playing anything.
  var demoPlayer: PlayerCore? {
    var player: PlayerCore?
    lock.withLock {
      player = _demoPlayer
    }
    return player
  }

  weak var _lastActivePlayer: PlayerCore?
  var lastActivePlayer: PlayerCore? {
    get {
      return _lastActivePlayer ?? activePlayer
    }
    set {
      _lastActivePlayer = newValue
    }
  }

  // Returns a copy of the list of PlayerCores, to ensure concurrency
  var playerCores: [PlayerCore] {
    var coreList: [PlayerCore]? = nil
    lock.withLock {
      coreList = _playerCores
    }
    return coreList!
  }

  var allPlayersShutdown: Bool {
    return lock.withLock {
      let runningLabels = _playerCores.compactMap({ $0.isShutDown ? nil : $0.label})
      if !runningLabels.isEmpty {
        Logger.log.verbose("Players have not yet shut down: \(runningLabels)")
        return false
      }
      if let demoPlayer = _demoPlayer, !demoPlayer.isShutDown {
        demoPlayer.log.verbose("Demo player has not yet shut down")
        return false
      }
      return true
    }
  }

  // Attempt to exactly restore play state & UI from last run of IINA (for given player)
  func restoreFromPriorLaunch(playerID id: String) -> PlayerCore? {
    Logger.log("Creating new PlayerCore & restoring saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)")

    guard let savedState = Preference.UIState.getPlayerSaveState(forPlayerID: id) else {
      Logger.log("Cannot restore window: could not find saved state for \(WindowAutosaveName.playerWindow(id: id).string.quoted)", level: .error)
      return nil
    }

    let player = createNewPlayerCore(withLabel: id)
    savedState.restoreTo(player)
    return player
  }

  func _getOrCreateFirst() -> PlayerCore {
    var core: PlayerCore
    if _playerCores.isEmpty {
      core = _createNewPlayerCore()
    } else {
      core = _playerCores[0]
    }
    return core
  }

  func getOrCreateFirst() -> PlayerCore {
    var core: PlayerCore? = nil
    lock.withLock {
      core = _getOrCreateFirst()
    }
    return core!
  }

  func getActiveOrCreateNew() -> PlayerCore {
    var core: PlayerCore? = nil
    lock.withLock {
      if _playerCores.isEmpty {
        core = _createNewPlayerCore()
      } else {
        if Preference.bool(for: .alwaysOpenInNewWindow) {
          core = _getIdleOrCreateNew()
        } else {
          core = _activePlayer
        }
      }
    }
    return core!
  }

  /// `isAlternative` means to negate the current value of pref `.alwaysOpenInNewWindow`
  func getActiveOrNewForMenuAction(isAlternative: Bool) -> PlayerCore {
    let useNew = Preference.bool(for: .alwaysOpenInNewWindow) != isAlternative
    if !useNew, let activePlayer = activePlayer {
      return activePlayer
    }
    // If no active player, need to create new. Or if by pref
    return getIdleOrCreateNew()
  }

  private func _findIdlePlayerCore() -> PlayerCore? {
    var firstIdlePlayer: PlayerCore? = nil
    for p in _playerCores {
      let isPlayerIdle = p.info.isIdle && p.isStopped && !p.info.isFileLoaded
      Logger.log("Player-\(p.label): idle:\(p.info.isIdle.yn) stopped:\(p.isStopped.yn) fileLoaded:\(p.info.isFileLoaded.yn) → IDLE=\(isPlayerIdle.yesno)")
      if firstIdlePlayer == nil && isPlayerIdle {
        firstIdlePlayer = p
      }
    }
    return firstIdlePlayer
  }

  func getNonIdle() -> [PlayerCore] {
    var cores: [PlayerCore]? = nil
    lock.withLock {
      cores = _playerCores.filter { $0.status.isAtLeast(.started) && !$0.info.isIdle }
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
    return core
  }

  var activePlayer: PlayerCore? {
    lock.withLock {
      return _activePlayer
    }
  }

  var _activePlayer: PlayerCore? {
    if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController, wc.player.isActive {
      return wc.player
    } else {
      return nil
    }
  }

  func getOrCreateDemo() -> PlayerCore {
    var player: PlayerCore!
    lock.withLock {
      if let _demoPlayer {
        player = _demoPlayer
      } else {
        Logger.log("Creating demo player")
        player = PlayerCore("demo", audioOnly: true)
        player.start()
        _demoPlayer = player
      }
    }
    return player
  }

  private func _playerExists(withLabel label: String) -> Bool {
    var exists = false
    exists = _playerCores.first(where: { $0.label == label }) != nil
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

    _playerCores.append(pc)
    return pc
  }

  func createNewPlayerCore(withLabel label: String? = nil) -> PlayerCore {
    var pc: PlayerCore? = nil
    lock.withLock {
      pc = _createNewPlayerCore(withLabel: label)
    }
    return pc!
  }

  func removePlayer(withLabel label: String) {
    lock.withLock {
      _playerCores.removeAll(where: { (player) in player.label == label })
    }
  }
}
