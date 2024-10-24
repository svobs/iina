//
//  PrefUIViewController.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let SizeWidthTag = 0
fileprivate let SizeHeightTag = 1
fileprivate let UnitPointTag = 0
fileprivate let UnitPercentTag = 1
fileprivate let SideLeftTag = 0
fileprivate let SideRightTag = 1
fileprivate let SideTopTag = 0
fileprivate let SideBottomTag = 1
fileprivate let maxToolbarPreviewBarHeight = 34.0

@objcMembers
class PrefUIViewController: PreferenceViewController, PreferenceWindowEmbeddable {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefUIViewController")
  }

  var preferenceTabTitle: String {
    return NSLocalizedString("preference.ui", comment: "UI")
  }

  var preferenceTabImage: NSImage {
    return makeSymbol("macwindow", fallbackImage: "pref_ui")
  }

  static var oscToolbarButtons: [Preference.ToolBarButton] {
    get {
      return (Preference.array(for: .controlBarToolbarButtons) as? [Int] ?? []).compactMap(Preference.ToolBarButton.init(rawValue:))
    }
  }

  override var sectionViews: [NSView] {
    return [sectionWindowView, sectionFullScreenView, sectionAppearanceView, sectionOSCView, sectionSidebarsView, sectionOSDView,
            sectionThumbnailView, sectionPictureInPictureView, sectionAccessibilityView]
  }

  private let toolbarSettingsSheetController = PrefOSCToolbarSettingsSheetController()

  @IBOutlet weak var toolIconSizeSlider: NSSlider!
  @IBOutlet weak var toolIconSpacingSlider: NSSlider!
  @IBOutlet weak var playIconSizeSlider: NSSlider!
  @IBOutlet weak var playIconSpacingSlider: NSSlider!

  @IBOutlet weak var aspectPresetsTokenField: AspectTokenField!
  @IBOutlet weak var cropPresetsTokenField: AspectTokenField!

  @IBOutlet weak var resetAspectPresetsButton: NSButton!
  @IBOutlet weak var resetCropPresetsButton: NSButton!

  @IBOutlet var sectionAppearanceView: NSView!
  @IBOutlet var sectionFullScreenView: NSView!
  @IBOutlet var sectionWindowView: NSView!
  @IBOutlet var sectionOSCView: NSView!
  @IBOutlet var sectionOSDView: NSView!
  @IBOutlet var sectionSidebarsView: NSView!
  @IBOutlet var sectionThumbnailView: NSView!
  @IBOutlet var sectionPictureInPictureView: NSView!
  @IBOutlet var sectionAccessibilityView: NSView!

  @IBOutlet weak var themeMenu: NSMenu!
  @IBOutlet weak var topBarPositionContainerView: NSView!
  @IBOutlet weak var showTopBarTriggerContainerView: NSView!
  @IBOutlet weak var windowPreviewImageView: NSImageView!
  @IBOutlet weak var arrowButtonActionPopUpButton: NSPopUpButton!
  @IBOutlet weak var oscBottomPlacementContainerView: NSView!
  @IBOutlet weak var oscSnapToCenterCheckboxContainerView: NSView!
  @IBOutlet weak var oscHeightStackView: NSStackView!
  @IBOutlet weak var playbackButtonsStackView: NSStackView!
  @IBOutlet weak var toolbarSectionVStackView: NSStackView!
  @IBOutlet weak var toolbarIconDimensionsHStackView: NSStackView!
  @IBOutlet weak var oscToolbarStackView: NSStackView!
  @IBOutlet weak var autoHideAfterCheckBox: NSButton!
  @IBOutlet weak var oscAutoHideTimeoutTextField: NSTextField!
  @IBOutlet weak var hideFadeableViewsOutsideWindowCheckBox: NSButton!

  @IBOutlet weak var leftSidebarLabel: NSTextField!
  @IBOutlet weak var leftSidebarPlacement: NSSegmentedControl!
  @IBOutlet weak var leftSidebarSettingsTabsRadioButton: NSButton!
  @IBOutlet weak var rightSidebarSettingsTabsRadioButton: NSButton!
  @IBOutlet weak var leftSidebarPlaylistTabsRadioButton: NSButton!
  @IBOutlet weak var rightSidebarPlaylistTabsRadioButton: NSButton!
  @IBOutlet weak var leftSidebarShowToggleButton: NSButton!
  @IBOutlet weak var leftSidebarClickToCloseButton: NSButton!
  @IBOutlet weak var rightSidebarLabel: NSTextField!
  @IBOutlet weak var rightSidebarPlacement: NSSegmentedControl!
  @IBOutlet weak var rightSidebarShowToggleButton: NSButton!
  @IBOutlet weak var rightSidebarClickToCloseButton: NSButton!

  @IBOutlet weak var resizeWindowWhenOpeningFileCheckbox: NSButton!
  @IBOutlet weak var resizeWindowTimingPopUpButton: NSPopUpButton!
  @IBOutlet weak var unparsedGeometryLabel: NSTextField!
  @IBOutlet weak var mpvWindowSizeCollapseView: CollapseView!
  @IBOutlet weak var mpvWindowPositionCollapseView: CollapseView!
  @IBOutlet weak var windowSizeCheckBox: NSButton!
  @IBOutlet weak var simpleVideoSizeRadioButton: NSButton!
  @IBOutlet weak var mpvGeometryRadioButton: NSButton!
  @IBOutlet weak var spacer0: NSView!
  @IBOutlet weak var windowSizeTypePopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeValueTextField: NSTextField!
  @IBOutlet weak var windowSizeUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowSizeBox: NSBox!
  @IBOutlet weak var windowPosCheckBox: NSButton!
  @IBOutlet weak var windowPosXOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosXUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosXAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYOffsetTextField: NSTextField!
  @IBOutlet weak var windowPosYUnitPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosYAnchorPopUpButton: NSPopUpButton!
  @IBOutlet weak var windowPosBox: NSBox!

  @IBOutlet weak var currentThumbCacheSizeTextField: NSTextField!

  @IBOutlet weak var pipDoNothing: NSButton!
  @IBOutlet weak var pipHideWindow: NSButton!
  @IBOutlet weak var pipMinimizeWindow: NSButton!

  var oscToolbarStackViewHeightConstraint: NSLayoutConstraint? = nil
  var oscToolbarStackViewWidthConstraint: NSLayoutConstraint? = nil

  private let observedPrefKeys: [Preference.Key] = [
    .enableAdvancedSettings,
    .showTopBarTrigger,
    .topBarPlacement,
    .bottomBarPlacement,
    .enableOSC,
    .oscPosition,
    .themeMaterial,
    .settingsTabGroupLocation,
    .playlistTabGroupLocation,

    .controlBarToolbarButtons,
    .oscBarHeight,
    .oscBarPlaybackIconSize,
    .oscBarPlaybackIconSpacing,
    .oscBarToolbarIconSize,
    .oscBarToolbarIconSpacing,
    .arrowButtonAction,

    .useLegacyWindowedMode,
    .aspectRatioPanelPresets,
    .cropPanelPresets,
  ]

  var disableObserversForOSC = false

  override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    // Set up key-value observing for changes to this view's properties:
    addObserver(self, forKeyPath: #keyPath(view.effectiveAppearance), options: [.old, .new], context: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    ObjcUtils.silenced {
      for key in self.observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }
      UserDefaults.standard.removeObserver(self, forKeyPath: #keyPath(view.effectiveAppearance))
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    updateAspectControlsFromPrefs()
    updateCropControlsFromPrefs()

    let geo = ControlBarGeometry.current
    let hConstraint = oscToolbarStackView.heightAnchor.constraint(equalToConstant: geo.barHeight)
    hConstraint.isActive = true
    oscToolbarStackViewHeightConstraint = hConstraint

    let wConstraint = oscToolbarStackView.widthAnchor.constraint(equalToConstant: geo.totalToolbarWidth)
    wConstraint.priority = .defaultHigh  // avoid conflicting constraints
    wConstraint.isActive = true
    oscToolbarStackViewWidthConstraint = wConstraint

    updateSidebarSection()
    refreshTitleBarAndOSCSection(animate: false)
    updateOSCToolbarPreview()
    updateGeometryUI()
    updatePipBehaviorRelatedControls()

    let removeThemeMenuItemWithTag = { (tag: Int) in
      if let item = self.themeMenu.item(withTag: tag) {
        self.themeMenu.removeItem(item)
      }
    }
    removeThemeMenuItemWithTag(Preference.Theme.mediumLight.rawValue)
    removeThemeMenuItemWithTag(Preference.Theme.ultraDark.rawValue)
  }

  override func viewDidAppear() {
    super.viewDidAppear()

    updateThumbnailCacheStat()
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath, let _ = change else { return }

    switch keyPath {
    case PK.aspectRatioPanelPresets.rawValue:
      updateAspectControlsFromPrefs()
  case PK.cropPanelPresets.rawValue:
      updateCropControlsFromPrefs()
    case PK.showTopBarTrigger.rawValue,
      PK.arrowButtonAction.rawValue,
      PK.enableOSC.rawValue,
      PK.topBarPlacement.rawValue,
      PK.bottomBarPlacement.rawValue,
      PK.oscPosition.rawValue,
      PK.useLegacyWindowedMode.rawValue,
      PK.themeMaterial.rawValue,
      PK.enableAdvancedSettings.rawValue:

      refreshTitleBarAndOSCSection()
      updateGeometryUI()
    case PK.settingsTabGroupLocation.rawValue, PK.playlistTabGroupLocation.rawValue:
      updateSidebarSection()
    case PK.oscBarHeight.rawValue,
      PK.controlBarToolbarButtons.rawValue,
      PK.oscBarPlaybackIconSize.rawValue,
      PK.oscBarPlaybackIconSpacing.rawValue,
      PK.oscBarToolbarIconSize.rawValue,
      PK.oscBarToolbarIconSpacing.rawValue:

      guard !disableObserversForOSC else { return }
      updateOSCToolbarPreview()
    case #keyPath(view.effectiveAppearance):
      if Preference.enum(for: .themeMaterial) == Preference.Theme.system {
        // Refresh image in case dark mode changed
        let ib = PWinPreviewImageBuilder(self.view)
        windowPreviewImageView.image = ib.buildPWinPreviewImage()
      }
    default:
      break
    }
  }

  // MARK: - Sidebars

  private func updateSidebarSection() {
    let settingsTabGroup: Preference.SidebarLocation = Preference.enum(for: .settingsTabGroupLocation)
    let playlistTabGroup: Preference.SidebarLocation = Preference.enum(for: .playlistTabGroupLocation)
    let isUsingLeadingSidebar = settingsTabGroup == .leadingSidebar || playlistTabGroup == .leadingSidebar
    let isUsingTrailingSidebar = settingsTabGroup == .trailingSidebar || playlistTabGroup == .trailingSidebar

    leftSidebarSettingsTabsRadioButton.state = (settingsTabGroup == .leadingSidebar) ? .on : .off
    rightSidebarSettingsTabsRadioButton.state = (settingsTabGroup == .trailingSidebar) ? .on : .off

    leftSidebarPlaylistTabsRadioButton.state = (playlistTabGroup == .leadingSidebar) ? .on : .off
    rightSidebarPlaylistTabsRadioButton.state = (playlistTabGroup == .trailingSidebar) ? .on : .off

    leftSidebarPlacement.isEnabled = isUsingLeadingSidebar
    leftSidebarShowToggleButton.isEnabled = isUsingLeadingSidebar
    leftSidebarClickToCloseButton.isEnabled = isUsingLeadingSidebar

    rightSidebarPlacement.isEnabled = isUsingTrailingSidebar
    rightSidebarShowToggleButton.isEnabled = isUsingTrailingSidebar
    rightSidebarClickToCloseButton.isEnabled = isUsingTrailingSidebar
  }

  @IBAction func settingsSidebarTabGroupAction(_ sender: NSButton) {
    Preference.set(sender.tag, for: .settingsTabGroupLocation)
  }

  @IBAction func playlistSidebarTabGroupAction(_ sender: NSButton) {
    Preference.set(sender.tag, for: .playlistTabGroupLocation)
  }

  @IBAction func saveAspectPresets(_ sender: AspectTokenField) {
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .aspectRatioPanelPresets) != csv {
      Logger.log("Saving \(Preference.Key.aspectRatioPanelPresets.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .aspectRatioPanelPresets)
    }
  }

  @IBAction func saveCropPresets(_ sender: AspectTokenField) {
    let csv = sender.commaSeparatedValues
    if Preference.string(for: .cropPanelPresets) != csv {
      Logger.log("Saving \(Preference.Key.cropPanelPresets.rawValue): \"\(csv)\"", level: .verbose)
      Preference.set(csv, for: .cropPanelPresets)
    }
  }

  @IBAction func resetAspectPresets(_ sender: NSButton) {
    let defaultValue = Preference.defaultPreference[.aspectRatioPanelPresets]
    Preference.set(defaultValue, for: .aspectRatioPanelPresets)
  }

  @IBAction func resetCropPresets(_ sender: NSButton) {
    let defaultValue = Preference.defaultPreference[.cropPanelPresets]
    Preference.set(defaultValue, for: .cropPanelPresets)
  }

  private func updateAspectControlsFromPrefs() {
    let newAspects = Preference.string(for: .aspectRatioPanelPresets) ?? ""
    aspectPresetsTokenField.commaSeparatedValues = newAspects
    let defaultAspects = Preference.defaultPreference[.aspectRatioPanelPresets] as? String
    resetAspectPresetsButton.isHidden = (defaultAspects == newAspects)
  }

  private func updateCropControlsFromPrefs() {
    let newCropPresets = Preference.string(for: .cropPanelPresets) ?? ""
    cropPresetsTokenField.commaSeparatedValues = newCropPresets
    let defaultCropPresets = Preference.defaultPreference[.cropPanelPresets] as? String
    resetCropPresetsButton.isHidden = defaultCropPresets == newCropPresets
  }

  // MARK: - Title Bar & OSC

  private func refreshTitleBarAndOSCSection(animate: Bool = true) {
    let ib = PWinPreviewImageBuilder(self.view)

    let titleBarIsOverlay = ib.hasTitleBar && ib.topBarPlacement == .insideViewport
    let oscIsOverlay = ib.oscEnabled && (ib.oscPosition == .floating ||
                                         (ib.oscPosition == .top && ib.topBarPlacement == .insideViewport) ||
                                         (ib.oscPosition == .bottom && ib.bottomBarPlacement == .insideViewport))
    let hasOverlay = titleBarIsOverlay || oscIsOverlay

    var viewHidePairs: [(NSView, Bool)] = []
    // Use animation where possible to make the transition less jarring
    NSAnimationContext.runAnimationGroup({context in
      context.duration = 0
      context.allowsImplicitAnimation = animate ? !AccessibilityPreferences.motionReductionEnabled : false
      context.timingFunction = CAMediaTimingFunction(name: .linear)

      let arrowButtonAction: Preference.ArrowButtonAction = Preference.enum(for: .arrowButtonAction)
      arrowButtonActionPopUpButton.selectItem(withTag: arrowButtonAction.rawValue)
      autoHideAfterCheckBox.isEnabled = hasOverlay
      oscAutoHideTimeoutTextField.isEnabled = hasOverlay
      hideFadeableViewsOutsideWindowCheckBox.isEnabled = hasOverlay
      windowPreviewImageView.image = ib.buildPWinPreviewImage()

      let oscIsFloating = ib.oscEnabled && ib.oscPosition == .floating

      if oscSnapToCenterCheckboxContainerView.isHidden != !oscIsFloating {
        viewHidePairs.append((oscSnapToCenterCheckboxContainerView, !oscIsFloating))
      }

      let oscIsBottom = ib.oscEnabled && ib.oscPosition == .bottom
      if oscBottomPlacementContainerView.isHidden != !oscIsBottom {
        viewHidePairs.append((oscBottomPlacementContainerView, !oscIsBottom))
      }

      let oscIsTop = ib.oscEnabled && ib.oscPosition == .top

      let hasBarOSC = oscIsBottom || oscIsTop
      viewHidePairs.append((toolbarSectionVStackView, !ib.oscEnabled))
      viewHidePairs.append((oscHeightStackView, !hasBarOSC))
      viewHidePairs.append((playbackButtonsStackView, !hasBarOSC))
      viewHidePairs.append((toolbarIconDimensionsHStackView, !hasBarOSC))

      let hasTopBar = ib.hasTopBar
      if topBarPositionContainerView.isHidden != !hasTopBar {
        viewHidePairs.append((topBarPositionContainerView, !hasTopBar))
      }

      let showTopBarTrigger = hasTopBar && ib.topBarPlacement == .insideViewport && Preference.isAdvancedEnabled
      if showTopBarTriggerContainerView.isHidden != !showTopBarTrigger {
        viewHidePairs.append((showTopBarTriggerContainerView, !showTopBarTrigger))
      }

      for (view, shouldHide) in viewHidePairs {
        for subview in view.subviews {
          subview.animator().isHidden = shouldHide
        }
      }

      // Need this to get proper slide effect
      oscBottomPlacementContainerView.superview?.layoutSubtreeIfNeeded()
    }, completionHandler: { [self] in
      NSAnimationContext.runAnimationGroup({context in
        context.duration = animate ? AccessibilityPreferences.adjustedDuration(IINAAnimation.DefaultDuration) : 0
        context.allowsImplicitAnimation = animate ? !AccessibilityPreferences.motionReductionEnabled : false
        context.timingFunction = CAMediaTimingFunction(name: .linear)
        for (view, shouldHide) in viewHidePairs {
          view.animator().isHidden = shouldHide
        }
        oscAutoHideTimeoutTextField.isEnabled = hasOverlay
        hideFadeableViewsOutsideWindowCheckBox.isEnabled = hasOverlay
        windowPreviewImageView.image = ib.buildPWinPreviewImage()

        updateOSCToolbarPreview()
      })
    })
  }

  @IBAction func oscPositionAction(_ sender: NSPopUpButton) {
    guard let oscPosition = Preference.OSCPosition(rawValue: sender.selectedTag()) else { return }
    let newGeo = ControlBarGeometry(oscPosition: oscPosition)
    // need to update this immediately because it is referenced by player windows for icon sizes, spacing
    ControlBarGeometry.current = newGeo
    Preference.set(oscPosition.rawValue, for: .oscPosition)
  }

  @IBAction func customizeOSCToolbarAction(_ sender: Any) {
    toolbarSettingsSheetController.currentItemsView?.initItems(fromItems: ControlBarGeometry.oscToolbarItems)
    toolbarSettingsSheetController.currentButtonTypes = ControlBarGeometry.oscToolbarItems
    view.window?.beginSheet(toolbarSettingsSheetController.window!) { response in
      guard response == .OK else { return }
      let newItems = self.toolbarSettingsSheetController.currentButtonTypes
      let intArray = newItems.map { $0.rawValue }
      let toolbarItems = intArray.compactMap(Preference.ToolBarButton.init(rawValue:))
      ControlBarGeometry.current = ControlBarGeometry(toolbarItems: toolbarItems)
      Preference.set(intArray, for: .controlBarToolbarButtons)
    }
  }

  private func updateOSCToolbarPreview() {
    let actualGeo = ControlBarGeometry.current
    Logger.log.verbose("New OSC geometry from barHeight=\(actualGeo.barHeight): toolIconSize=\(actualGeo.toolIconSize), toolIconSpacing=\(actualGeo.toolIconSpacing) playIconSize=\(actualGeo.playIconSize) playIconSpacing=\(actualGeo.playIconSpacing)")
    let toolIconSizeTicks = actualGeo.toolIconSizeTicks
    let toolIconSpacingTicks = actualGeo.toolIconSpacingTicks
    let playIconSizeTicks = actualGeo.playIconSizeTicks
    let playIconSpacingTicks = actualGeo.playIconSpacingTicks

    let previewBarHeight = min(maxToolbarPreviewBarHeight, actualGeo.barHeight)
    let geo = ControlBarGeometry(barHeight: previewBarHeight,
                                 toolIconSizeTicks: toolIconSizeTicks, toolIconSpacingTicks: toolIconSpacingTicks,
                                 playIconSizeTicks: playIconSizeTicks, playIconSpacingTicks: playIconSpacingTicks)

    if Logger.log.isTraceEnabled {
      Logger.log.trace("OSC geometry: barHeight=\(actualGeo.barHeight) toolIconSizeTicks=\(actualGeo.toolIconSizeTicks) toolIconSpacingTicks=\(actualGeo.toolIconSpacingTicks) playIconSizeTicks=\(actualGeo.playIconSizeTicks) playIconSpacingTicks=\(actualGeo.playIconSpacingTicks)")
      Logger.log.trace("OSC geometry preview: barHeight=\(geo.barHeight) toolIconSize=\(geo.toolIconSize), toolIconSpacing=\(geo.toolIconSpacing) playIconSize=\(geo.playIconSize) playIconSpacing=\(geo.playIconSpacing)")
    }

    NSAnimationContext.runAnimationGroup({context in
      context.timingFunction = CAMediaTimingFunction(name: .linear)

      // Prevent constraint violations by lowering these briefly...
      oscToolbarStackViewHeightConstraint?.priority = .defaultHigh
      oscToolbarStackViewWidthConstraint?.priority = .defaultHigh

      oscToolbarStackView.views.forEach { oscToolbarStackView.removeView($0) }
      oscToolbarStackView.spacing = 2 * geo.toolIconSpacing
      // Include spacing on sides:
      let toolbarButtons = geo.toolbarItems
      for buttonType in toolbarButtons {
        let button = OSCToolbarButton()
        button.setStyle(buttonType: buttonType, iconSize: geo.toolIconSize, iconSpacing: geo.toolIconSpacing)
        oscToolbarStackView.addView(button, in: .center)
        button.isEnabled = false
        // But don't gray it out
        (button.cell! as! NSButtonCell).imageDimsWhenDisabled = false
      }

      let totalToolbarWidth = geo.totalToolbarWidth
      Logger.log.verbose("Updating OSC toolbar preview (width=\(totalToolbarWidth) height=\(geo.barHeight))")

      oscToolbarStackViewHeightConstraint?.animateToConstant(geo.barHeight)
      oscToolbarStackViewWidthConstraint?.animateToConstant(totalToolbarWidth)

      // Update sheet preview also (both available items & current items)
      toolbarSettingsSheetController.updateToolbarButtonHeight()

      oscToolbarStackViewHeightConstraint?.priority = .required
      oscToolbarStackViewWidthConstraint?.priority = .required
    })
  }

  @IBAction func oscBarHeightAction(_ sender: NSTextField) {
    let oldGeo = ControlBarGeometry.current

    let geo = ControlBarGeometry(barHeight: sender.doubleValue,
                                 toolIconSizeTicks: oldGeo.toolIconSizeTicks, toolIconSpacingTicks: oldGeo.toolIconSpacingTicks,
                                 playIconSizeTicks: oldGeo.playIconSizeTicks, playIconSpacingTicks: oldGeo.playIconSpacingTicks)
    Logger.log.verbose("New OSC geometry from barHeight=\(geo.barHeight): toolIconSize=\(geo.toolIconSize), toolIconSpacing=\(geo.toolIconSpacing) playIconSize=\(geo.playIconSize) playIconSpacing=\(geo.playIconSpacing)")
    disableObserversForOSC = true
    ControlBarGeometry.current = geo
    Preference.set(geo.barHeight, for: .oscBarHeight)
    Preference.set(geo.toolIconSize, for: .oscBarToolbarIconSize)
    Preference.set(geo.toolIconSpacing, for: .oscBarToolbarIconSpacing)
    Preference.set(geo.playIconSize, for: .oscBarPlaybackIconSize)
    Preference.set(geo.playIconSpacing, for: .oscBarPlaybackIconSpacing)
    disableObserversForOSC = false
    updateOSCToolbarPreview()
  }

  @IBAction func toolIconSizeAction(_ sender: NSSlider) {
    let ticks = sender.integerValue
    let geo = ControlBarGeometry(toolIconSizeTicks: ticks)
    Logger.log.verbose("Updating oscBarToolbarIconSize: \(ticks) ticks, \(Preference.float(for: .oscBarToolbarIconSize)) -> \(geo.toolIconSize)")
    ControlBarGeometry.current = geo
    Preference.set(geo.toolIconSize, for: .oscBarToolbarIconSize)
  }

  @IBAction func toolIconSpacingAction(_ sender: NSSlider) {
    let ticks = sender.integerValue
    let geo = ControlBarGeometry(toolIconSpacingTicks: ticks)
    Logger.log.verbose("Updating oscBarToolbarIconSpacing: \(ticks) ticks, \(geo.toolIconSpacing)")
    ControlBarGeometry.current = geo
    Preference.set(geo.toolIconSpacing, for: .oscBarToolbarIconSpacing)
  }

  @IBAction func playIconSizeAction(_ sender: NSSlider) {
    let ticks = sender.integerValue
    let geo = ControlBarGeometry(playIconSizeTicks: ticks)
    Logger.log.verbose("Updating oscBarPlaybackIconSize: \(ticks) ticks, \(geo.playIconSize)")
    ControlBarGeometry.current = geo
    Preference.set(geo.playIconSize, for: .oscBarPlaybackIconSize)
  }

  @IBAction func playIconSpacingAction(_ sender: NSSlider) {
    let ticks = sender.integerValue
    let geo = ControlBarGeometry(playIconSpacingTicks: ticks)
    Logger.log.verbose("Updating oscBarPlaybackIconSpacing: \(ticks) ticks, \(geo.playIconSpacing)")
    ControlBarGeometry.current = geo
    Preference.set(geo.playIconSpacing, for: .oscBarPlaybackIconSpacing)
  }

  @IBAction func arrowButtonActionAction(_ sender: NSPopUpButton) {
    let arrowButtonAction: Preference.ArrowButtonAction = .init(rawValue: sender.selectedTag()) ?? .defaultValue
    let geo = ControlBarGeometry(arrowButtonAction: arrowButtonAction)
    Logger.log.verbose("Updating arrowButtonAction to: \(geo.arrowButtonAction)")
    ControlBarGeometry.current = geo
    let val = geo.arrowButtonAction.rawValue
    guard val != Preference.integer(for: .arrowButtonAction) else { return }
    Preference.set(val, for: .arrowButtonAction)
  }

  // MARK: - PiP

  @IBAction func setupPipBehaviorRelatedControls(_ sender: NSButton) {
    Preference.set(sender.tag, for: .windowBehaviorWhenPip)
  }

  private func updatePipBehaviorRelatedControls() {
    let pipBehaviorOption = Preference.enum(for: .windowBehaviorWhenPip) as Preference.WindowBehaviorWhenPip
    ([pipDoNothing, pipHideWindow, pipMinimizeWindow] as [NSButton])
      .first { $0.tag == pipBehaviorOption.rawValue }?.state = .on
  }

  // MARK: - Window Geometry

  @IBAction func updateWindowResizeScheme(_ sender: AnyObject) {
    guard let scheme = Preference.ResizeWindowScheme(rawValue: sender.tag) else {
      let tag: String = String(sender.tag ?? -1)
      Logger.log("Could not find ResizeWindowScheme matching rawValue \(tag)", level: .error)
      return
    }
    Preference.set(scheme.rawValue, for: .resizeWindowScheme)
    updateGeometryUI()
  }

  // Called by a UI control. Updates prefs + any dependent UI controls
  @IBAction func updateGeometryValue(_ sender: AnyObject) {
    if resizeWindowWhenOpeningFileCheckbox.state == .off {
      Preference.set(Preference.ResizeWindowTiming.never.rawValue, for: .resizeWindowTiming)
      Preference.set("", for: .initialWindowSizePosition)

    } else {
      if let timing = Preference.ResizeWindowTiming(rawValue: resizeWindowTimingPopUpButton.selectedTag()) {
        Preference.set(timing.rawValue, for: .resizeWindowTiming)
      }

      var geometry = ""
      // size
      if windowSizeCheckBox.state == .on {
        // either width or height, but not both
        if windowSizeTypePopUpButton.selectedTag() == SizeHeightTag {
          geometry += "x"
        }

        let isPercentage = windowSizeUnitPopUpButton.selectedTag() == UnitPercentTag
        if isPercentage {
          geometry += normalizePercentage(windowSizeValueTextField.stringValue)
        } else {
          geometry += windowSizeValueTextField.stringValue
        }
      }
      // position
      if windowPosCheckBox.state == .on {
        // X
        geometry += windowPosXAnchorPopUpButton.selectedTag() == SideLeftTag ? "+" : "-"

        if windowPosXUnitPopUpButton.selectedTag() == UnitPercentTag {
          geometry += normalizePercentage(windowPosXOffsetTextField.stringValue)
        } else {
          geometry += normalizeSignedInteger(windowPosXOffsetTextField.stringValue)
        }

        // Y
        geometry += windowPosYAnchorPopUpButton.selectedTag() == SideTopTag ? "+" : "-"

        if windowPosYUnitPopUpButton.selectedTag() == UnitPercentTag {
          geometry += normalizePercentage(windowPosYOffsetTextField.stringValue)
        } else {
          geometry += normalizeSignedInteger(windowPosYOffsetTextField.stringValue)
        }
      }
      Logger.log("Saving pref \(Preference.Key.initialWindowSizePosition.rawValue.quoted) with geometry: \(geometry.quoted)")
      Preference.set(geometry, for: .initialWindowSizePosition)
    }

    updateGeometryUI()
  }

  private func normalizeSignedInteger(_ string: String) -> String {
    let intValue = Int(string) ?? 0
    return intValue < 0 ? "\(intValue)" : "+\(intValue)"
  }

  private func normalizePercentage(_ string: String) -> String {
    var sizeInt = Int(string) ?? 100
    sizeInt = max(0, sizeInt)
    sizeInt = min(sizeInt, 100)
    return "\(sizeInt)%"
  }

  // Updates UI from prefs
  private func updateGeometryUI() {
    let resizeOption = Preference.enum(for: .resizeWindowTiming) as Preference.ResizeWindowTiming
    let scheme: Preference.ResizeWindowScheme = Preference.enum(for: .resizeWindowScheme)

    let isAnyResizeEnabled: Bool
    switch resizeOption {
    case .never:
      resizeWindowWhenOpeningFileCheckbox.state = .off
      isAnyResizeEnabled = false
    case .always, .onlyWhenOpen:
      resizeWindowWhenOpeningFileCheckbox.state = .on
      isAnyResizeEnabled = true
      resizeWindowTimingPopUpButton.selectItem(withTag: resizeOption.rawValue)

      switch scheme {
      case .mpvGeometry:
        mpvGeometryRadioButton.state = .on
        simpleVideoSizeRadioButton.state = .off
      case .simpleVideoSizeMultiple:
        mpvGeometryRadioButton.state = .off
        simpleVideoSizeRadioButton.state = .on
      }
    }

    mpvGeometryRadioButton.isHidden = !isAnyResizeEnabled
    simpleVideoSizeRadioButton.superview?.isHidden = !isAnyResizeEnabled

    // mpv
    let isMpvGeometryEnabled = isAnyResizeEnabled && scheme == .mpvGeometry
    var isUsingMpvSize = false
    var isUsingMpvPos = false

    if isMpvGeometryEnabled {
      let geometryString = Preference.string(for: .initialWindowSizePosition) ?? ""
      if let geometry = MPVGeometryDef.parse(geometryString) {
        Logger.log("Parsed \(Preference.quoted(.initialWindowSizePosition))=\(geometryString.quoted) ➤ \(geometry)")
        unparsedGeometryLabel.stringValue = "\"\(geometryString)\""
        // size
        if let h = geometry.h {
          isUsingMpvSize = true
          windowSizeTypePopUpButton.selectItem(withTag: SizeHeightTag)
          windowSizeUnitPopUpButton.selectItem(withTag: geometry.hIsPercentage ? UnitPercentTag : UnitPointTag)
          windowSizeValueTextField.stringValue = h
        } else if let w = geometry.w {
          isUsingMpvSize = true
          windowSizeTypePopUpButton.selectItem(withTag: SizeWidthTag)
          windowSizeUnitPopUpButton.selectItem(withTag: geometry.wIsPercentage ? UnitPercentTag : UnitPointTag)
          windowSizeValueTextField.stringValue = w
        }
        // position
        if var x = geometry.x, var y = geometry.y {
          let xSign = geometry.xSign ?? "+"
          let ySign = geometry.ySign ?? "+"
          x = x.hasPrefix("+") ? String(x.dropFirst()) : x
          y = y.hasPrefix("+") ? String(y.dropFirst()) : y
          isUsingMpvPos = true
          windowPosXAnchorPopUpButton.selectItem(withTag: xSign == "+" ? SideLeftTag : SideRightTag)
          windowPosXOffsetTextField.stringValue = x
          windowPosXUnitPopUpButton.selectItem(withTag: geometry.xIsPercentage ? UnitPercentTag : UnitPointTag)
          windowPosYAnchorPopUpButton.selectItem(withTag: ySign == "+" ? SideTopTag : SideBottomTag)
          windowPosYOffsetTextField.stringValue = y
          windowPosYUnitPopUpButton.selectItem(withTag: geometry.yIsPercentage ? UnitPercentTag : UnitPointTag)
        }
      } else {
        if !geometryString.isEmpty {
          Logger.log("Failed to parse string \(geometryString.quoted) from \(Preference.quoted(.initialWindowSizePosition)) pref", level: .error)
        }
        unparsedGeometryLabel.stringValue = ""
      }
    }
    unparsedGeometryLabel.isHidden = !(Preference.isAdvancedEnabled && isMpvGeometryEnabled)
    spacer0.isHidden = !isMpvGeometryEnabled
    mpvWindowSizeCollapseView.isHidden = !isMpvGeometryEnabled
    mpvWindowPositionCollapseView.isHidden = !isMpvGeometryEnabled
    windowSizeCheckBox.state = isUsingMpvSize ? .on : .off
    windowPosCheckBox.state = isUsingMpvPos ? .on : .off
    mpvWindowSizeCollapseView.setCollapsed(!isUsingMpvSize, animated: true)
    mpvWindowPositionCollapseView.setCollapsed(!isUsingMpvPos, animated: true)

    let geo = ControlBarGeometry()
    toolIconSizeSlider.intValue = Int32(geo.toolIconSizeTicks)
    toolIconSpacingSlider.intValue = Int32(geo.toolIconSpacingTicks)
    playIconSizeSlider.intValue = Int32(geo.playIconSizeTicks)
    playIconSpacingSlider.intValue = Int32(geo.playIconSpacingTicks)
  }

  // MARK: - Other

  @IBAction func disableAnimationsHelpAction(_ sender: Any) {
    NSWorkspace.shared.open(URL(string: AppData.disableAnimationsHelpLink)!)
  }

  private func updateThumbnailCacheStat() {
    AppDelegate.shared.preferenceWindowController.indexingQueue.async { [self] in
      let newString = "\(FloatingPointByteCountFormatter.string(fromByteCount: ThumbnailCacheManager.shared.getCacheSize(), countStyle: .binary))B"
      DispatchQueue.main.async { [self] in
        currentThumbCacheSizeTextField.stringValue = newString
      }
    }
  }

}

