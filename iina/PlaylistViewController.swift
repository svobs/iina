//
//  PlaylistViewController.swift
//  iina
//
//  Created by lhc on 17/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let PrefixMinLength = 7
fileprivate let FilenameMinLength = 12

fileprivate let MenuItemTagCut = 601
fileprivate let MenuItemTagCopy = 602
fileprivate let MenuItemTagPaste = 603
fileprivate let MenuItemTagDelete = 604

fileprivate let isPlayingTextBlendFraction: CGFloat = 0.3
fileprivate let isPlayingPrefixTextBlendFraction: CGFloat = 0.4

class PlaylistViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, SidebarTabGroupViewController, NSMenuItemValidation {

  override var nibName: NSNib.Name {
    return NSNib.Name("PlaylistViewController")
  }

  func getTopOfTabsConstraint() -> NSLayoutConstraint? {
    return self.buttonTopConstraint
  }
  func getHeightOfTabsConstraint() -> NSLayoutConstraint? {
    return self.tabHeightConstraint
  }

  weak var windowController: PlayerWindowController! {
    didSet {
      self.player = windowController.player
    }
  }

  weak var player: PlayerCore!

  /** Similar to the one in `QuickSettingViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  var playlistChangeObserver: NSObjectProtocol?

  /** Enum for tab switching */
  enum TabViewType: String {
    case playlist
    case chapters

    init?(name: String) {
      switch name {
      case "playlist":
        self = .playlist
      case "chapters":
        self = .chapters
      default:
        return nil
      }
    }
  }

  var currentTab: TabViewType = .playlist

  @IBOutlet weak var playlistTableView: NSTableView!
  @IBOutlet weak var chapterTableView: NSTableView!
  @IBOutlet weak var playlistBtn: NSButton!
  @IBOutlet weak var chaptersBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!
  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var tabHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var loopBtn: NSButton!
  @IBOutlet weak var shuffleBtn: NSButton!
  @IBOutlet weak var totalLengthLabel: NSTextField!
  @IBOutlet var subPopover: NSPopover!
  @IBOutlet var addFileMenu: NSMenu!
  @IBOutlet weak var addBtn: NSButton!
  @IBOutlet weak var removeBtn: NSButton!
  
  private var playlistTotalLengthIsReady = false
  private var playlistTotalLength: Double? = nil
  private var lastNowPlayingIndex: Int = -1

  private var distObservers: [NSObjectProtocol] = []  // For DistributedNotificationCenter
  internal var observedPrefKeys: [Preference.Key] = [
  ]

