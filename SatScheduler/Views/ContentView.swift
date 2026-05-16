//
//  ContentView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct ContentView: View {

	@EnvironmentObject private var authManager: AuthManager

	var body: some View {
		TabView {
			WatchListView()
				.tabItem {
					Label("Watch List", systemImage: "list.star")
				}

			ObservationsView()
				.tabItem {
					Label("Observations", systemImage: "waveform")
				}
			StationTimeLineView()
				.tabItem {
					Label("Timeline", systemImage: "text.line.first.and.arrowtriangle.forward")
				}

			SettingsView()
				.tabItem {
					Label("Settings", systemImage: "gearshape")
				}
			
		}
		.sheet(isPresented: $authManager.shouldShowLoginPrompt) {
			LoginTokenView()
				.environmentObject(authManager)
		}
	}
}

//#Preview {
//    ContentView()
//}
