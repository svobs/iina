//
//  ShutdownHandler.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-10.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Handles application shutdown
class ShutdownHandler {
  private(set) var isTerminating = false

  /// Whether the shutdown sequence timed out.
  private var shutdownTimedOut = false
  private var shutdownTimer: Timer? = nil

  private var observers: [NSObjectProtocol] = []

  func beginShutdown() -> Bool {
    guard !isTerminating else {
      Logger.log("Ignoring shutdown request - already started shutting down")
      return false
    }

    // Save UI state first:
    for playerWindowController in NSApplication.playerWindows {
      PlayerSaveState.saveSynchronously(playerWindowController.player)
    }
    UIState.shared.saveCurrentOpenWindowList()

    isTerminating = true

    HistoryController.shared.stop()

    // Normally termination happens fast enough that the user does not have time to initiate
    // additional actions, however to be sure shutdown further input from the user.
    Logger.log("Disabling all menus")
    AppDelegate.shared.menuController.disableAllMenus()
    // Remove custom menu items added by IINA to the dock menu. AppKit does not allow the dock
    // supplied items to be changed by an application so there is no danger of removing them.
    // The menu items are being removed because setting the isEnabled property to false had no
    // effect under macOS 12.6.
    removeAllMenuItems(AppDelegate.shared.dockMenu)
    // If supported and enabled disable all remote media commands. This also removes IINA from
    // the Now Playing widget.
    if RemoteCommandController.shared.useSystemMediaControl {
      RemoteCommandController.shared.disableAllCommands()
      RemoteCommandController.shared.useSystemMediaControl = false
    }

    if UIState.shared.isSaveEnabled {
      // unlock for new launch
      Logger.log("Updating lifecycle state of \(UIState.shared.currentLaunchName.quoted) to 'done' in prefs", level: .verbose)
      UserDefaults.standard.setValue(UIState.LaunchLifecycleState.done.rawValue, forKey: UIState.shared.currentLaunchName)
    }

    // The first priority was to shutdown any new input from the user. The second priority is to
    // send a logout request if logged into an online subtitles provider as that needs time to
    // complete.
    if OnlineSubtitle.loggedIn {
      // Force the logout request to timeout earlier than the overall termination timeout. This
      // request taking too long does not represent an error in the shutdown code, whereas the
      // intention of the overall termination timeout is to recover from some sort of hold up in the
      // shutdown sequence that should not occur.
      OnlineSubtitle.logout(timeout: Constants.TimeInterval.appTerminationTimeout - 1)
    }

    // Close all windows. When a player window is closed it will send a stop command to mpv to stop
    // playback and unload the file.
    Logger.log("Closing all windows")
    for window in NSApp.windows {
      window.close()
    }
    // To ensure termination completes and the user is not required to force quit IINA, impose an
    // arbitrary timeout that forces termination to complete. The expectation is that this timeout
    // is never triggered. If a timeout warning is logged during termination then that needs to be
    // investigated.
    let shutdownTimer = Timer(timeInterval: Constants.TimeInterval.appTerminationTimeout, repeats: false) { _ in
      self.shutdownDidTimeout()
    }
    self.shutdownTimer = shutdownTimer
    RunLoop.main.add(shutdownTimer, forMode: .common)

    // Establish an observer for a player core stopping.
    var observers: [NSObjectProtocol] = []

    observers.append(NotificationCenter.default.addObserver(forName: .iinaPlayerStopped, object: nil, queue: .main) { [self] note in
      guard !self.shutdownTimedOut else {
        // The player has stopped after IINA already timed out, gave up waiting for players to
        // shutdown, and told Cocoa to proceed with termination. AppKit will continue to process
        // queued tasks during application termination even after AppKit has called
        // applicationWillTerminate. So this observer can be called after IINA has told Cocoa to
        // proceed with termination. When the termination sequence times out IINA does not remove
        // observers as it may be useful for debugging purposes to know that a player stopped after
        // the timeout as that indicates the stopping was proceeding as opposed to being permanently
        // blocked. Log that this has occurred and take no further action as it is too late to
        // proceed with the normal termination sequence.  If the log file has already been closed
        // then the message will only be printed to the console.
        Logger.log("Player stopped after application termination timed out", level: .warning)
        return
      }
      guard let player = note.object as? PlayerCore else { return }
      player.log.verbose("Got iinaPlayerStopped. Requesting player shutdown")
      // Now that the player has stopped it is safe to instruct the player to terminate. IINA MUST
      // wait for the player to stop before instructing it to terminate because sending the quit
      // command to mpv while it is still asynchronously executing the stop command can result in a
      // watch later file that is missing information such as the playback position. See issue #3939
      // for details.
      player.shutdown()
    })

    // Establish an observer for a player core shutting down.
    observers.append(NotificationCenter.default.addObserver(forName: .iinaPlayerShutdown, object: nil, queue: .main) { [self] _ in
      guard !self.shutdownTimedOut else {
        // The player has shutdown after IINA already timed out, gave up waiting for players to
        // shutdown, and told Cocoa to proceed with termination. AppKit will continue to process
        // queued tasks during application termination even after AppKit has called
        // applicationWillTerminate. So this observer can be called after IINA has told Cocoa to
        // proceed with termination. When the termination sequence times out IINA does not remove
        // observers as it may be useful for debugging purposes to know that a player shutdown after
        // the timeout as that indicates shutdown was proceeding as opposed to being permanently
        // blocked. Log that this has occurred and take no further action as it is too late to
        // proceed with the normal termination sequence. If the log file has already been closed
        // then the message will only be printed to the console.
        Logger.log("Player shutdown completed after application termination timed out", level: .warning)
        return
      }
      proceedWithTermination()
    })

    // Establish an observer for logging out of the online subtitle provider.
    observers.append(NotificationCenter.default.addObserver(forName: .iinaLogoutCompleted, object: nil, queue: .main) { [self] _ in
      guard !self.shutdownTimedOut else {
        // The request to log out of the online subtitles provider has completed after IINA already
        // timed out, gave up waiting for players to shutdown, and told Cocoa to proceed with
        // termination. This should not occur as the logout request uses a timeout that is shorter
        // than the termination timeout to avoid this occurring. Therefore if this message is logged
        // something has gone wrong with the shutdown code.
        Logger.log.warn("Logout of online subtitles provider completed after application termination timed out")
        return
      }
      Logger.log("Got iinaLogoutCompleted notification", level: .verbose)
      proceedWithTermination()
    })

    // Establish an observer for saving of playback history finishing.
    observers.append(NotificationCenter.default.addObserver(forName: .iinaHistoryTasksFinished, object: nil, queue: .main) { [self] _ in
      guard !self.shutdownTimedOut else {
        // Saving of playback history finished after IINA already timed out, gave up waiting, and
        // told Cocoa to proceed with termination. This is a problem as it indicates playback
        // history might be being lost.
        Logger.log.warn("Saving of playback history finished after application termination timed out")
        return
      }
      // If there are still tasks outstanding then must continue waiting.
      guard HistoryController.shared.tasksOutstanding == 0 else { return }
      Logger.log("Saving of playback history finished")
      proceedWithTermination()
    })

    // Instruct any players that are already stopped to start shutting down.
    for player in PlayerManager.shared.playerCores {
      if !player.isShutDown {
        player.log.verbose("Requesting shutdown of player")
        player.shutdown()
      }
    }
    if let player = PlayerManager.shared.demoPlayer {
      if !player.isShutDown {
        player.log.verbose("Requesting shutdown of demo player")
        player.shutdown()
      }
    }

    return isReadyToTerminate()
  }

