//
//  PWin_Sidebars.swift
//  iina
//
//  Created by Matt Svoboda on 2023-03-26.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

private func clampPlaylistWidth(_ width: CGFloat) -> CGFloat {
  return width.clamped(to: Constants.Sidebar.minPlaylistWidth...Constants.Sidebar.maxPlaylistWidth).rounded()
}

// Sidebar layout state
struct Sidebar {
  enum Visibility {
    case show(tabToShow: Sidebar.Tab)
    case hide

    var visibleTab: Sidebar.Tab? {
      switch self {
      case .show(let tab):
        return tab
      case .hide:
        return nil
      }
    }
  }

  /// Type of the view embedded in sidebar.
  enum TabGroup: String {
    case settings
    case playlist
    case plugins

    func width(using sidebarState: SidebarMiscState) -> CGFloat {
      switch self {
      case .settings, .plugins:
        return Constants.Sidebar.settingsWidth
      case .playlist:
        return clampPlaylistWidth(CGFloat(sidebarState.playlistSidebarWidth))
      }
    }

    static func fromPrefs(for locationID: Preference.SidebarLocation) -> Set<Sidebar.TabGroup> {
      var tabGroups = Set<Sidebar.TabGroup>()
      if Preference.enum(for: .settingsTabGroupLocation) == locationID {
        tabGroups.insert(.settings)
      }
      if Preference.enum(for: .playlistTabGroupLocation) == locationID {
        tabGroups.insert(.playlist)
      }
      if Preference.enum(for: .pluginsTabGroupLocation) == locationID {
        tabGroups.insert(.plugins)
      }
      return tabGroups
    }
  }

  // Includes all types of tabs possible in all tab groups
  enum Tab: Equatable {

    case playlist
    case chapters

    case video
    case audio
    case sub

    case anyPlugin
    /// Plugin tabs are serialized in the format `"plugin:\(id)"`.
    /// A plugin cannot have any ID matching `Constants.Sidebar.anyPluginID`, because that is reserved to represent `anyPlugin`.
    case plugin(id: String)

    init?(name: String?) {
      guard let name = name else {
        return nil
      }
      switch name {
      case "playlist":
        self = .playlist
      case "chapters":
        self = .chapters
      case "video":
        self = .video
      case "audio":
        self = .audio
      case "sub":
        self = .sub
      case "nil":
        return nil
      case Constants.Sidebar.anyPluginID:
        self = .anyPlugin
      default:
        if name.hasPrefix("plugin:") {
          let pluginID = name.dropFirst(7)
          self = .plugin(id: String(pluginID))
        } else {
          return nil
        }
      }
    }

    var name: String {
      switch self {
      case .playlist: return "playlist"
      case .chapters: return "chapters"
      case .video: return "video"
      case .audio: return "audio"
      case .sub: return "sub"
      case .anyPlugin: return Constants.Sidebar.anyPluginID
      case .plugin(let id): return "plugin:\(id)"
      }
    }

    var group: Sidebar.TabGroup {
      switch self {
      case .playlist, .chapters:
        return .playlist
      case .video, .audio, .sub:
        return .settings
      case .plugin(id: _), .anyPlugin:
        return .plugins
      }
    }

  }  // enum Tab


  struct SidebarMiscState {
    let playlistSidebarWidth: Int
    let selectedSubSegment: Int
    let selectedPluginTabID: String

    static func fromDefaultPrefs() -> SidebarMiscState {
      return SidebarMiscState(playlistSidebarWidth: Preference.integer(for: .playlistWidth),
                              selectedSubSegment: 0, selectedPluginTabID: Constants.Sidebar.anyPluginID)
    }
  }


  // MARK: - Sidebar Init

  init(_ locationID: Preference.SidebarLocation, tabGroups: Set<TabGroup>, placement: Preference.PanelPlacement,
       visibility: Sidebar.Visibility, lastVisibleTab: Sidebar.Tab? = nil) {
    self.locationID = locationID
    self.placement = placement
    self.visibility = visibility
    self.tabGroups = tabGroups

    /// some validation before setting `lastVisibleTab`
    if let visibleTab = visibility.visibleTab, tabGroups.contains(visibleTab.group) {
      self.lastVisibleTab = visibleTab
    } else if let lastVisibleTab = lastVisibleTab, tabGroups.contains(lastVisibleTab.group) {
      self.lastVisibleTab = lastVisibleTab
    } else {
      self.lastVisibleTab = nil
    }
  }

  func clone(tabGroups: Set<TabGroup>? = nil, placement: Preference.PanelPlacement? = nil,
             visibility: Sidebar.Visibility? = nil) -> Sidebar {
    let newTabGroups = tabGroups ?? self.tabGroups
    var newVisibility = visibility ?? self.visibility
    if let newVisibleTab = newVisibility.visibleTab, !newTabGroups.contains(newVisibleTab.group) {
      Logger.log("Can no longer show visible tab \(newVisibleTab.name) in \(self.locationID). The sidebar will close.", level: .verbose)
      newVisibility = .hide
    }

    return Sidebar(self.locationID,
                   tabGroups: newTabGroups,
                   placement: placement ?? self.placement,
                   visibility: newVisibility,
                   lastVisibleTab: self.lastVisibleTab)
  }


  // MARK: - Stored Properties

  /// `leadingSidebar` or `trailingSidebar`
  let locationID: Preference.SidebarLocation

  /// One of `show(Sidebar.Tab)` or `hide`:
  let visibility: Visibility

  /// If sidebar is showing, this should be the same as `visibleTab`. Otherwise this matches the last tab
  /// which was shown since the current app launch, if it is still valid with respect to the current `tabGroups`.
  /// Otherwise returns `nil`.
  let lastVisibleTab: Sidebar.Tab?

  // Should match prefs
  let placement: Preference.PanelPlacement
  /// The set of tab groups assigned to this sidebar as configured by prefs. May be empty.
  /// If empty, this sidebar cannot be shown.
  /// If `visibleTab` and `lastVisibleTab` must belong to a tab group in this list, respectively.
  let tabGroups: Set<Sidebar.TabGroup>


  // MARK: - Computed Properties

  /// The currently visible tab, if sidebar is open/visible. Is `nil` if sidebar is closed/hidden.
  /// Use `lastVisibleTab` if the last shown tab needs to be known.
  var visibleTab: Sidebar.Tab? {
    return visibility.visibleTab
  }

