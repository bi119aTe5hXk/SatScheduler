//
//  LoginTokenView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct LoginTokenView: View {

	@EnvironmentObject private var authManager: AuthManager
	@Environment(\.dismiss) private var dismiss

	@State private var token: String = ""
	@State private var errorMessage: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("SatNOGS API Token")
				.font(.title2)
				.bold()

			Text("Please enter SatNOGS Network API Token. ")
				.foregroundStyle(.secondary)

			SecureField("API Token", text: $token)
				.textFieldStyle(.roundedBorder)

			if let errorMessage {
				Text(errorMessage)
					.foregroundStyle(.red)
					.font(.caption)
			}

			HStack {
				Button("Skip") {
					authManager.skipLoginPrompt()
					dismiss()
				}

				Spacer()

				Button("Save") {
					do {
						try authManager.saveToken(token)
						dismiss()
					} catch {
						errorMessage = error.localizedDescription
					}
				}
				.keyboardShortcut(.defaultAction)
				.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
			}
		}
		.padding()
		.frame(width: 420)
	}
}
