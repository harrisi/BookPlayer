//
//  MainCoordinator.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 5/9/21.
//  Copyright © 2021 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import RevenueCat
import Themeable
import UIKit

class MainCoordinator: Coordinator {
  let tabBarController: AppTabBarController

  let playerManager: PlayerManagerProtocol
  let libraryService: LibraryServiceProtocol
  let playbackService: PlaybackServiceProtocol
  let accountService: AccountServiceProtocol
  let syncService: SyncServiceProtocol
  let watchConnectivityService: PhoneWatchConnectivityService
  let socketService: SocketServiceProtocol

  private var disposeBag = Set<AnyCancellable>()

  init(
    navigationController: UINavigationController,
    coreServices: CoreServices
  ) {
    self.libraryService = coreServices.libraryService
    self.accountService = coreServices.accountService
    self.syncService = coreServices.syncService
    self.playbackService = coreServices.playbackService
    self.playerManager = coreServices.playerManager
    self.watchConnectivityService = coreServices.watchService
    self.socketService = coreServices.socketService

    ThemeManager.shared.libraryService = libraryService

    let viewModel = MiniPlayerViewModel(playerManager: self.playerManager)
    self.tabBarController = AppTabBarController(miniPlayerViewModel: viewModel)
    tabBarController.modalPresentationStyle = .fullScreen
    tabBarController.modalTransitionStyle = .crossDissolve

    super.init(navigationController: navigationController, flowType: .modal)
    viewModel.coordinator = self

    accountService.setDelegate(self)
    accountService.loginIfUserExists()
    setUpTheming()
  }

  override func start() {
    presentingViewController = tabBarController

    if let currentTheme = try? libraryService.getLibraryCurrentTheme() {
      ThemeManager.shared.currentTheme = SimpleTheme(with: currentTheme)
    }

    startLibraryCoordinator()

    startProfileCoordinator()

    startSettingsCoordinator()

    bindObservers()

    navigationController.present(tabBarController, animated: false)
  }

  func startLibraryCoordinator() {
    let libraryCoordinator = LibraryListCoordinator(
      navigationController: AppNavigationController.instantiate(from: .Main),
      playerManager: self.playerManager,
      importManager: ImportManager(libraryService: self.libraryService),
      libraryService: self.libraryService,
      playbackService: self.playbackService
    )
    libraryCoordinator.tabBarController = tabBarController
    libraryCoordinator.parentCoordinator = self
    self.childCoordinators.append(libraryCoordinator)
    libraryCoordinator.start()
  }

  func startProfileCoordinator() {
    let profileCoordinator = ProfileCoordinator(
      libraryService: self.libraryService,
      accountService: self.accountService,
      navigationController: AppNavigationController.instantiate(from: .Main)
    )
    profileCoordinator.tabBarController = tabBarController
    profileCoordinator.parentCoordinator = self
    self.childCoordinators.append(profileCoordinator)
    profileCoordinator.start()
  }

  func startSettingsCoordinator() {
    let settingsCoordinator = SettingsCoordinator(
      libraryService: self.libraryService,
      accountService: self.accountService,
      navigationController: AppNavigationController.instantiate(from: .Settings)
    )
    settingsCoordinator.tabBarController = tabBarController
    settingsCoordinator.parentCoordinator = self
    self.childCoordinators.append(settingsCoordinator)
    settingsCoordinator.start()
  }

  func bindObservers() {
    NotificationCenter.default.publisher(for: .login, object: nil)
      .sink(receiveValue: { [weak self] _ in
        print("=== login")
        self?.syncLibrary()
      })
      .store(in: &disposeBag)
    NotificationCenter.default.publisher(for: .logout, object: nil)
      .sink(receiveValue: { [weak self] _ in
        print("=== logout")
        self?.socketService.disconnectSocket()
      })
      .store(in: &disposeBag)
  }

  func showPlayer() {
    let playerCoordinator = PlayerCoordinator(
      playerManager: self.playerManager,
      libraryService: self.libraryService,
      presentingViewController: self.presentingViewController
    )
    playerCoordinator.parentCoordinator = self
    self.childCoordinators.append(playerCoordinator)
    playerCoordinator.start()
  }

  func showMiniPlayer(_ flag: Bool) {
    // Only animate if it toggles the state
    guard flag != self.tabBarController.isMiniPlayerVisible else { return }

    guard flag else {
      self.tabBarController.animateView(self.tabBarController.miniPlayer, show: flag)
      return
    }

    if self.playerManager.hasLoadedBook() {
      self.tabBarController.animateView(self.tabBarController.miniPlayer, show: flag)
    }
  }

  func hasPlayerShown() -> Bool {
    return self.childCoordinators.contains(where: { $0 is PlayerCoordinator })
  }

  func getLibraryCoordinator() -> LibraryListCoordinator? {
    return self.childCoordinators.first as? LibraryListCoordinator
  }

  func getTopController() -> UIViewController? {
    return getPresentingController(coordinator: self)
  }

  func getPresentingController(coordinator: Coordinator) -> UIViewController? {
    guard let lastCoordinator = coordinator.childCoordinators.last else {
      return coordinator.presentingViewController?.getTopViewController()
      ?? coordinator.navigationController
    }

    return getPresentingController(coordinator: lastCoordinator)
  }

  func syncLibrary() {
    Task { [weak self] in
      try? await self?.syncService.syncLibrary()
    }
  }
}

extension MainCoordinator: PurchasesDelegate {
  public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
    self.accountService.updateAccount(from: customerInfo)
    self.syncService.accountUpdated(customerInfo)

    if !customerInfo.activeSubscriptions.isEmpty {
      socketService.connectSocket()
    } else {
      socketService.disconnectSocket()
    }
  }
}

extension MainCoordinator: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    guard
      !UserDefaults.standard.bool(forKey: Constants.UserDefaults.systemThemeVariantEnabled.rawValue)
    else { return }
    // This fixes native components like alerts having the proper color theme
    SceneDelegate.shared?.window?.overrideUserInterfaceStyle = theme.useDarkVariant
    ? .dark
    : .light
  }
}
