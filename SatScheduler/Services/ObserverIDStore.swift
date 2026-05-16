//
//  ObserverIDStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//
import Foundation
import Combine

@MainActor
final class ObserverIDStore: ObservableObject {
	static let shared = ObserverIDStore()

	private let key = "SatScheduler.observerID"
	@Published private(set) var observerIDText: String

	var observerID: Int? {
		Int(observerIDText.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	private init() {
		let cloudValue = NSUbiquitousKeyValueStore.default.string(forKey: key)
		let localValue = UserDefaults.standard.string(forKey: key)
		observerIDText = cloudValue ?? localValue ?? ""

		if let cloudValue, cloudValue != localValue {
			UserDefaults.standard.set(cloudValue, forKey: key)
		}

		NotificationCenter.default.addObserver(
			forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
			object: NSUbiquitousKeyValueStore.default,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in
				self?.reloadFromCloud()
			}
		}

		NSUbiquitousKeyValueStore.default.synchronize()
	}

	func saveObserverIDText(_ text: String) {
		let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
		observerIDText = normalized
		UserDefaults.standard.set(normalized, forKey: key)
		NSUbiquitousKeyValueStore.default.set(normalized, forKey: key)
		NSUbiquitousKeyValueStore.default.synchronize()
	}

	func removeObserverID() {
		observerIDText = ""
		UserDefaults.standard.removeObject(forKey: key)
		NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
		NSUbiquitousKeyValueStore.default.synchronize()
	}

	private func reloadFromCloud() {
		let cloudValue = NSUbiquitousKeyValueStore.default.string(forKey: key) ?? ""
		guard cloudValue != observerIDText else {
			return
		}

		observerIDText = cloudValue
		if cloudValue.isEmpty {
			UserDefaults.standard.removeObject(forKey: key)
		} else {
			UserDefaults.standard.set(cloudValue, forKey: key)
		}
	}
}

