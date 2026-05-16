//
//  ObservationDetailView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//

import SwiftUI

struct ObservationDetailView: View {
	let observation: Observation
	@State private var selectedTab: ObservationDetailTab = .info

	var body: some View {
		VStack(spacing: 0) {
			Picker("",selection: $selectedTab) {
				ForEach(ObservationDetailTab.allCases) { tab in
					Label(tab.title, systemImage: tab.systemImage)
						.tag(tab)
				}
			}
			.pickerStyle(.segmented)
			.padding([.horizontal, .top])

			Group {
				switch selectedTab {
				case .info:
					ObservationInfoTabView(observation: observation)
				case .waterfall:
					ObservationWaterfallTabView(observation: observation)
				case .audio:
					ObservationAudioTabView(observation: observation)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.navigationTitle(detailTitle)
#if os(iOS)
		.navigationBarTitleDisplayMode(.inline)
#endif
	}

	private var detailTitle: String {
		if let satelliteName = observation.satellite_name, !satelliteName.isEmpty {
			return satelliteName
		}

		if let tle0 = observation.tle0, !tle0.isEmpty {
			return tle0
		}

		return "Observation \(observation.id)"
	}
}

private enum ObservationDetailTab: String, CaseIterable, Identifiable {
	case info
	case waterfall
	case audio

	var id: String { rawValue }

	var title: String {
		switch self {
		case .info:
			return "Info"
		case .waterfall:
			return "Waterfall"
		case .audio:
			return "Audio"
		}
	}

	var systemImage: String {
		switch self {
		case .info:
			return "info.circle"
		case .waterfall:
			return "waveform.path.ecg.rectangle"
		case .audio:
			return "play.circle"
		}
	}
}
