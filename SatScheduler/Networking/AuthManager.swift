//
//  AuthManager.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {

	static let shared = AuthManager()

	@Published private(set) var apiToken: String = ""
	@Published var shouldShowLoginPrompt: Bool = false
	
	private let initialLoginPromptCompletedKey = "SatScheduler.initialLoginPromptCompleted"

	private let keychainStore: KeychainStore

	private init(keychainStore: KeychainStore = .shared) {
		self.keychainStore = keychainStore

		SatNOGSAPIClient.shared.apiTokenProvider = { [weak self] in
			self?.apiToken
		}
	}

	var isLoggedIn: Bool {
		!apiToken.isEmpty
	}

	func loadToken() {
		do {
			self.apiToken = try keychainStore.readAPIToken() ?? ""
		} catch {
			print("Failed to load API token from Keychain: \(error)")
			self.apiToken = ""
		}

		let hasCompletedInitialPrompt = UserDefaults.standard.bool(forKey: initialLoginPromptCompletedKey)
		self.shouldShowLoginPrompt = self.apiToken.isEmpty && !hasCompletedInitialPrompt
	}

	func saveToken(_ token: String) throws {
		let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !trimmedToken.isEmpty else {
			return
		}

		try keychainStore.saveAPIToken(trimmedToken)

		self.apiToken = trimmedToken
		UserDefaults.standard.set(true, forKey: initialLoginPromptCompletedKey)
		self.shouldShowLoginPrompt = false
	}

	func skipLoginPrompt() {
		UserDefaults.standard.set(true, forKey: initialLoginPromptCompletedKey)
		self.shouldShowLoginPrompt = false
	}

	func requireLoginPrompt() {
		guard !isLoggedIn else {
			return
		}

		self.shouldShowLoginPrompt = true
	}

	func logout() {
		do {
			try keychainStore.deleteAPIToken()
		} catch {
			print("Failed to delete API token from Keychain: \(error)")
		}

		self.apiToken = ""
		self.shouldShowLoginPrompt = false
	}
}