// MARK: - Transformers

@objc(IntEqualsZeroTransformer) class IntEqualsZeroTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 0
  }
}

@objc(IntEqualsOneTransformer) class IntEqualsOneTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 1
  }
}

@objc(IntEqualsTwoTransformer) class IntEqualsTwoTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number == 2
  }
}

@objc(IntNotEqualsOneTransformer) class IntNotEqualsOneTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number != 1
  }
}

@objc(IntNotEqualsTwoTransformer) class IntNotEqualsTwoTransformer: IntEqualsZeroTransformer {

  override func transformedValue(_ value: Any?) -> Any? {
    guard let number = value as? NSNumber else { return nil }
    return number != 2
  }
}


@objc(ResizeTimingTransformer) class ResizeTimingTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let timing = value as? Int else { return nil }
    return timing != Preference.ResizeWindowTiming.never.rawValue
  }
}

@objc(InverseResizeTimingTransformer) class InverseResizeTimingTransformer: ValueTransformer {

  static override func allowsReverseTransformation() -> Bool {
    return false
  }

  static override func transformedValueClass() -> AnyClass {
    return NSNumber.self
  }

  override func transformedValue(_ value: Any?) -> Any? {
    guard let timing = value as? Int else { return nil }
    return timing == Preference.ResizeWindowTiming.never.rawValue
  }
}


class PlayerWindowPreviewView: NSView {

  override func awakeFromNib() {
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.layer?.borderWidth = 1
    self.layer?.borderColor = CGColor(gray: 0.6, alpha: 0.5)
  }

}
