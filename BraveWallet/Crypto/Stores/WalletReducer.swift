// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import BraveCore
import ComposableArchitecture
import Foundation
import SwiftUI

enum WalletState: Equatable {
  case initial
  case crypto(CryptoState)
  case unlock(UnlockState)
  case onboarding(OnboardingState)
}

struct OnboardingState: Equatable {
}

enum OnboardingAction: Equatable {
}

enum WalletAction {
  case onAppear
  case keyringInfoUpdated(BraveWallet.KeyringInfo)
  case keyringObservation(KeyringObserver.Action)
  case unlock(UnlockAction)
  case crypto(CryptoAction)
  case onboarding(OnboardingAction)
}

struct WalletEnvironment {
  let keyringController: BraveWalletKeyringController
  let keyringObserver: Effect<KeyringObserver.Action, Never>
  let rpcController: BraveWalletEthJsonRpcController
  let rpcControllerObserver: Effect<RpcControllerAction, Never>
  let walletService: BraveWalletBraveWalletService
  let assetRatioController: BraveWalletAssetRatioController
  let swapController: BraveWalletSwapController
  let tokenRegistry: BraveWalletERCTokenRegistry
  let transactionController: BraveWalletEthTxController
  let transactionObserver: Effect<TransactionAction, Never>
  let walletKeychain: WalletKeychain
}

let walletReducer = Reducer<WalletState, WalletAction, WalletEnvironment>.combine(
  unlockReducer
    .pullback(state: /WalletState.unlock, action: /WalletAction.unlock, environment: { environment in
      return UnlockEnvironment(
        keyringController: environment.keyringController,
        walletKeychain: environment.walletKeychain
      )
    }),
  cryptoReducer
    .pullback(state: /WalletState.crypto, action: /WalletAction.crypto, environment: { environment in
      return environment
    }),
  Reducer { state, action, environment in
    switch action {
    case .onAppear:
      return .merge(
        .fireAndForget {
          // Setup network if it's not set yet
          environment.rpcController.chainId { chainId in
            if chainId.isEmpty {
              environment.rpcController.setNetwork(BraveWallet.MainnetChainId) { _ in }
            }
          }
        },
        // Collect keyring info for setting up base state
        .future { completion in
          environment.keyringController.defaultKeyringInfo { keyringInfo in
            completion(.success(WalletAction.keyringInfoUpdated(keyringInfo)))
          }
        },
        // Start watching for keyring observations
        environment
          .keyringObserver
          .map(WalletAction.keyringObservation)
          .receive(on: DispatchQueue.main.animation(.default))
          .eraseToEffect()
      )
      
    case .keyringInfoUpdated(let keyring):
      if keyring.isDefaultKeyringCreated {
        if keyring.isLocked {
          state = .unlock(.init())
        } else {
          state = .crypto(.init())
        }
      } else {
        state = .onboarding(.init())
      }
      return .none
      
    case .keyringObservation(.locked):
      state = .unlock(.init())
      // Cancel all running observations on child reducers
      return .cancel(id: KeyringObserver.CancelId())
      
    case .keyringObservation(.unlocked),
        .keyringObservation(.keyringCreated),
        .keyringObservation(.keyringRestored):
      if (/WalletState.crypto).extract(from: state) == nil {
        state = .crypto(.init())
      }
      return .none
      
//    case .keyringObservation(.selectedAccountChanged):
//      // Collect keyring info for setting up base state
//      return .future { completion in
//        environment.keyringController.defaultKeyringInfo { keyringInfo in
//          completion(.success(WalletAction.keyringInfoUpdated(keyringInfo)))
//        }
//      }
      
    case .keyringObservation:
      return .none
      
    case .unlock:
      return .none
      
    case .crypto:
      return .none
      
    case .onboarding:
      return .none
    }
  }
)

enum UnlockError: LocalizedError {
  case incorrectPassword
  
  var errorDescription: String? {
    switch self {
    case .incorrectPassword:
      return ""
//      return Strings.Wallet.incorrectPasswordErrorMessage
    }
  }
}

struct RestoreState: Equatable {
  var phrase: String = ""
  var password: String = ""
  var repeatedPassword: String = ""
}

struct UnlockState: Equatable {
  @BindableState var password: String = ""
  var isUnlockButtonDisabled: Bool = true
  var isPasswordSaved: Bool = false
  var attemptedBiometricUnlock: Bool = false
  var unlockError: UnlockError?
  @BindableState var isRestoreVisible: Bool = false
  var restore: RestoreState?
}

enum UnlockAction: BindableAction {
  case onAppear
  case binding(BindingAction<UnlockState>)
  case unlockTapped
  case unlockFailed
  case fillPasswordFromKeychain
  case restoreTapped
  case restoreDismissed
}

struct WalletKeychain {
  var savePassword: (String) -> Result<Void, NSError>
  var loadPassword: () -> Result<String, NSError>
  var isPasswordSaved: () -> Bool
}

struct UnlockEnvironment {
  let keyringController: BraveWalletKeyringController
  let walletKeychain: WalletKeychain
}