  /// The parent `TabGroup` of `visibleTab`
  var visibleTabGroup: Sidebar.TabGroup? {
    return visibleTab?.group
  }

  var isVisible: Bool {
    return visibleTab != nil
  }

  var defaultTabToShow: Sidebar.Tab? {
    // Use last visible tab if still valid:
    if let lastVisibleTab = lastVisibleTab, tabGroups.contains(lastVisibleTab.group) {
      Logger.log.verbose("Returning last visible tab for \(locationID): \(lastVisibleTab.name.quoted)")
      return lastVisibleTab
    }

    // Fall back to default for whatever tab group found:
    if let group = tabGroups.first {
      switch group {
      case .playlist:
        return Sidebar.Tab.playlist
      case .settings:
        return Sidebar.Tab.video
      case .plugins:
        return Sidebar.Tab.anyPlugin
      }
    }

    // If sidebar has no tab groups, can't show anything:
    Logger.log.verbose("No tab groups found for \(locationID), returning nil for defaultTab")
    return nil
  }

}  // end struct Sidebar


/// Enapsulates code relating to leading & trailing sidebars in PlayerWindow.
extension PlayerWindowController {
  // MARK: - Show/Hide functions

  func isShowing(sidebarTabGroup tabGroup: Sidebar.TabGroup) -> Bool {
    let layout = currentLayout
    return layout.leadingSidebar.visibleTabGroup == tabGroup || layout.trailingSidebar.visibleTabGroup == tabGroup
  }

  func isShowing(sidebarTab tab: Sidebar.Tab) -> Bool {
    let layout = currentLayout
    return layout.leadingSidebar.visibleTab == tab || layout.trailingSidebar.visibleTab == tab
  }

  @IBAction func toggleLeadingSidebarVisibility(_ sender: NSButton) {
    toggleVisibility(of: .leadingSidebar)
  }

  @IBAction func toggleTrailingSidebarVisibility(_ sender: NSButton) {
    toggleVisibility(of: .trailingSidebar)
  }

  /// Toggles visibility of given `sidebar`
  func toggleVisibility(of sidebarID: Preference.SidebarLocation) {
    animationPipeline.submitInstantTask { [self] in
      guard currentLayout.canShowSidebars else { return }
      let sidebar = currentLayout.sidebar(withID: sidebarID)
      let isCurrentlyVisible = sidebar.isVisible
      log.verbose{"Toggling visibility of sidebar \(sidebarID): \(isCurrentlyVisible.yn) → \((!isCurrentlyVisible).yn)"}
      // Do nothing if sidebar has no configured tabs
      guard let tab = sidebar.defaultTabToShow else { return }

      if isCurrentlyVisible {
        changeVisibility(forTab: tab, to: false)
      } else {
        changeVisibility(forTab: tab, to: true)
      }
    }
  }

  /// Shows or toggles visibility of given `tabGroup`
  func showSidebar(forTabGroup tabGroup: Sidebar.TabGroup, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    log.verbose("ShowSidebar for tabGroup: \(tabGroup.rawValue.quoted), force: \(force), hideIfAlreadyShown: \(hideIfAlreadyShown)")
    switch tabGroup {
    case .playlist:
      showSidebar(tab: playlistView.currentTab, force: force, hideIfAlreadyShown: hideIfAlreadyShown)
    case .settings:
      if let tab = Sidebar.Tab(name: quickSettingView.currentTab.name) {
        showSidebar(tab: tab, force: force, hideIfAlreadyShown: hideIfAlreadyShown)
      }
    case .plugins:
      let pluginID = pluginView.currentPluginID
      let tab: Sidebar.Tab = pluginID == Constants.Sidebar.anyPluginID ? .anyPlugin : Sidebar.Tab.plugin(id: pluginID)
      showSidebar(tab: tab, force: force, hideIfAlreadyShown: hideIfAlreadyShown)
    }
  }

  /// Shows or toggles visibility of given `tab`
  func showSidebar(tab: Sidebar.Tab, force: Bool = false, hideIfAlreadyShown: Bool = true) {
    log.verbose("ShowSidebar for tab: \(tab.name.quoted), force: \(force), hideIfAlreadyShown: \(hideIfAlreadyShown)")

    animationPipeline.submitInstantTask { [self] in
      guard let destinationSidebar = getConfiguredSidebar(forTabGroup: tab.group) else { return }

      if destinationSidebar.visibleTab == tab {
        if hideIfAlreadyShown {
          log.verbose("Will hide \(destinationSidebar.locationID) instead because it is in state \(destinationSidebar.visibility)")
          changeVisibility(forTab: tab, to: false)
        }
      } else {
        // This will first change the sidebar to the displayed tab group if needed:
        changeVisibility(forTab: tab, to: true)
      }
    }
  }

  // Updates placements (inside or outside) of both sidebars in the UI so they match the prefs.
  // If placement of one/both affected sidebars is open, closes then reopens the affected bar(s) with the new placement.
  func updateSidebarPlacements() {
    animationPipeline.submitInstantTask { [self] in
      let oldLayout = currentLayout
      let leadingSidebar = oldLayout.leadingSidebar.clone(placement: Preference.enum(for: .leadingSidebarPlacement))
      let trailingSidebar = oldLayout.trailingSidebar.clone(placement: Preference.enum(for: .trailingSidebarPlacement))

      guard oldLayout.leadingSidebarPlacement != leadingSidebar.placement ||
              oldLayout.trailingSidebarPlacement != trailingSidebar.placement else {
        return
      }

      let newLayoutSpec = oldLayout.spec.clone(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar)
      buildLayoutTransition(named: "UpdateSidebarPlacements", from: oldLayout, to: newLayoutSpec, thenRun: true)
    }
  }

  /// Hides all visible sidebars
  func hideAllSidebars(animate: Bool = true) {
    Logger.log("Hiding all sidebars", level: .verbose, subsystem: player.subsystem)

    animationPipeline.submitInstantTask { [self] in
      let oldLayout = currentLayout
      let newLayoutSpec = oldLayout.spec.withSidebarsHidden()
      let transition = buildLayoutTransition(named: "HideAllSidebars", from: oldLayout, to: newLayoutSpec, totalEndingDuration: 0)

      if animate {
        animationPipeline.submit(transition.tasks)
      } else {
        IINAAnimation.disableAnimation{
          animationPipeline.submit(transition.tasks)
        }
      }
    }
  }

