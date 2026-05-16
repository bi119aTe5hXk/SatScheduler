//
//  SettingsView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct SettingsView: View {

	@EnvironmentObject private var authManager: AuthManager
	@StateObject private var observerIDStore = ObserverIDStore.shared

	@State private var isShowingTokenEditor = false
	@State private var successMessage: String?
	@State private var cacheMessage: String?
	@State private var isShowingClearTimelineCacheConfirmation = false
	@State private var isShowingObserverIDEditor = false
	@State private var observerIDDraft = ""
	@State private var observerIDMessage: String?
	
	@AppStorage("SatScheduler.timeDisplayMode") private var timeDisplayMode = TimeDisplayMode.utc.rawValue

	var body: some View {
		NavigationStack {
			Form {
				Section {
					VStack(alignment: .leading, spacing: 16) {
						HStack(alignment: .center, spacing: 14) {
							Image(systemName: authManager.isLoggedIn ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
								.font(.system(size: 28))
								.foregroundStyle(authManager.isLoggedIn ? .green : .orange)

							VStack(alignment: .leading, spacing: 4) {
								Text("SatNOGS Account")
									.font(.headline)

								Text(authManager.isLoggedIn ? "API Token is configured." : "API Token is not configured.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
							}
						}

						Text("The token is stored in Keychain and is used when creating or managing SatNOGS observations.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

				Section("API Token") {
					Button {
						isShowingTokenEditor = true
						successMessage = nil
					} label: {
						Label(authManager.isLoggedIn ? "Change API Token" : "Set API Token", systemImage: "key.fill")
					}

					if authManager.isLoggedIn {
						Button(role: .destructive) {
							authManager.logout()
							successMessage = "API Token removed."
						} label: {
							Label("Remove API Token", systemImage: "trash")
						}
					}

					if let successMessage {
						Text(successMessage)
							.font(.caption)
							.foregroundStyle(.green)
					}
				}

				Section("Observer ID") {
					HStack {
						Text("Current Observer ID")
						Spacer()
						Text(observerIDStore.observerIDText.isEmpty ? "Not set" : observerIDStore.observerIDText)
							.foregroundStyle(.secondary)
					}

					Button {
						observerIDDraft = observerIDStore.observerIDText
						observerIDMessage = nil
						isShowingObserverIDEditor = true
					} label: {
						Label(observerIDStore.observerIDText.isEmpty ? "Set Observer ID" : "Change Observer ID", systemImage: "person.crop.circle.badge.checkmark")
					}

					if !observerIDStore.observerIDText.isEmpty {
						Button(role: .destructive) {
							observerIDStore.removeObserverID()
							observerIDMessage = "Observer ID removed."
						} label: {
							Label("Remove Observer ID", systemImage: "trash")
						}
					}

					Text("Observer ID is used to load observations that need rating. It is synced with iCloud key-value storage when available.")
						.font(.caption)
						.foregroundStyle(.secondary)

					if let observerIDMessage {
						Text(observerIDMessage)
							.font(.caption)
							.foregroundStyle(.green)
					}
				}
				Section("Time Display") {

					Picker("Prediction Time Zone", selection: $timeDisplayMode) {
						Text("UTC").tag(TimeDisplayMode.utc.rawValue)
						Text("Local Time").tag(TimeDisplayMode.local.rawValue)
					}
					.pickerStyle(.segmented)
					Text("SatNOGS Network displays observation times in UTC. Use UTC when comparing prediction results with the website.")
						.font(.caption)
						.foregroundStyle(.secondary)

				}
				Section("Cache") {
					Button(role: .destructive) {
						isShowingClearTimelineCacheConfirmation = true
					} label: {
						Label("Clear Station Timeline Cache", systemImage: "trash")
					}

					Text("This removes cached station observation timeline data stored locally. It does not delete observations from SatNOGS Network.")
						.font(.caption)
						.foregroundStyle(.secondary)

					if let cacheMessage {
						Text(cacheMessage)
							.font(.caption)
							.foregroundStyle(.green)
					}
				}
			}
			.navigationTitle("Settings")
			.sheet(isPresented: $isShowingTokenEditor) {
				APITokenEditorSheet {
					successMessage = "API Token saved."
				}
				.environmentObject(authManager)
			}
			.sheet(isPresented: $isShowingObserverIDEditor) {
				NavigationStack {
					Form {
						Section("SatNOGS Observer") {
							TextField("Observer ID", text: $observerIDDraft)
#if os(iOS)
								.keyboardType(.numberPad)
#endif
							Text("Used for /api/observations/?status=unknown&observer=<id>.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					.navigationTitle("Observer ID")
					.toolbar {
						ToolbarItem(placement: .cancellationAction) {
							Button("Cancel") {
								isShowingObserverIDEditor = false
							}
						}

						ToolbarItem(placement: .confirmationAction) {
							Button("Save") {
								observerIDStore.saveObserverIDText(observerIDDraft)
								observerIDMessage = "Observer ID saved."
								isShowingObserverIDEditor = false
							}
							.disabled(Int(observerIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
						}
					}
				}
				.frame(minWidth: 420, minHeight: 180)
			}
			.confirmationDialog(
				"Clear station timeline cache?",
				isPresented: $isShowingClearTimelineCacheConfirmation,
				titleVisibility: .visible
			) {
				Button("Clear Cache", role: .destructive) {
					StationScheduleStore.shared.clearCache()
					cacheMessage = "Station timeline cache cleared."
				}
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("Cached station timeline data will be removed from this device only.")
			}
			
		}
	}
}

private struct APITokenEditorSheet: View {

	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var authManager: AuthManager

	let onSaved: () -> Void

	@State private var tokenText = ""
	@State private var errorMessage: String?

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 20) {
				VStack(alignment: .leading, spacing: 8) {
					Image(systemName: "key.fill")
						.font(.system(size: 36))
						.foregroundStyle(.blue)

					Text(authManager.isLoggedIn ? "Change API Token" : "Set API Token")
						.font(.title2)
						.bold()

					Text("Enter your SatNOGS API token. It will be stored securely in Keychain and used for authenticated API requests.")
						.foregroundStyle(.secondary)
				}

				SecureField("API Token", text: $tokenText)
					.textFieldStyle(.roundedBorder)

				if let errorMessage {
					Text(errorMessage)
						.font(.caption)
						.foregroundStyle(.red)
				}

				Spacer()
			}
			.padding(24)
			.frame(minWidth: 420, minHeight: 280)
			.navigationTitle(authManager.isLoggedIn ? "Change API Token" : "Set API Token")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						dismiss()
					}
				}

				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						saveToken()
					}
					.disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
	}

	private func saveToken() {
		do {
			try authManager.saveToken(tokenText)
			onSaved()
			dismiss()
		} catch {
			errorMessage = error.localizedDescription
		}
	}
}