  fileprivate var isPlayingTextColor: NSColor = .textColor
  fileprivate var isPlayingPrefixTextColor: NSColor = .secondaryLabelColor
  fileprivate var cachedEffectiveAppearanceName: String? = nil

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case #keyPath(view.effectiveAppearance):
      if cachedEffectiveAppearanceName == view.effectiveAppearance.name.rawValue {
        return
      }
      cachedEffectiveAppearanceName = view.effectiveAppearance.name.rawValue
      // Need to use this closure for dark/light mode toggling to get picked up while running (not sure why...)
      view.effectiveAppearance.applyAppearanceFor {
        setCustomColors()
      }
      reloadData(playlist: true, chapters: true)
    default:
      return
    }
  }

  fileprivate func setCustomColors() {
    if #available(macOS 10.14, *) {
      isPlayingTextColor = NSColor.controlAccentColor.blended(withFraction: isPlayingTextBlendFraction, of: .textColor)!
      isPlayingPrefixTextColor = NSColor.controlAccentColor.blended(withFraction: isPlayingPrefixTextBlendFraction, of: .textColor)!
    }
  }

  private var downshift: CGFloat = 0
  private var tabHeight: CGFloat = 0

  func setVerticalConstraints(downshift: CGFloat, tabHeight: CGFloat) {
    if self.downshift != downshift || self.tabHeight != tabHeight {
      self.downshift = downshift
      self.tabHeight = tabHeight
      updateVerticalConstraints()
    }
  }

  private func updateVerticalConstraints() {
    // may not be available until after load
    self.buttonTopConstraint?.animateToConstant(downshift)
    self.tabHeightConstraint?.animateToConstant(tabHeight)
    view.layoutSubtreeIfNeeded()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    withAllTableViews { (view) in
      view.dataSource = self
    }
    playlistTableView.menu?.delegate = self

    [deleteBtn, loopBtn, shuffleBtn].forEach {
      $0?.image?.isTemplate = true
      $0?.alternateImage?.isTemplate = true
    }
    
    deleteBtn.toolTip = NSLocalizedString("mini_player.delete", comment: "delete")
    loopBtn.toolTip = NSLocalizedString("mini_player.loop", comment: "loop")
    shuffleBtn.toolTip = NSLocalizedString("mini_player.shuffle", comment: "shuffle")
    addBtn.toolTip = NSLocalizedString("mini_player.add", comment: "add")
    removeBtn.toolTip = NSLocalizedString("mini_player.remove", comment: "remove")

    hideTotalLength()

    // colors
    if #available(macOS 10.14, *) {
      withAllTableViews { $0.backgroundColor = NSColor(named: .sidebarTableBackground)! }
    }

    // handle pending switch tab request
    if pendingSwitchRequest != nil {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    } else {
      // Initial display: need to draw highlight for currentTab
      updateTabButtons(activeTab: currentTab)
    }

    updateVerticalConstraints()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
    addObserver(self, forKeyPath: #keyPath(view.effectiveAppearance), options: [.old, .new], context: nil)

    if #available(macOS 10.14, *) {
      distObservers.append(DistributedNotificationCenter.default().addObserver(forName: .appleColorPreferencesChangedNotification, object: nil, queue: .main, using: self.systemColorSettingsDidChange))
    }

    // notifications
    playlistChangeObserver = NotificationCenter.default.addObserver(forName: .iinaPlaylistChanged, object: player, queue: .main) { [self] _ in
      self.playlistTotalLengthIsReady = false
      self.reloadData(playlist: true, chapters: false)
    }

    // register for double click action
    let action = #selector(performDoubleAction(sender:))
    playlistTableView.doubleAction = action
    playlistTableView.target = self
    chapterTableView.doubleAction = action
    chapterTableView.target = self

    // register for drag and drop
    playlistTableView.registerForDraggedTypes([.iinaPlaylistItem, .nsFilenames, .nsURL, .string])

    (subPopover.contentViewController as! SubPopoverViewController).player = player
    if let popoverView = subPopover.contentViewController?.view,
      popoverView.trackingAreas.isEmpty {
      popoverView.addTrackingArea(NSTrackingArea(rect: popoverView.bounds,
                                                 options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                                 owner: windowController, userInfo: [PlayerWindowController.TrackingArea.key: PlayerWindowController.TrackingArea.playerWindow]))
    }
    view.layoutSubtreeIfNeeded()
  }

  @objc func systemColorSettingsDidChange(notification: Notification) {
    Logger.log("Detected change system color prefs; reloading tabls", level: .verbose)
    reloadData(playlist: true, chapters: true)
  }

  override func viewDidAppear() {
    scrollPlaylistToCurrentItem()
    updateLoopBtnStatus()
  }

  deinit {
    for observer in distObservers {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
    distObservers = []
    UserDefaults.standard.removeObserver(self, forKeyPath: #keyPath(view.effectiveAppearance))
    NotificationCenter.default.removeObserver(self.playlistChangeObserver!)
  }

  func scrollPlaylistToCurrentItem() {
    if let entryIndex = player.info.currentMedia?.playlistPos {
      playlistTableView.scrollRowToVisible(entryIndex)
    }
  }

  func reloadData(playlist: Bool, chapters: Bool) {
    if playlist {
      player.log.verbose("Reloading playlist table")
      playlistTableView.reloadData()
    }
    if chapters {
      chapterTableView.reloadData()
    }

    removeBtn.isEnabled = !playlistTableView.selectedRowIndexes.isEmpty
  }

  private func showTotalLength() {
    guard let playlistTotalLength = playlistTotalLength, playlistTotalLengthIsReady else { return }
    totalLengthLabel.isHidden = false
    if playlistTableView.numberOfSelectedRows > 0 {
      let info = player.info
      let selectedDuration = info.calculateTotalDuration(playlistTableView.selectedRowIndexes)
      totalLengthLabel.stringValue = String(format: NSLocalizedString("playlist.total_length_with_selected", comment: "%@ of %@ selected"),
                                            VideoTime(selectedDuration).stringRepresentation,
                                            VideoTime(playlistTotalLength).stringRepresentation)
    } else {
      totalLengthLabel.stringValue = String(format: NSLocalizedString("playlist.total_length", comment: "%@ in total"),
                                            VideoTime(playlistTotalLength).stringRepresentation)
    }
  }

  private func hideTotalLength() {
    totalLengthLabel.isHidden = true
  }

  private func refreshTotalLength() {
    let totalDuration: Double? = player.info.calculateTotalDuration()
    if let duration = totalDuration {
      playlistTotalLengthIsReady = true
      playlistTotalLength = duration
      DispatchQueue.main.async {
        self.showTotalLength()
      }
    } else {
      DispatchQueue.main.async {
        self.hideTotalLength()
      }
    }
  }

  func updateLoopBtnStatus() {
    guard isViewLoaded else { return }
    let loopMode = player.getLoopMode()
    switch loopMode {
    case .off:  loopBtn.state = .off
    case .file: loopBtn.state = .on
    default:    loopBtn.state = .mixed
    }
    loopBtn.alternateImage = NSImage.init(named: loopBtn.state == .on ? "loop_file" : "loop_dark")
  }

  // MARK: - Tab switching

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabViewType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  /** Switch tab (for internal call) */
  private func switchToTab(_ tab: TabViewType) {
    updateTabButtons(activeTab: tab)
    switch tab {
    case .playlist:
      refreshNowPlayingIndex()
      tabView.selectTabViewItem(at: 0)
    case .chapters:
      tabView.selectTabViewItem(at: 1)
    }

    currentTab = tab
    windowController.didChangeTab(to: tab.rawValue)
  }

  // Updates display of all tabs buttons to indicate that the given tab is active and the rest are not
  private func updateTabButtons(activeTab: TabViewType) {
    switch activeTab {
    case .playlist:
      updateTabActiveStatus(for: playlistBtn, isActive: true)
      updateTabActiveStatus(for: chaptersBtn, isActive: false)
    case .chapters:
      updateTabActiveStatus(for: playlistBtn, isActive: false)
      updateTabActiveStatus(for: chaptersBtn, isActive: true)
    }
  }

  private func updateTabActiveStatus(for btn: NSButton, isActive: Bool) {
    if #available(macOS 10.14, *) {
      btn.contentTintColor = isActive ? NSColor.sidebarTabTintActive : NSColor.sidebarTabTint
    } else {
      Utility.setBoldTitle(for: btn, isActive)
    }
  }

  // MARK: - NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == playlistTableView {
      return player.info.playlist.count
    } else if tableView == chapterTableView {
      return player.info.chapters.count
    } else {
      return 0
    }
  }

  // MARK: - Drag and Drop

  func copyToPasteboard(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) {
    let indexesData = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
    let playlistItems = player.info.playlist
    let filePaths = rowIndexes.compactMap { playlistItems[$0].filename }
    pboard.declareTypes([.iinaPlaylistItem, .nsFilenames], owner: tableView)
    pboard.setData(indexesData, forType: .iinaPlaylistItem)
    pboard.setPropertyList(filePaths, forType: .nsFilenames)
  }

  @discardableResult
  func pasteFromPasteboard(_ tableView: NSTableView, row: Int, from pboard: NSPasteboard) -> Bool {
    if let paths = pboard.propertyList(forType: .nsFilenames) as? [String] {
      let playableFiles = Utility.resolveURLs(player.getPlayableFiles(in: paths.map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0)!
      }))
      if playableFiles.count == 0 {
        return false
      }
      player.addToPlaylist(paths: playableFiles.map { $0.isFileURL ? $0.path : $0.absoluteString }, at: row)
    } else if let urls = pboard.propertyList(forType: .nsURL) as? [String] {
      player.addToPlaylist(paths: urls, at: row)
    } else if let droppedString = pboard.string(forType: .string), Regex.url.matches(droppedString) {
      player.addToPlaylist(paths: [droppedString], at: row)
    } else {
      return false
    }
    return true
  }

  func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
    if tableView == playlistTableView {
      copyToPasteboard(tableView, writeRowsWith: rowIndexes, to: pboard)
      return true
    }
    return false
  }


  func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    playlistTableView.setDropRow(row, dropOperation: .above)
    if info.draggingSource as? NSTableView === tableView {
      return .move
    }
    return player.acceptFromPasteboard(info, isPlaylist: true)
  }

  func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
    if info.draggingSource as? NSTableView === tableView,
      let rowData = info.draggingPasteboard.data(forType: .iinaPlaylistItem),
      let indexSet = NSKeyedUnarchiver.unarchiveObject(with: rowData) as? IndexSet {

      player.playlistMove(indexSet, to: row)
      return true
    }
    // Otherwise, could be copy/cut & paste within playlistTableView
    return pasteFromPasteboard(tableView, row: row, from: info.draggingPasteboard)
  }

  // MARK: - Edit Menu Support

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if currentTab == .playlist {
      switch menuItem.tag {
      case MenuItemTagCut, MenuItemTagCopy, MenuItemTagDelete:
        return playlistTableView.selectedRow != -1
      case MenuItemTagPaste:
        return NSPasteboard.general.types?.contains(.nsFilenames) ?? false
      default:
        break
      }
    }
    return menuItem.isEnabled
  }

  @objc func copy(_ sender: NSMenuItem) {
    copyToPasteboard(playlistTableView, writeRowsWith: playlistTableView.selectedRowIndexes, to: .general)
  }

  @objc func cut(_ sender: NSMenuItem) {
    copy(sender)
    delete(sender)
  }

  @objc func paste(_ sender: NSMenuItem) {
    let dest = playlistTableView.selectedRowIndexes.first ?? 0
    pasteFromPasteboard(playlistTableView, row: dest, from: .general)
  }

  @objc func delete(_ sender: NSMenuItem) {
    let selectedRows = playlistTableView.selectedRowIndexes
    if !selectedRows.isEmpty {
      player.playlistRemove(selectedRows)
    }
  }

  // MARK: - private methods

  private func withAllTableViews(_ block: (NSTableView) -> Void) {
    block(playlistTableView)
    block(chapterTableView)
  }

  // MARK: - IBActions

  @IBAction func addToPlaylistBtnAction(_ sender: NSButton) {
    addFileMenu.popUp(positioning: nil, at: .zero, in: sender)
  }

  @IBAction func removeBtnAction(_ sender: NSButton) {
    player.playlistRemove(playlistTableView.selectedRowIndexes)
  }

  @IBAction func addFileAction(_ sender: AnyObject) {
    Utility.quickMultipleOpenPanel(title: "Add to playlist", canChooseDir: true) { urls in
      let playableFiles = self.player.getPlayableFiles(in: urls)
      if playableFiles.count != 0 {
        self.player.addToPlaylist(paths: playableFiles.map { $0.path }, at: self.player.info.playlist.count)
        self.player.sendOSD(.addToPlaylist(playableFiles.count))
      }
    }
  }

  @IBAction func addURLAction(_ sender: AnyObject) {
    Utility.quickPromptPanel("add_url") { url in
      if Regex.url.matches(url) {
        self.player.addToPlaylist(url)
        self.player.sendOSD(.addToPlaylist(1))
      } else {
        Utility.showAlert("wrong_url_format")
      }
    }
  }

  @IBAction func clearPlaylistBtnAction(_ sender: AnyObject) {
    player.clearPlaylist()
    player.sendOSD(.clearPlaylist)
  }

  @IBAction func playlistBtnAction(_ sender: AnyObject) {
    switchToTab(.playlist)
  }

  @IBAction func chaptersBtnAction(_ sender: AnyObject) {
    switchToTab(.chapters)
  }

  @IBAction func loopBtnAction(_ sender: NSButton) {
    player.nextLoopMode()
  }

  @IBAction func loopFileBtnAction(_ sender: AnyObject) {
    player.toggleFileLoop()
  }
  
  @IBAction func shuffleBtnAction(_ sender: AnyObject) {
    player.toggleShuffle()
  }


  @objc func performDoubleAction(sender: AnyObject) {
    guard let tv = sender as? NSTableView, tv.numberOfSelectedRows > 0 else { return }
    if tv == playlistTableView {
      player.playFileInPlaylist(tv.selectedRow)
    } else {
      let index = tv.selectedRow
      player.playChapter(index)
    }
    tv.deselectAll(self)
    tv.reloadData()
  }

  @IBAction func prefixBtnAction(_ sender: PlaylistPrefixButton) {
    sender.isFolded = !sender.isFolded
  }

  @IBAction func subBtnAction(_ sender: NSButton) {
    let row = playlistTableView.row(for: sender)
    guard let vc = subPopover.contentViewController as? SubPopoverViewController else { return }
    let playlist = player.info.playlist
    guard row < playlist.count else { return }
    vc.filePath = playlist[row].filename
    vc.tableView.reloadData()
    subPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  // MARK: - Table delegates

  func tableViewSelectionDidChange(_ notification: Notification) {
    let tv = notification.object as! NSTableView
    if tv == playlistTableView {
      showTotalLength()

      removeBtn.isEnabled = !playlistTableView.selectedRowIndexes.isEmpty
      return
    }
  }

  // Updates index of playing item Don't need to reload whole playlist
  func refreshNowPlayingIndex(setNewIndexTo newNowPlayingIndex: Int? = nil) {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
    guard isViewLoaded else { return }
    guard !view.isHidden else { return }

    let oldNowPlayingIndex = self.lastNowPlayingIndex
    let newNowPlayingIndex = newNowPlayingIndex ?? player.info.currentMedia?.playlistPos ?? oldNowPlayingIndex
    if newNowPlayingIndex != oldNowPlayingIndex {
      player.log.verbose("Updating nowPlayingIndex: \(oldNowPlayingIndex) → \(newNowPlayingIndex)")
      self.lastNowPlayingIndex = newNowPlayingIndex
      DispatchQueue.main.async { [self] in
        // If "now playing" row changed, make sure the new "now playing" row is redrawn to show its new status...
        playlistTableView.reloadData(forRowIndexes: IndexSet(integer: newNowPlayingIndex), columnIndexes: IndexSet(integersIn: 0...1))
        // ... also make sure the old "now playing" row is redrawn so it loses its status
        playlistTableView.reloadData(forRowIndexes: IndexSet(integer: oldNowPlayingIndex), columnIndexes: IndexSet(integersIn: 0...1))
      }
    }
  }

  fileprivate class ClearBackgroundRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
      layer?.backgroundColor = .clear

      // Y origin is at top
      let dash = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
      NSColor.playlistProgressBarBackground.setFill()
      NSBezierPath(rect: dash).fill()
    }
  }