  /// Shows or hides visibility of given `tab`. If the affected sidebar is showing the wrong `tabGroup`, it will be first be
  /// hidden/closed and then shown again the the correct `tabGroup` & `tab`. Will do nothing if already showing the given `tab`.
  private func changeVisibility(forTab tab: Sidebar.Tab, to shouldShow: Bool) {
    guard !isInInteractiveMode, currentLayout.canShowSidebars else { return }
    log.verbose("Changing visibility of sidebar for tab \(tab.name.quoted) to: \(shouldShow ? "SHOW" : "HIDE")")

    let newVisibilty: Sidebar.Visibility = shouldShow ? .show(tabToShow: tab) : .hide
    let oldLayout = currentLayout

    var leadingSidebar: Sidebar
    var trailingSidebar: Sidebar = oldLayout.trailingSidebar
    if oldLayout.leadingSidebar.tabGroups.contains(tab.group) {  // Leading sidebar
      let isShown = oldLayout.leadingSidebar.isVisible
      if shouldShow != isShown {
        // good
      } else if isShown, let visibleTabGroup = oldLayout.leadingSidebar.visibleTabGroup {
        if visibleTabGroup == tab.group {
          // Already showing the tab group. Just need to change current tab in group
          switchToTabInTabGroup(tab: tab)
          return
        }
        // Otherwise need to change tab group. Drop through.
      } else {
        // Drop request if already animating
        log.verbose("Skipping \(shouldShow ? "SHOW" : "HIDE") for \(tab.name.quoted) because leadingSidebar isShown=\(isShown.yn)")
        return
      }
      leadingSidebar = oldLayout.leadingSidebar.clone(visibility: newVisibilty)
      trailingSidebar = oldLayout.trailingSidebar
    } else if oldLayout.trailingSidebar.tabGroups.contains(tab.group) {  // Trailing sidebar
      let isShown = oldLayout.trailingSidebar.isVisible
      if shouldShow != isShown {
        // good
      } else if isShown, let visibleTabGroup = oldLayout.trailingSidebar.visibleTabGroup {
        if visibleTabGroup == tab.group {
          // Already showing the tab group. Just need to change current tab in group
          switchToTabInTabGroup(tab: tab)
          return
        }
        // Otherwise need to change tab group. Drop through.
      } else {
        // Drop request if already animating or already in desired state
        log.verbose("Skipping \(shouldShow ? "SHOW" : "HIDE") for \(tab.name.quoted) because trailingSidebar isShown=\(isShown.yn)")
        return
      }
      leadingSidebar = oldLayout.leadingSidebar
      trailingSidebar = oldLayout.trailingSidebar.clone(visibility: newVisibilty)
    } else {
      // Should never get here
      log.error("Internal error: no sidebar found for tab group \(tab.group)!")
      return
    }

    log.verbose("Transitioning to layout with \(leadingSidebar.locationID)=\(leadingSidebar.visibility) \(trailingSidebar.locationID)=\(trailingSidebar.visibility)")
    let newLayoutSpec = oldLayout.spec.clone(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar)
    buildLayoutTransition(named: "\(shouldShow ? "Show" : "Hide")Sidebar", from: oldLayout, to: newLayoutSpec, thenRun: true)
  }

  /// Do not call directly. Will be called by `LayoutTransition` via animation tasks.
  func animateShowOrHideSidebars(transition: LayoutTransition,
                                 layout: LayoutState,
                                 setLeadingTo leadingGoal: Sidebar.Visibility? = nil,
                                 setTrailingTo trailingGoal: Sidebar.Visibility? = nil,
                                 ΔWindowWidth: CGFloat) {

    guard leadingGoal != nil || trailingGoal != nil else { return }

    let leadingSidebar = layout.leadingSidebar
    let trailingSidebar = layout.trailingSidebar

    if let goal = leadingGoal {
      log.verbose("[\(transition.name)] Setting leadingSidebar visibility to \(goal)")
      var shouldShow = false
      let sidebarWidth: CGFloat
      switch goal {
      case .show(let tabToShow):
        sidebarWidth = tabToShow.group.width(using: layout.spec.moreSidebarState)
        shouldShow = true
      case .hide:
        if let lastVisibleTab = leadingSidebar.lastVisibleTab {
          sidebarWidth = lastVisibleTab.group.width(using: layout.spec.moreSidebarState)
        } else {
          log.error("[\(transition.name)] Failed to find lastVisibleTab for leadingSidebar")
          sidebarWidth = 0
        }
      }
      updateLeadingSidebarWidthConstraints(to: sidebarWidth, visible: shouldShow, placement: leadingSidebar.placement,
                                           ΔWindowWidth: ΔWindowWidth)
      if leadingSidebar.placement == .outsideViewport {
        leadingSidebarTrailingBorder.isHidden = !shouldShow
      }
    }

    if let goal = trailingGoal {
      log.verbose("[\(transition.name)] Setting trailingSidebar visibility to \(goal)")
      var shouldShow = false
      let sidebarWidth: CGFloat
      switch goal {
      case .show(let tabToShow):
        sidebarWidth = tabToShow.group.width(using: layout.spec.moreSidebarState)
        shouldShow = true
      case .hide:
        if let lastVisibleTab = trailingSidebar.lastVisibleTab {
          sidebarWidth = lastVisibleTab.group.width(using: layout.spec.moreSidebarState)
        } else {
          log.error("[\(transition.name)] Failed to find lastVisibleTab for trailingSidebar")
          sidebarWidth = 0
        }
      }
      updateTrailingSidebarWidthConstraints(to: sidebarWidth, visible: shouldShow, placement: trailingSidebar.placement,
                                            ΔWindowWidth: ΔWindowWidth)
      if trailingSidebar.placement == .outsideViewport {
        trailingSidebarLeadingBorder.isHidden = !shouldShow
      }
    }
  }

