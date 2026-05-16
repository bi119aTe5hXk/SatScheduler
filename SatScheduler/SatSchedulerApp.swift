//
//  SatSchedulerApp.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

@main
struct SatSchedulerApp: App {
	@StateObject private var authManager = AuthManager.shared
	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(authManager)
				.task {
					authManager.loadToken()
				}
		}
	}

}