  @objc
  private func shutdownDidTimeout() {
    shutdownTimedOut = true
    if !PlayerManager.shared.allPlayersShutdown {
      Logger.log("Timed out waiting for players to stop and shut down", level: .warning)
      // For debugging list players that have not terminated.
      for player in PlayerManager.shared.playerCores {
        let label = player.label
        if !player.isShutDown {
          Logger.log("Player \(label) failed to shut down", level: .warning)
        }
      }
      // For debugging purposes we do not remove observers in case players stop or shutdown after
      // the timeout has fired as knowing that occurred maybe useful for debugging why the
      // termination sequence failed to complete on time.
      Logger.log("Not waiting for players to shut down; proceeding with application termination",
                 level: .warning)
    }
    if OnlineSubtitle.loggedIn {
      // The request to log out of the online subtitles provider has not completed. This should not
      // occur as the logout request uses a timeout that is shorter than the termination timeout to
      // avoid this occurring. Therefore if this message is logged something has gone wrong with the
      // shutdown code.
      Logger.log("Timed out waiting for log out of online subtitles provider to complete",
                 level: .warning)
    }
    Logger.log("Proceeding with application termination due to timeout", level: .warning)

    // Tell Cocoa to proceed with termination.
    NSApp.reply(toApplicationShouldTerminate: true)
  }

  private func isReadyToTerminate() -> Bool {
    // If any player has not shut down then continue waiting.
    let allPlayersShutdown = PlayerManager.shared.allPlayersShutdown
    let didSubtitleSvcLogOut = !OnlineSubtitle.loggedIn
    // If still still saving playback history then continue waiting.
    let tasksOutstanding = HistoryController.shared.tasksOutstanding

    // All players have shut down.
    Logger.log("AllPlayersShutdown=\(allPlayersShutdown.yesno) OnlineSubtitleLoggedOut=\(didSubtitleSvcLogOut.yesno) HistoryTasksOutstanding=\(tasksOutstanding)")
    guard allPlayersShutdown && didSubtitleSvcLogOut  && tasksOutstanding == 0 else { return false }
    // All players have shutdown. No longer logged into an online subtitles provider.

    Logger.log("Proceeding with application termination")
    // No longer need the timer that forces termination to proceed.
    shutdownTimer?.invalidate()
    // No longer need the observers for players stopping and shutting down, along with the
    // observer for logout requests completing and saving of playback history finishing.
    ObjcUtils.silenced { [self] in
      for observer in observers {
        NotificationCenter.default.removeObserver(observer)
      }
    }
    return true
  }

  /// Proceed with termination if all outstanding shutdown tasks have completed.
  ///
  /// This method is called when an observer receives a notification that a player has shutdown or an online subtitles provider logout
  /// request has completed. If there are no other termination tasks outstanding then this method will instruct AppKit to proceed with
  /// termination.
  private func proceedWithTermination() {
    guard isReadyToTerminate() else { return }
    // Tell AppKit to proceed with termination.
    NSApp.reply(toApplicationShouldTerminate: true)
  }

  /// Remove all menu items in the given menu and any submenus.
  ///
  /// This method recursively descends through the entire tree of menu items removing all items.
  /// - Parameter menu: Menu to remove items from
  private func removeAllMenuItems(_ menu: NSMenu) {
    for item in menu.items {
      if item.hasSubmenu {
        removeAllMenuItems(item.submenu!)
      }
      menu.removeItem(item)
    }
  }

}