  /// Executed prior to opening `leadingSidebar` to the given tab.
  /// Do not call directly. Will be called by `LayoutTransition` via animation tasks.
  func prepareLayoutForOpening(leadingSidebar: Sidebar, parentLayout: LayoutState, ΔWindowWidth: CGFloat) {
    guard let window = window else { return }
    let tabToShow: Sidebar.Tab = leadingSidebar.visibleTab!

    // - Remove old:
    for constraint in [viewportLeadingOffsetFromLeadingSidebarTrailingConstraint,
                       viewportLeadingOffsetFromLeadingSidebarLeadingConstraint,
                       viewportLeadingToLeadingSidebarCropTrailingConstraint] {
      if let constraint = constraint {
        window.contentView?.removeConstraint(constraint)
      }
    }

    for subview in leadingSidebarView.subviews {
      // remove cropView without keeping a reference to it
      if subview != leadingSidebarTrailingBorder {
        subview.removeFromSuperview()
      }
    }

    // - Add new:
    let sidebarWidth = tabToShow.group.width(using: parentLayout.spec.moreSidebarState)
    let tabContainerView: NSView

    if leadingSidebar.placement == .insideViewport {
      tabContainerView = leadingSidebarView
    } else {
      assert(leadingSidebar.placement == .outsideViewport)
      let cropView = NSView()
      cropView.identifier = .init("leadingSidebarCropView")
      leadingSidebarView.addSubview(cropView, positioned: .below, relativeTo: leadingSidebarTrailingBorder)
      cropView.translatesAutoresizingMaskIntoConstraints = false
      // Cling to superview for all sides but trailing:
      cropView.leadingAnchor.constraint(equalTo: leadingSidebarView.leadingAnchor).isActive = true
      cropView.topAnchor.constraint(equalTo: leadingSidebarView.topAnchor).isActive = true
      cropView.bottomAnchor.constraint(equalTo: leadingSidebarView.bottomAnchor).isActive = true
      tabContainerView = cropView

      // extra constraint for cropView:
      viewportLeadingToLeadingSidebarCropTrailingConstraint = viewportView.leadingAnchor.constraint(
        equalTo: leadingSidebarView.trailingAnchor, constant: 0)
      viewportLeadingToLeadingSidebarCropTrailingConstraint.isActive = true
    }

    let coefficients = getLeadingSidebarWidthCoefficients(visible: false, placement: leadingSidebar.placement, ΔWindowWidth: ΔWindowWidth)

    viewportLeadingOffsetFromLeadingSidebarLeadingConstraint = viewportView.leadingAnchor.constraint(
      equalTo: tabContainerView.leadingAnchor, constant: coefficients.0 * sidebarWidth)
    viewportLeadingOffsetFromLeadingSidebarLeadingConstraint.isActive = true

    viewportLeadingOffsetFromLeadingSidebarTrailingConstraint = viewportView.leadingAnchor.constraint(
      equalTo: tabContainerView.trailingAnchor, constant: coefficients.1 * sidebarWidth)
    viewportLeadingOffsetFromLeadingSidebarTrailingConstraint.isActive = true

    prepareRemainingLayoutForOpening(sidebar: leadingSidebar, sidebarView: leadingSidebarView, tabContainerView: tabContainerView, tab: tabToShow)
  }

  /// Executed prior to opening `trailingSidebar` to the given tab.
  /// Do not call directly. Will be called by `LayoutTransition` via animation tasks.
  func prepareLayoutForOpening(trailingSidebar: Sidebar, parentLayout: LayoutState, ΔWindowWidth: CGFloat) {
    guard let window = window else { return }
    let tabToShow: Sidebar.Tab = trailingSidebar.visibleTab!

    // - Remove old:
    for constraint in [viewportTrailingOffsetFromTrailingSidebarLeadingConstraint,
                       viewportTrailingOffsetFromTrailingSidebarTrailingConstraint,
                       viewportTrailingToTrailingSidebarCropLeadingConstraint] {
      if let constraint = constraint {
        window.contentView?.removeConstraint(constraint)
      }
    }

    for subview in trailingSidebarView.subviews {
      // remove cropView without keeping a reference to it
      if subview != trailingSidebarLeadingBorder {
        subview.removeFromSuperview()
      }
    }

    // - Add new:
    let sidebarWidth = tabToShow.group.width(using: parentLayout.spec.moreSidebarState)
    let tabContainerView: NSView

    if trailingSidebar.placement == .insideViewport {
      tabContainerView = trailingSidebarView
    } else {
      assert(trailingSidebar.placement == .outsideViewport)
      let cropView = NSView()
      cropView.identifier = .init("trailingSidebarCropView")
      trailingSidebarView.addSubview(cropView, positioned: .below, relativeTo: trailingSidebarLeadingBorder)
      cropView.translatesAutoresizingMaskIntoConstraints = false
      // Cling to superview for all sides but leading:
      cropView.trailingAnchor.constraint(equalTo: trailingSidebarView.trailingAnchor).isActive = true
      cropView.topAnchor.constraint(equalTo: trailingSidebarView.topAnchor).isActive = true
      cropView.bottomAnchor.constraint(equalTo: trailingSidebarView.bottomAnchor).isActive = true
      tabContainerView = cropView

      // extra constraint for cropView:
      viewportTrailingToTrailingSidebarCropLeadingConstraint = viewportView.trailingAnchor.constraint(
        equalTo: trailingSidebarView.leadingAnchor, constant: 0)
      viewportTrailingToTrailingSidebarCropLeadingConstraint.isActive = true
    }

    let coefficients = getTrailingSidebarWidthCoefficients(visible: false, placement: trailingSidebar.placement, ΔWindowWidth: ΔWindowWidth)

    viewportTrailingOffsetFromTrailingSidebarLeadingConstraint = viewportView.trailingAnchor.constraint(
      equalTo: tabContainerView.leadingAnchor, constant: coefficients.0 * sidebarWidth)
    viewportTrailingOffsetFromTrailingSidebarLeadingConstraint.isActive = true

    viewportTrailingOffsetFromTrailingSidebarTrailingConstraint = viewportView.trailingAnchor.constraint(
      equalTo: tabContainerView.trailingAnchor, constant: coefficients.1 * sidebarWidth)
    viewportTrailingOffsetFromTrailingSidebarTrailingConstraint.isActive = true

    prepareRemainingLayoutForOpening(sidebar: trailingSidebar, sidebarView: trailingSidebarView, tabContainerView: tabContainerView, tab: tabToShow)
  }