let unlockReducer: Reducer<UnlockState, UnlockAction, UnlockEnvironment> =
  .init { state, action, environment in
    switch action {
    case .onAppear:
      let isPasswordSaved = environment.walletKeychain.isPasswordSaved()
      state.isPasswordSaved = isPasswordSaved
      // Attempt to unlock with biometrics
      if !state.attemptedBiometricUnlock, isPasswordSaved {
        return Effect(value: .fillPasswordFromKeychain)
      }
      return .none
    
    case .binding(\.$password):
      state.isUnlockButtonDisabled = state.password.isEmpty
      state.unlockError = nil
      return .none
      
    case .binding:
      return .none
      
    case .unlockTapped:
      return Effect
        .future { [password = state.password] callback in
          environment.keyringController
            .unlock(password) { success in
              // We only care about failures inside the unlock view
              if success {
                return
              }
              callback(.success(UnlockAction.unlockFailed))
            }
        }
      
    case .unlockFailed:
      state.unlockError = .incorrectPassword
      return .none
      
    case .fillPasswordFromKeychain:
      if case .success(let password) = environment.walletKeychain.loadPassword() {
        state.password = password
        return Effect(value: .unlockTapped)
      }
      return .none
      
    case .restoreTapped:
      state.isRestoreVisible = true
      state.restore = .init()
      return .none
      
    case .restoreDismissed:
      state.isRestoreVisible = false
      state.restore = nil
      return .none
    }
}
.binding()

import Combine

extension BraveWalletKeyringController {
  var observer: Effect<KeyringObserver.Action, Never> {
    .run { [weak self] subscriber in
      let observer = KeyringObserver(subscriber)
      self?.add(observer)
      
      return AnyCancellable {
        _ = observer
      }
    }
    .share()
    .eraseToEffect()
  }
}

class KeyringObserver: BraveWalletKeyringControllerObserver {
  struct CancelId: Hashable { }
  
  enum Action {
    case accountsChanged
    case autoLockMinutesChanged
    case backedUp
    case keyringCreated
    case keyringRestored
    case locked
    case unlocked
    case selectedAccountChanged
  }
  
  let subscriber: Effect<Action, Never>.Subscriber
  
  init(_ subscriber: Effect<Action, Never>.Subscriber) {
    self.subscriber = subscriber
  }
  
  func accountsChanged() {
    subscriber.send(.accountsChanged)
  }
  
  func autoLockMinutesChanged() {
    subscriber.send(.autoLockMinutesChanged)
  }
  
  func backedUp() {
    subscriber.send(.backedUp)
  }
  
  func keyringCreated() {
    subscriber.send(.keyringCreated)
  }
  
  func keyringRestored() {
    subscriber.send(.keyringRestored)
  }
  
  func locked() {
    subscriber.send(.locked)
  }
  
  func unlocked() {
    subscriber.send(.unlocked)
  }
  
  func selectedAccountChanged() {
    subscriber.send(.selectedAccountChanged)
  }
}

enum TransactionAction: Equatable {
  case onNewUnapprovedTx(BraveWallet.TransactionInfo)
  case onTransactionStatusChanged(BraveWallet.TransactionInfo)
  case onUnapprovedTxUpdated(BraveWallet.TransactionInfo)
}

class TransactionObserver: BraveWalletEthTxControllerObserver {
  let subscriber: Effect<TransactionAction, Never>.Subscriber
  
  init(_ subscriber: Effect<TransactionAction, Never>.Subscriber) {
    self.subscriber = subscriber
  }
  
  func onNewUnapprovedTx(_ txInfo: BraveWallet.TransactionInfo) {
    subscriber.send(.onNewUnapprovedTx(txInfo))
  }
  func onTransactionStatusChanged(_ txInfo: BraveWallet.TransactionInfo) {
    subscriber.send(.onTransactionStatusChanged(txInfo))
  }
  func onUnapprovedTxUpdated(_ txInfo: BraveWallet.TransactionInfo) {
    subscriber.send(.onUnapprovedTxUpdated(txInfo))
  }
}

extension BraveWalletEthTxController {
  var observer: Effect<TransactionAction, Never> {
    .run { subscriber in
      let observer = TransactionObserver(subscriber)
      self.add(observer)
      
      return AnyCancellable {
        _ = observer
      }
    }
    .share()
    .eraseToEffect()
  }
}

enum RpcControllerAction: Equatable {
  case chainChangedEvent(_ chainId: String)
  case onAddEthereumChainRequestCompleted(_ chainId: String, error: String)
  case onIsEip1559Changed(_ chainId: String, isEip1559: Bool)
}

class RpcControllerObserver: BraveWalletEthJsonRpcControllerObserver {
  let subscriber: Effect<RpcControllerAction, Never>.Subscriber
  
  init(_ subscriber: Effect<RpcControllerAction, Never>.Subscriber) {
    self.subscriber = subscriber
  }
  
  func chainChangedEvent(_ chainId: String) {
    subscriber.send(.chainChangedEvent(chainId))
  }
  func onAddEthereumChainRequestCompleted(_ chainId: String, error: String) {
    subscriber.send(.onAddEthereumChainRequestCompleted(chainId, error: error))
  }
  func onIsEip1559Changed(_ chainId: String, isEip1559: Bool) {
    subscriber.send(.onIsEip1559Changed(chainId, isEip1559: isEip1559))
  }
}

extension BraveWalletEthJsonRpcController {
  var observer: Effect<RpcControllerAction, Never> {
    .run { subscriber in
      let observer = RpcControllerObserver(subscriber)
      self.add(observer)
      
      return AnyCancellable {
        _ = observer
      }
    }
    .share()
    .eraseToEffect()
  }
}