//  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
//    // uses custom highlight for table row
//    return ClearBackgroundRowView()
//  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier else { return nil }
    let info = player.info
    let v = tableView.makeView(withIdentifier: identifier, owner: self) as! NSTableCellView

    // playlist
    if tableView == playlistTableView {
      let playlistItems = info.playlist
      guard row < playlistItems.count else { return nil }
      let item = playlistItems[row]

      refreshNowPlayingIndex()
      // use cached value
      let isPlaying = self.lastNowPlayingIndex == row

      if identifier == .isChosen {
        // ▶︎ Is Playing icon
        if let textField = v.textField {
          let text = isPlaying ? Constants.String.play : ""
          textField.setFormattedText(stringValue: text, textColor: isPlayingTextColor)
        }
      } else if identifier == .trackName {
        // Track title
        let cellView = v as! PlaylistTrackCellView
        let filename = item.filenameForDisplay
        let displayStr: String = NSString(string: filename).deletingPathExtension

        func getCachedMetadata() -> (artist: String, title: String)? {
          guard Preference.bool(for: .playlistShowMetadata) else { return nil }
          if Preference.bool(for: .playlistShowMetadataInMusicMode) && !player.isInMiniPlayer {
            return nil
          }
          guard let metadata = info.getCachedMetadata(item.filename) else { return nil }
          guard let artist = metadata.artist, let title = metadata.title else { return nil }
          return (artist, title)
        }

        let textColor = isPlaying ? isPlayingTextColor : .controlTextColor
        let prefixTextColor = isPlaying ? isPlayingPrefixTextColor : .secondaryLabelColor
        if Preference.bool(for: .shortenFileGroupsInPlaylist), let prefix = player.info.currentVideosInfo.first(where: { $0.path == item.filename })?.prefix,
           !prefix.isEmpty,
           prefix.count <= displayStr.count,  // check whether prefix length > filename length
           prefix.count >= PrefixMinLength,
           filename.count > FilenameMinLength {
          cellView.setPrefix(prefix, textColor: prefixTextColor)
          cellView.setTitle(String(filename[filename.index(filename.startIndex, offsetBy: prefix.count)...]), textColor: textColor)
        } else {
          cellView.setPrefix(nil, textColor: prefixTextColor)
          cellView.setAdditionalInfo(nil)
          cellView.setTitle(filename, textColor: textColor)
        }
        // playback progress and duration
        cellView.durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        cellView.durationLabel.stringValue = ""
        PlayerCore.playlistQueue.async {
          if let (artist, title) = getCachedMetadata() {
            DispatchQueue.main.async {
              cellView.setTitle(title, textColor: textColor)
              cellView.setAdditionalInfo(artist, textColor: textColor)
            }
          }
          if let cached = self.player.info.getCachedVideoDurationAndProgress(item.filename),
             let duration = cached.duration {
            // if it's cached
            if duration > 0 {
              // if FFmpeg got the duration successfully
              DispatchQueue.main.async { [self] in
                let durationString = VideoTime(duration).stringRepresentation
                cellView.durationLabel.setFormattedText(stringValue: durationString, textColor: isPlaying ? isPlayingTextColor : .secondaryLabelColor)
                if let progress = cached.progress {
                  cellView.playbackProgressView.percentage = progress / duration
                  cellView.playbackProgressView.needsDisplay = true
                  cellView.playbackProgressView.isHidden = false
                } else {
                  cellView.playbackProgressView.isHidden = true
                }
                if isPlaying {
                  cellView.needsDisplay = true
                  cellView.needsLayout = true
                }
              }
              self.refreshTotalLength()
            }
          } else {
            // get related data and schedule a reload
            if Preference.bool(for: .prefetchPlaylistVideoDuration) {
              self.player.refreshCachedVideoInfo(forVideoPath: item.filename)
              // Only schedule a reload if data was obtained and cached to avoid looping
              if let cached = self.player.info.getCachedVideoDurationAndProgress(item.filename),
                 let duration = cached.duration, duration > 0 {
                // if FFmpeg got the duration successfully
                self.refreshTotalLength()
                DispatchQueue.main.async {
                  self.playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
                }
              }
            }
          }
        }
        // sub button
        if !info.isMatchingSubtitles,
           let matchedSubs = player.info.getMatchedSubs(item.filename), !matchedSubs.isEmpty {
          cellView.setDisplaySubButton(true)
        } else {
          cellView.setDisplaySubButton(false)
        }
        // not sure why this line exists, but let's keep it for now
        cellView.subBtn.image?.isTemplate = true
      }
      return v
    }
    // chapter
    else if tableView == chapterTableView {
      let chapters = info.chapters
      guard row < chapters.count else {
        return nil
      }
      let chapter = chapters[row]
      // next chapter time
      let nextChapterTime = chapters[at: row+1]?.time ?? .infinite
      // construct view
      let isCurrentChapter = info.chapter == row
      let textColor = isCurrentChapter ? isPlayingTextColor : .controlTextColor

      if identifier == .isChosen {
        // left column
        v.setTitle(isCurrentChapter ? Constants.String.play : "", textColor: textColor)
        return v
      } else if identifier == .trackName {
        // right column
        let titleString = chapter.title.isEmpty ? "Chapter \(row)" : chapter.title
        v.setTitle(titleString, textColor: textColor)
        let cellView = v as! ChapterTableCellView
        cellView.durationTextField.setText("\(chapter.time.stringRepresentation) → \(nextChapterTime.stringRepresentation)", textColor: textColor)
        return cellView
      } else {
        return nil
      }
    }
    else {
      return nil
    }
  }

  // MARK: - Context menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    buildContextMenu(menu)
  }

  private func getTargetRowsForContextMenu() -> IndexSet {
    let selectedRows = playlistTableView.selectedRowIndexes
    let clickedRow = playlistTableView.clickedRow
    guard clickedRow != -1 else {
      return IndexSet()
    }

    if selectedRows.contains(clickedRow) {
      return selectedRows
    } else {
      return IndexSet(integer: clickedRow)
    }
  }

  @IBAction func contextMenuPlayNext(_ sender: ContextMenuItem) {
    player.playNextInPlaylist(sender.targetRows)
    playlistTableView.deselectAll(nil)
  }

  @IBAction func contextMenuPlayInNewWindow(_ sender: ContextMenuItem) {
    let playlistItems = player.info.playlist
    let files = sender.targetRows.enumerated().compactMap { (_, i) in
      i < playlistItems.count ? URL(fileURLWithPath: playlistItems[i].filename) : nil
    }
    PlayerCore.newPlayerCore.openURLs(files, shouldAutoLoad: false)
  }

  @IBAction func contextMenuRemove(_ sender: ContextMenuItem) {
    Logger.log("User chose to remove rows \(sender.targetRows.map{$0}) from playlist")
    player.playlistRemove(sender.targetRows)
  }

  @IBAction func contextMenuDeleteFile(_ sender: ContextMenuItem) {
    Logger.log("User chose to delete files from playlist at indexes: \(sender.targetRows.map{$0})")

    let playlistItems = player.info.playlist
    var successes = IndexSet()
    for index in sender.targetRows {
      guard index < playlistItems.count else { continue }
      guard !playlistItems[index].isNetworkResource else { continue }
      let url = URL(fileURLWithPath: playlistItems[index].filename)
      do {
        Logger.log("Trashing row \(index): \(url.standardizedFileURL)")
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        successes.insert(index)
      } catch let error {
        Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
      }
    }
    if !successes.isEmpty {
      player.playlistRemove(successes)
    }
  }

  @IBAction func contextMenuDeleteFileAfterPlayback(_ sender: NSMenuItem) {
    // WIP
  }

  private func getFiles(fromPlaylistRows rows: IndexSet) -> [URL] {
    var urls: [URL] = []
    let playlistItems = player.info.playlist
    for index in rows {
      guard index < playlistItems.count else { continue }
      if !playlistItems[index].isNetworkResource {
        urls.append(URL(fileURLWithPath: playlistItems[index].filename))
      }
    }

    return urls
  }

  @IBAction func contextMenuShowInFinder(_ sender: ContextMenuItem) {
    let urls: [URL] = getFiles(fromPlaylistRows: sender.targetRows)
    guard !urls.isEmpty else {
      player.log.error("Show in Finder failed: found no files in \(sender.targetRows.count) provided rows!")
      return
    }
    playlistTableView.deselectAll(nil)
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  @IBAction func contextMenuAddSubtitle(_ sender: ContextMenuItem) {
    guard let index = sender.targetRows.first else { return }
    let playlistItems = player.info.playlist
    guard index < playlistItems.count else { return }
    let filename = playlistItems[index].filename
    let fileURL = URL(fileURLWithPath: filename).deletingLastPathComponent()
    Utility.quickMultipleOpenPanel(title: NSLocalizedString("alert.choose_media_file.title", comment: "Choose Media File"), dir: fileURL, canChooseDir: true) { subURLs in
      for subURL in subURLs {
        guard Utility.supportedFileExt[.sub]!.contains(subURL.pathExtension.lowercased()) else { return }
        self.player.info.$matchedSubs.withLock { $0[filename, default: []].append(subURL) }
      }
      self.playlistTableView.reloadData(forRowIndexes: sender.targetRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextMenuWrongSubtitle(_ sender: ContextMenuItem) {
    let playlistItems = player.info.playlist
    for index in sender.targetRows {
      guard index < playlistItems.count else { continue }
      let filename = playlistItems[index].filename
      player.info.$matchedSubs.withLock { $0[filename]?.removeAll() }
      playlistTableView.reloadData(forRowIndexes: sender.targetRows, columnIndexes: IndexSet(integersIn: 0...1))
    }
  }

  @IBAction func contextOpenInBrowser(_ sender: ContextMenuItem) {
    let playlistItems = player.info.playlist
    for i in sender.targetRows {
      guard i < playlistItems.count else { continue }

      let info = playlistItems[i]
      if info.isNetworkResource, let url = URL(string: info.filename) {
        NSWorkspace.shared.open(url)
      }
    }
  }

  @IBAction func contextCopyURL(_ sender: ContextMenuItem) {
    let playlistItems = player.info.playlist
    let urls = sender.targetRows.compactMap { i -> String? in
      guard i < playlistItems.count else { return nil }
      let info = playlistItems[i]
      return info.isNetworkResource ? info.filename : nil
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([urls.joined(separator: "\n") as NSString])
  }

  private func buildContextMenu(_ menu: NSMenu) {
    let playlistItems = player.info.playlist
    let rows = getTargetRowsForContextMenu()
    Logger.log("Building context menu for rows: \(rows.map{ $0 })", level: .verbose)

    menu.removeAllItems()

    let isSingleItem = rows.count == 1

    if !rows.isEmpty {
      let firstURL = playlistItems[rows.first!]
      let matchedSubCount = player.info.getMatchedSubs(firstURL.filename)?.count ?? 0
      let title: String = isSingleItem ?
        firstURL.filenameForDisplay :
        String(format: NSLocalizedString("pl_menu.title_multi", comment: "%d Items"), rows.count)

      menu.addItem(withTitle: title)
      menu.addItem(NSMenuItem.separator())
      menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.play_next", comment: "Play Next"), action: #selector(self.contextMenuPlayNext(_:)))
      menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.play_in_new_window", comment: "Play in New Window"), action: #selector(self.contextMenuPlayInNewWindow(_:)))
      menu.addItem(forRows: rows, withTitle: NSLocalizedString(isSingleItem ? "pl_menu.remove" : "pl_menu.remove_multi", comment: "Remove"), action: #selector(self.contextMenuRemove(_:)))

      if !player.isInMiniPlayer {
        menu.addItem(NSMenuItem.separator())
        if isSingleItem {
          menu.addItem(forRows: rows, withTitle: String(format: NSLocalizedString("pl_menu.matched_sub", comment: "Matched %d Subtitle(s)"), matchedSubCount))
          menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.add_sub", comment: "Add Subtitle…"), action: #selector(self.contextMenuAddSubtitle(_:)))
        }
        if matchedSubCount != 0 {
          menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.wrong_sub", comment: "Wrong Subtitle"), action: #selector(self.contextMenuWrongSubtitle(_:)))
        }
      }

      menu.addItem(NSMenuItem.separator())
      // network resources related operations
      let networkCount = rows.filter {
        playlistItems[$0].isNetworkResource
      }.count
      if networkCount != 0 {
        menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.browser", comment: "Open in Browser"), action: #selector(self.contextOpenInBrowser(_:)))
        menu.addItem(forRows: rows, withTitle: NSLocalizedString(networkCount == 1 ? "pl_menu.copy_url" : "pl_menu.copy_url_multi", comment: "Copy URL(s)"), action: #selector(self.contextCopyURL(_:)))
        menu.addItem(NSMenuItem.separator())
      }
      // file related operations
      let localCount = rows.count - networkCount
      if localCount != 0 {
        menu.addItem(forRows: rows, withTitle: NSLocalizedString(localCount == 1 ? "pl_menu.delete" : "pl_menu.delete_multi", comment: "Delete"), action: #selector(self.contextMenuDeleteFile(_:)))
        // menu.addItem(forRows: rows, withTitle: NSLocalizedString(isSingleItem ? "pl_menu.delete_after_play" : "pl_menu.delete_after_play_multi", comment: "Delete After Playback"), action: #selector(self.contextMenuDeleteFileAfterPlayback(_:)))

        menu.addItem(forRows: rows, withTitle: NSLocalizedString("pl_menu.show_in_finder", comment: "Show in Finder"), action: #selector(self.contextMenuShowInFinder(_:)))
        menu.addItem(NSMenuItem.separator())
      }
    }

    // menu items from plugins
    var hasPluginMenuItems = false
    let filenames = Array(rows)
    let pluginMenuItems = player.plugins.map {
      plugin -> (JavascriptPluginInstance, [JavascriptPluginMenuItem]) in
      if let builder = (plugin.apis["playlist"] as! JavascriptAPIPlaylist).menuItemBuilder?.value,
        let value = builder.call(withArguments: [filenames]),
        value.isObject,
        let items = value.toObject() as? [JavascriptPluginMenuItem] {
        hasPluginMenuItems = true
        return (plugin, items)
      }
      return (plugin, [])
    }
    if hasPluginMenuItems {
      menu.addItem(withTitle: NSLocalizedString("preference.plugins", comment: "Plugins"))
      for (plugin, items) in pluginMenuItems {
        for item in items {
          add(menuItemDef: item, to: menu, for: plugin)
        }
      }
      menu.addItem(NSMenuItem.separator())
    }

    menu.addItem(withTitle: NSLocalizedString("pl_menu.add_file", comment: "Add File"), action: #selector(self.addFileAction(_:)))
    menu.addItem(withTitle: NSLocalizedString("pl_menu.add_url", comment: "Add URL"), action: #selector(self.addURLAction(_:)))
    menu.addItem(withTitle: NSLocalizedString("pl_menu.clear_playlist", comment: "Clear Playlist"), action: #selector(self.clearPlaylistBtnAction(_:)))
  }

  @discardableResult
  private func add(menuItemDef item: JavascriptPluginMenuItem,
                   to menu: NSMenu,
                   for plugin: JavascriptPluginInstance) -> NSMenuItem {
    if (item.isSeparator) {
      let item = NSMenuItem.separator()
      menu.addItem(item)
      return item
    }

    let menuItem: NSMenuItem
    if item.action == nil {
      menuItem = menu.addItem(withTitle: item.title, action: nil, target: plugin, obj: item)
    } else {
      menuItem = menu.addItem(withTitle: item.title,
                              action: #selector(plugin.playlistMenuItemAction(_:)),
                              target: plugin,
                              obj: item)
    }

    menuItem.isEnabled = item.enabled
    menuItem.state = item.selected ? .on : .off
    if !item.items.isEmpty {
      menuItem.submenu = NSMenu()
      for submenuItem in item.items {
        add(menuItemDef: submenuItem, to: menuItem.submenu!, for: plugin)
      }
    }
    return menuItem
  }
}


class PlaylistTrackCellView: NSTableCellView {
  @IBOutlet weak var subBtn: NSButton!
  @IBOutlet weak var subBtnWidthConstraint: NSLayoutConstraint!
  @IBOutlet weak var subBtnTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var prefixBtn: PlaylistPrefixButton!
  @IBOutlet weak var infoLabel: EditableTextField!  /// use `EditableTextField` class for proper highlight color
  @IBOutlet weak var infoLabelTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var durationLabel: EditableTextField!
  @IBOutlet weak var playbackProgressView: PlaylistPlaybackProgressView!

  func setPrefix(_ prefix: String?, textColor: NSColor? = nil) {
    if #available(macOS 10.14, *) {
      prefixBtn.contentTintColor = textColor
    } else {
      // Sorry earlier versions, no color for you
    }
    if let prefix = prefix {
      prefixBtn.hasPrefix = true
      prefixBtn.text = prefix
    } else {
      prefixBtn.hasPrefix = false
    }
  }

  func setDisplaySubButton(_ show: Bool) {
    if show {
      subBtn.isHidden = false
      subBtnWidthConstraint.constant = 12
      subBtnTrailingConstraint.constant = 4
    } else {
      subBtn.isHidden = true
      subBtnWidthConstraint.constant = 0
      subBtnTrailingConstraint.constant = 0
    }
  }

  func setAdditionalInfo(_ string: String?, textColor: NSColor? = nil) {
    if let string = string {
      infoLabel.isHidden = false
      infoLabelTrailingConstraint.constant = 4
      infoLabel.setFormattedText(stringValue: string, textColor: textColor)
      infoLabel.stringValue = string
      infoLabel.toolTip = string
    } else {
      infoLabel.isHidden = true
      infoLabelTrailingConstraint.constant = 0
      infoLabel.stringValue = ""
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    playbackProgressView.percentage = 0
    playbackProgressView.needsDisplay = true
    setPrefix(nil)
    setAdditionalInfo(nil)
  }
}


class PlaylistPrefixButton: NSButton {

  var text = "" {
    didSet {
      refresh()
    }
  }

  var hasPrefix = true {
    didSet {
      refresh()
    }
  }

  var isFolded = true {
    didSet {
      refresh()
    }
  }

  private func refresh() {
    self.title = hasPrefix ? (isFolded ? "…" : text) : ""
  }

}


class PlaylistView: NSView {

  override func resetCursorRects() {
    let rect = NSRect(x: frame.origin.x - 4, y: frame.origin.y, width: 4, height: frame.height)
    addCursorRect(rect, cursor: .resizeLeftRight)
  }

  override func mouseDown(with event: NSEvent) {}

  // override var allowsVibrancy: Bool { return true }

}


class SubPopoverViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

  @IBOutlet weak var tableView: NSTableView!
  @IBOutlet weak var playlistTableView: NSTableView!

  weak var player: PlayerCore!

  var filePath: String = ""

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return false
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard let matchedSubs = player.info.getMatchedSubs(filePath) else { return nil }
    return matchedSubs[row].lastPathComponent
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    return player.info.getMatchedSubs(filePath)?.count ?? 0
  }

  @IBAction func wrongSubBtnAction(_ sender: AnyObject) {
    player.info.$matchedSubs.withLock { $0[filePath]?.removeAll() }
    tableView.reloadData()
    if let row = player.info.playlist.firstIndex(where: { $0.filename == filePath }) {
      playlistTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0...1))
    }
  }
}

class ChapterTableCellView: NSTableCellView {
  @IBOutlet weak var durationTextField: EditableTextField!
}