  /// Prepares those layout components which are generic for either `Sidebar`.
  /// Executed prior to opening the given `Sidebar` with corresponding `sidebarView`
  private func prepareRemainingLayoutForOpening(sidebar: Sidebar, sidebarView: NSView, tabContainerView: NSView, tab: Sidebar.Tab) {
    log.verbose("ChangeVisibility pre-animation, show \(sidebar.locationID), \(tab.name.quoted) tab")

    let viewController: NSViewController
    switch tab.group {
    case .playlist:
      viewController = playlistView
    case .settings:
      viewController = quickSettingView
    case .plugins:
      viewController = pluginView
    }
    let tabGroupView = viewController.view

    tabContainerView.addSubview(tabGroupView)
    tabGroupView.leadingAnchor.constraint(equalTo: tabContainerView.leadingAnchor).isActive = true
    tabGroupView.trailingAnchor.constraint(equalTo: tabContainerView.trailingAnchor).isActive = true
    tabGroupView.topAnchor.constraint(equalTo: tabContainerView.topAnchor).isActive = true
    tabGroupView.bottomAnchor.constraint(equalTo: tabContainerView.bottomAnchor).isActive = true

    sidebarView.isHidden = false

    // Update blending mode instantaneously. It doesn't animate well
    updateSidebarBlendingMode(sidebar.locationID, layout: self.currentLayout)

    // Make it the active tab in its parent tab group:
    switchToTabInTabGroup(tab: tab)

    sidebarView.needsUpdateConstraints = true
  }

  /**
   For opening/closing `leadingSidebar` via constraints, multiply each times the sidebar width
   Correesponding to:
   (`viewportLeadingOffsetFromLeadingSidebarLeadingConstraint`,
   `viewportLeadingOffsetFromLeadingSidebarTrailingConstraint`,
   `viewportLeadingOffsetFromContentViewLeadingConstraint`)
   */
  private func getLeadingSidebarWidthCoefficients(visible: Bool, placement: Preference.PanelPlacement,
                                                  ΔWindowWidth: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    switch placement {
    case .insideViewport:
      if visible {
        return (0, -1, 0)
      } else {
        return (1, 0, 0)
      }
    case .outsideViewport:
      if visible {
        return (1, 0, 1)
      } else {
        if ΔWindowWidth == 0 {
          return (1, 0, 0)
        } else {
          return (0, -1, 0)
        }
      }
    }
  }

  private func updateLeadingSidebarWidthConstraints(to newWidth: CGFloat, visible: Bool, placement: Preference.PanelPlacement,
                                         ΔWindowWidth: CGFloat) {
    log.verbose("\(visible ? "Showing" : "Hiding") leadingSidebar, width=\(newWidth) placement=\(placement), ΔWindowWidth=\(ΔWindowWidth)")

    let coefficients = getLeadingSidebarWidthCoefficients(visible: visible, placement: placement, ΔWindowWidth: ΔWindowWidth)
    viewportLeadingOffsetFromLeadingSidebarLeadingConstraint.animateToConstant(coefficients.0 * newWidth)
    viewportLeadingOffsetFromLeadingSidebarTrailingConstraint.animateToConstant(coefficients.1 * newWidth)
    viewportLeadingOffsetFromContentViewLeadingConstraint.animateToConstant(coefficients.2 * newWidth)
  }

  /**
   For opening/closing `trailingSidebar` via constraints, multiply each times the sidebar width
   Correesponding to:
   (`viewportTrailingOffsetFromTrailingSidebarLeadingConstraint`,
   `viewportTrailingOffsetFromTrailingSidebarTrailingConstraint`,
   `viewportTrailingOffsetFromContentViewTrailingConstraint`)
   */
  private func getTrailingSidebarWidthCoefficients(visible: Bool, placement: Preference.PanelPlacement,
                                                   ΔWindowWidth: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    switch placement {
    case .insideViewport:
      if visible {
        return (1, 0, 0)
      } else {
        return (0, -1, 0)
      }
    case .outsideViewport:
      if visible {
        return (0, -1, -1)
      } else {
        if ΔWindowWidth == 0 {
          return (0, -1, 0)
        } else {
          return (1, 0, 0)
        }
      }
    }
  }

  private func updateTrailingSidebarWidthConstraints(to newWidth: CGFloat, visible: Bool,
                                                     placement: Preference.PanelPlacement,
                                                     ΔWindowWidth: CGFloat) {
    log.verbose("\(visible ? "Showing" : "Hiding") trailingSidebar, width=\(newWidth) placement=\(placement), ΔWindowWidth=\(ΔWindowWidth)")
    let coefficients = getTrailingSidebarWidthCoefficients(visible: visible, placement: placement, ΔWindowWidth: ΔWindowWidth)
    viewportTrailingOffsetFromTrailingSidebarLeadingConstraint.animateToConstant(coefficients.0 * newWidth)
    viewportTrailingOffsetFromTrailingSidebarTrailingConstraint.animateToConstant(coefficients.1 * newWidth)
    viewportTrailingOffsetFromContentViewTrailingConstraint.animateToConstant(coefficients.2 * newWidth)
  }

  // MARK: - Changing tabs

  /// Assuming the correct sidebar is already showing, & it is showing the correct tab group, switches to the given tab in the same tab group.
  func switchToTabInTabGroup(tab: Sidebar.Tab) {
    assert((getConfiguredSidebar(forTabGroup: tab.group)!.visibleTabGroup == tab.group),
           "switchToTabInTabGroup: expected TabGroup \(tab.group) to be visible")

    // Make it the active tab in its parent tab group (can do this whether or not it's shown):
    switch tab.group {
    case .playlist:
      log.verbose("Switching to tab \(tab.name.quoted) in playlistView")
      playlistView.pleaseSwitchToTab(tab)
    case .settings:
      log.verbose("Switching to tab \(tab.name.quoted) in quickSettingView")
      quickSettingView.pleaseSwitchToTab(tab)
    case .plugins:
      guard case .plugin(let pluginID) = tab else {
        log.error("Cannot switch to tab \(tab.name.quoted): bad plugin tab object!")
        return
      }
      log.verbose("Switching to tab \(pluginID.quoted) in pluginView")
      pluginView.pleaseSwitchToTab(pluginID)
    }
  }

  // This is so that sidebar controllers can notify when they changed tabs in their tab groups, so that
  // the tracking information here can be updated.
  func didChangeTab(to tab: Sidebar.Tab) {
    log.verbose("Changing to tab: \(tab.name.quoted)")

    // Try to avoid race conditions if possible
    animationPipeline.submitInstantTask { [self] in
      let newVisibility = Sidebar.Visibility.show(tabToShow: tab)
      let layout = currentLayout
      var leadingSidebar: Sidebar? = nil
      var trailingSidebar: Sidebar? = nil
      if layout.leadingSidebar.tabGroups.contains(tab.group) {
        leadingSidebar = layout.leadingSidebar.clone(visibility: newVisibility)
      } else if layout.trailingSidebar.tabGroups.contains(tab.group) {
        trailingSidebar = layout.trailingSidebar.clone(visibility: newVisibility)
      }
      // Need to update current layout, but no need for animation
      let newLayoutSpec = layout.spec.clone(leadingSidebar: leadingSidebar, trailingSidebar: trailingSidebar)
      let outputLayout = LayoutState.buildFrom(newLayoutSpec)
      currentLayout = outputLayout
      player.saveState()
    }
  }

  func getConfiguredSidebar(forTabGroup tabGroup: Sidebar.TabGroup) -> Sidebar? {
    for sidebar in [currentLayout.leadingSidebar, currentLayout.trailingSidebar] {
      if sidebar.tabGroups.contains(tabGroup) {
        return sidebar
      }
    }
    log.error("No sidebar found for tab group \(tabGroup.rawValue.quoted)!")
    return nil
  }

  // If location of tab group changed to another sidebar (in user prefs), check if it is showing, and if so, hide it & show it on the other side
  func moveTabGroup(_ tabGroup: Sidebar.TabGroup, toSidebarLocation newLocationID: Preference.SidebarLocation) {
    animationPipeline.submitInstantTask { [self] in
      guard let currentLocationID = getConfiguredSidebar(forTabGroup: tabGroup)?.locationID else { return }
      guard currentLocationID != newLocationID else { return }

      let oldLayout = currentLayout
      let leadingSidebar = oldLayout.leadingSidebar
      var newLeadingTabGroups = leadingSidebar.tabGroups
      var newLeadingSidebarVisibility: Sidebar.Visibility = leadingSidebar.visibility
      let trailingSidebar = oldLayout.trailingSidebar
      var newTrailingTabGroups = trailingSidebar.tabGroups
      var newTraillingSidebarVisibility: Sidebar.Visibility = trailingSidebar.visibility

      if newLocationID == .leadingSidebar {
        newLeadingTabGroups.insert(tabGroup)
        newTrailingTabGroups.remove(tabGroup)
        if trailingSidebar.visibleTabGroup == tabGroup && !leadingSidebar.isVisible {
          newTraillingSidebarVisibility = .hide
          newLeadingSidebarVisibility = trailingSidebar.visibility
        }
      }

      if newLocationID == .trailingSidebar {
        newTrailingTabGroups.insert(tabGroup)
        newLeadingTabGroups.remove(tabGroup)
        if leadingSidebar.visibleTabGroup == tabGroup && !trailingSidebar.isVisible {
          newLeadingSidebarVisibility = .hide
          newTraillingSidebarVisibility = leadingSidebar.visibility
        }
      }

      let newLayoutSpec = oldLayout.spec.clone(
        leadingSidebar: leadingSidebar.clone(tabGroups: newLeadingTabGroups, visibility: newLeadingSidebarVisibility),
        trailingSidebar: trailingSidebar.clone(tabGroups: newTrailingTabGroups, visibility: newTraillingSidebarVisibility))
      buildLayoutTransition(named: "MoveTabGroupToSidebar", from: oldLayout, to: newLayoutSpec, thenRun: true)
    }
  }

  func isTabGroupVisible(_ tabGroup: Sidebar.TabGroup) -> Bool {
    return getConfiguredSidebar(forTabGroup: tabGroup)?.visibleTabGroup == tabGroup
  }

  // MARK: - Various functions

  func updateSidebarBlendingMode(_ sidebarID: Preference.SidebarLocation, layout: LayoutState) {
    switch sidebarID {
    case .leadingSidebar:
      // Full screen + "behindWindow" doesn't blend properly and looks ugly
      if layout.leadingSidebarPlacement == .insideViewport || layout.isFullScreen {
        leadingSidebarView.blendingMode = .withinWindow
      } else {
        leadingSidebarView.blendingMode = .behindWindow
      }
    case .trailingSidebar:
      if layout.trailingSidebarPlacement == .insideViewport || layout.isFullScreen {
        trailingSidebarView.blendingMode = .withinWindow
      } else {
        trailingSidebarView.blendingMode = .behindWindow
      }
    }
  }

  /// Make sure this is called AFTER `windowController.setupTitleBarAndOSC()` has updated its variables
  func updateSidebarVerticalConstraints(tabHeight: CGFloat, downshift: CGFloat) {
    log.verbose("Updating sidebars, downshift: \(downshift), tabHeight: \(tabHeight)")
    quickSettingView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
    playlistView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
    pluginView.setVerticalConstraints(downshift: downshift, tabHeight: tabHeight)
  }

  // MARK: - Sidebar resize via drag

  func isMousePosWithinLeadingSidebarResizeRect(mousePositionInWindow: NSPoint) -> Bool {
    if currentLayout.leadingSidebar.visibleTabGroup == .playlist {
      let sf = leadingSidebarView.frame

      let dragRectCenterX = videoView.userInterfaceLayoutDirection == .rightToLeft ?
      sf.origin.x - Constants.Sidebar.resizeActivationRadius : sf.origin.x + sf.width

      // TODO: need to find way to resize from inside of sidebar
      let activationRect = NSRect(x: dragRectCenterX,
                                  y: sf.origin.y,
                                  width: Constants.Sidebar.resizeActivationRadius,
                                  height: sf.height)
      if NSPointInRect(mousePositionInWindow, activationRect) {
        return true
      }
    }
    return false
  }

  func isMousePosWithinTrailingSidebarResizeRect(mousePositionInWindow: NSPoint) -> Bool {
    if currentLayout.trailingSidebar.visibleTabGroup == .playlist {
      let sf = trailingSidebarView.frame
      let dragRectCenterX = videoView.userInterfaceLayoutDirection == .rightToLeft ?
      sf.origin.x + sf.width + Constants.Sidebar.resizeActivationRadius : sf.origin.x

      // TODO: need to find way to resize from inside of sidebar
      let activationRect = NSRect(x: dragRectCenterX - Constants.Sidebar.resizeActivationRadius,
                                  y: sf.origin.y,
                                  width: Constants.Sidebar.resizeActivationRadius,
                                  height: sf.height)
      if NSPointInRect(mousePositionInWindow, activationRect) {
        return true
      }
    }
    return false
  }

  /// Returns `true` if mouse was within sidebar resize rect, and resize was started.
  func startResizingSidebar(with event: NSEvent) -> Bool {
    if isMousePosWithinLeadingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) {
      log.verbose("User started resize of leading sidebar")
      leadingSidebarIsResizing = true
      if currentLayout.isWindowed {
        // Update to latest frame in case window has moved
        windowedModeGeo = windowedGeoForCurrentFrame()
      }
      return true
    } else if isMousePosWithinTrailingSidebarResizeRect(mousePositionInWindow: event.locationInWindow) {
      Logger.log("User started resize of trailing sidebar", level: .verbose, subsystem: player.subsystem)
      trailingSidebarIsResizing = true
      if currentLayout.isWindowed {
        windowedModeGeo = windowedGeoForCurrentFrame()
      }
      return true
    }
    return false
  }

  func resizeSidebar(with dragEvent: NSEvent) -> CursorType {
    guard leadingSidebarIsResizing || trailingSidebarIsResizing else { return .normalCursor }

    let oldGeo: PWinGeometry
    switch currentLayout.mode {
    case .windowedNormal:
      oldGeo = windowedModeGeo
    case .fullScreenNormal:
      oldGeo = currentLayout.buildFullScreenGeometry(inScreenID: windowedModeGeo.screenID, video: geo.video)
    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      Logger.fatal("ResizeSidebar: current mode unexpected: \(currentLayout.mode)")
    }

    return IINAAnimation.disableAnimation { [self] in
      videoView.videoLayer.enterAsynchronousMode()
      
      let (result, newGeo): (CursorType, PWinGeometry?)

      if leadingSidebarIsResizing {
        let newWidth = (videoView.userInterfaceLayoutDirection == .rightToLeft ?
        window!.frame.width - dragEvent.locationInWindow.x : dragEvent.locationInWindow.x) - 2
        (result, newGeo) = resizeLeadingSidebar(from: oldGeo, desiredWidth: newWidth)
      } else if trailingSidebarIsResizing {
        let newWidth = (videoView.userInterfaceLayoutDirection == .rightToLeft ?
        dragEvent.locationInWindow.x : window!.frame.width - dragEvent.locationInWindow.x) - 2
        (result, newGeo) = resizeTrailingSidebar(from: oldGeo, desiredWidth: newWidth)
      } else {
        // should be already handled above
        return .normalCursor
      }

      if let newGeo {
        resizeWindowImmediately(using: newGeo)

        switch currentLayout.mode {
        case .windowedNormal:
          // Need to update this for future operations
          windowedModeGeo = newGeo
        case .fullScreenNormal:
          break
        case .musicMode, .windowedInteractive, .fullScreenInteractive:
          Logger.fatal("ResizeSidebar: current mode unexpected: \(currentLayout.mode)")
        }

        // Update currentLayout with new playlist width
        let oldSidebarState = currentLayout.spec.moreSidebarState
        let newSidebarState = Sidebar.SidebarMiscState(playlistSidebarWidth: Preference.integer(for: .playlistWidth),
                                                       selectedSubSegment: oldSidebarState.selectedSubSegment,
                                                       selectedPluginTabID: oldSidebarState.selectedPluginTabID)
        let newSpec = currentLayout.spec.clone(moreSidebarState: newSidebarState)
        currentLayout = LayoutState.buildFrom(newSpec)
      }
      return result
    }
  }

  private func resizeLeadingSidebar(from oldGeo: PWinGeometry, desiredWidth: CGFloat) -> (CursorType, PWinGeometry?) {
    let newPlaylistWidth: CGFloat
    let newGeo: PWinGeometry
    let currentLayout = currentLayout

    let desiredPlaylistWidth = clampPlaylistWidth(desiredWidth)

    if currentLayout.leadingSidebar.placement == .insideViewport {
      // Stop sidebar from resizing when the viewportView is not wide enough to fit it.
      let negativeDeficit = min(0, currentLayout.spec.getExcessSpaceBetweenInsideSidebars(leadingSidebarWidth: desiredPlaylistWidth, in: oldGeo.viewportSize.width))
      newPlaylistWidth = desiredPlaylistWidth + negativeDeficit
      if newPlaylistWidth < Constants.Sidebar.minPlaylistWidth {
        // should not happen in theory, because playlist shouldn't have been shown when resize started
        log.error("Cannot resize playlist: desired width \(desiredPlaylistWidth) is below minimum!")
        return (.resized_AtLeftMin, nil)
      }
    } else {  /// `placement == .outsideViewport`
      newPlaylistWidth = desiredPlaylistWidth
    }

    /// Updating the sidebar width when it is in "outside" mode will cause the video width to
    /// grow or shrink, which will require its height to change according to its aspectRatio.
    if currentLayout.leadingSidebar.placement == .outsideViewport {
      let playlistWidthDifference = newPlaylistWidth - oldGeo.outsideBars.leading
      let viewportSize = oldGeo.viewportSize
      let newViewportWidth = viewportSize.width - playlistWidthDifference
      let resizedPlaylistGeo = oldGeo.clone(outsideBars: oldGeo.outsideBars.clone(leading: newPlaylistWidth))

      /// If `lockViewportToVideoSize` is `true`, it is necessary to resize the window's height to
      /// accomodate the change in video height.
      if Preference.bool(for: .lockViewportToVideoSize) {
        let desiredViewportSize = NSSize(width: newViewportWidth, height: round(newViewportWidth / viewportSize.aspect))
        newGeo = resizedPlaylistGeo.scalingViewport(to: desiredViewportSize)
      } else {
        /// If `lockViewportToVideoSize` is `false`, window size won't change.
        /// But call `refit` to recalculate videoSize or other internal vars
        newGeo = resizedPlaylistGeo.refitted()
      }
    } else {  /// `.insideViewport`: needs to refit in case window is so small that the viewport is larger than the video
      let insideBarsNew = oldGeo.insideBars.clone(leading: newPlaylistWidth)
      let resizedPlaylistGeo = oldGeo.clone(insideBars: insideBarsNew)
      newGeo = resizedPlaylistGeo.refitted()
    }

    Preference.set(Int(newPlaylistWidth), for: .playlistWidth)

    updateLeadingSidebarWidthConstraints(to: newPlaylistWidth, visible: true,
                                         placement: currentLayout.leadingSidebarPlacement,
                                         ΔWindowWidth: newGeo.windowFrame.width - oldGeo.windowFrame.width)

    if (newPlaylistWidth < desiredPlaylistWidth) || (newPlaylistWidth == Constants.Sidebar.maxPlaylistWidth) {
      return (.resized_AtRightMax, nil)
    } else if (desiredPlaylistWidth > newPlaylistWidth) || (newPlaylistWidth == Constants.Sidebar.minPlaylistWidth) {
      return (.resized_AtLeftMin, nil)
    }
    return (.resizing_BothDirections, newGeo)
  }

  private func resizeTrailingSidebar(from oldGeo: PWinGeometry, desiredWidth: CGFloat) -> (CursorType, PWinGeometry?) {
    let newPlaylistWidth: CGFloat
    let newGeo: PWinGeometry
    let currentLayout = currentLayout
    let viewportSize = oldGeo.viewportSize
    let desiredPlaylistWidth = clampPlaylistWidth(desiredWidth)

    if currentLayout.trailingSidebar.placement == .insideViewport {
      let negativeDeficit = min(0, currentLayout.spec.getExcessSpaceBetweenInsideSidebars(trailingSidebarWidth: desiredPlaylistWidth, in: viewportSize.width))

      newPlaylistWidth = desiredPlaylistWidth + negativeDeficit
      if newPlaylistWidth < Constants.Sidebar.minPlaylistWidth {
        log.error("Cannot resize playlist: desired width \(desiredPlaylistWidth) is below minimum!")
        return (.resized_AtRightMax, nil)
      }
    } else {  /// `placement == .outsideViewport`
      newPlaylistWidth = desiredPlaylistWidth
    }

    /// See comments in `resizeLeadingSidebar()` above
    if currentLayout.trailingSidebar.placement == .outsideViewport {
      let playlistWidthDifference = newPlaylistWidth - oldGeo.outsideBars.trailing
      let newViewportWidth = viewportSize.width - playlistWidthDifference
      let resizedPlaylistGeo = oldGeo.clone(outsideBars: oldGeo.outsideBars.clone(trailing: newPlaylistWidth))

      if Preference.bool(for: .lockViewportToVideoSize) {
        let desiredViewportSize = NSSize(width: newViewportWidth, height: round(newViewportWidth / viewportSize.aspect))
        newGeo = resizedPlaylistGeo.scalingViewport(to: desiredViewportSize)
      } else {
        newGeo = resizedPlaylistGeo.refitted()
      }
    } else {  /// `.insideViewport`
      let resizedPlaylistGeo = oldGeo.clone(insideBars: oldGeo.insideBars.clone(trailing: newPlaylistWidth))
      newGeo = resizedPlaylistGeo.refitted()
    }

    Preference.set(Int(newPlaylistWidth), for: .playlistWidth)
    // Update layout also. Do this inside the animation pipeline to prevent races
    animationPipeline.submitInstantTask{ [self] in
      let prevLayout = self.currentLayout
      let moreSidebarState = Sidebar.SidebarMiscState(playlistSidebarWidth: Int(newPlaylistWidth),
                                                      selectedSubSegment: prevLayout.spec.moreSidebarState.selectedSubSegment,
                                                      selectedPluginTabID: prevLayout.spec.moreSidebarState.selectedPluginTabID)
      self.currentLayout = LayoutState.buildFrom(prevLayout.spec.clone(moreSidebarState: moreSidebarState))
    }

    updateTrailingSidebarWidthConstraints(to: newPlaylistWidth, visible: true,
                                          placement: currentLayout.trailingSidebarPlacement,
                                          ΔWindowWidth: newGeo.windowFrame.width - oldGeo.windowFrame.width)

    if (newPlaylistWidth < desiredPlaylistWidth) || (newPlaylistWidth == Constants.Sidebar.maxPlaylistWidth) {
      return (.resized_AtLeftMin, nil)
    } else if (desiredPlaylistWidth > newPlaylistWidth) || (newPlaylistWidth == Constants.Sidebar.minPlaylistWidth) {
      return (.resized_AtRightMax, nil)
    }
    return (.resizing_BothDirections, newGeo)
  }

  func finishResizingSidebar(with dragEvent: NSEvent) -> Bool {
    let sidebarResizeResult = resizeSidebar(with: dragEvent)
    guard sidebarResizeResult != .normalCursor else { return false }

    if leadingSidebarIsResizing {
      // if it's a mouseup after resizing sidebar
      leadingSidebarIsResizing = false
      let width = currentLayout.spec.moreSidebarState.playlistSidebarWidth
      log.verbose("Finished resize of leading sidebar; playlist is now \(width)")
    } else if trailingSidebarIsResizing {
      // if it's a mouseup after resizing sidebar
      trailingSidebarIsResizing = false
      let width = currentLayout.spec.moreSidebarState.playlistSidebarWidth
      log.verbose("Finished resize of trailing sidebar; playlist is now \(width)")
    }

    // Call this to refresh cursor
    mouseInWindow()
    return true
  }

  // MARK: - Other mouse events

  func hideSidebarsOnClick() -> Bool {
    let oldLayout = currentLayout
    let hideLeading = oldLayout.leadingSidebar.isVisible && Preference.bool(for: .hideLeadingSidebarOnClick)
    let hideTrailing = oldLayout.trailingSidebar.isVisible && Preference.bool(for: .hideTrailingSidebarOnClick)

    if hideLeading || hideTrailing {
      animationPipeline.submitInstantTask { [self] in
        let newLayoutSpec = oldLayout.spec.clone(leadingSidebar: hideLeading ? oldLayout.leadingSidebar.clone(visibility: .hide) : nil,
                                                 trailingSidebar: hideTrailing ? oldLayout.trailingSidebar.clone(visibility: .hide) : nil)
        buildLayoutTransition(named: "HideSidebarsOnClick", from: oldLayout, to: newLayoutSpec, totalEndingDuration: 0, thenRun: true)
      }
      return true
    }
    return false
  }

}

// MARK: - SidebarTabGroupViewController

protocol SidebarTabGroupViewController {
  var windowController: PlayerWindowController! { get }
  var customTabHeight: CGFloat? { get }

  // Implementing classes need to define this
  func setVerticalConstraints(downshift: CGFloat, tabHeight: CGFloat)
}

extension SidebarTabGroupViewController {
  var customTabHeight: CGFloat? { return nil }

  func updateTabActiveStatus(for btn: NSButton, isActive: Bool) {
    btn.contentTintColor = isActive ? .sidebarTabTintActive : .sidebarTabTint
  }

}
