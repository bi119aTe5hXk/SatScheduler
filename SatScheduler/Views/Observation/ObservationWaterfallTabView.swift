//
//  ObservationWaterfallTabView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//
import SwiftUI

struct ObservationWaterfallTabView: View {
	let observation: Observation

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				if let waterfallURL {
					AsyncImage(url: waterfallURL) { phase in
						switch phase {
						case .empty:
							ProgressView("Loading waterfall...")
								.frame(maxWidth: .infinity, minHeight: 260)
						case .success(let image):
							image
								.resizable()
								.scaledToFit()
								.clipShape(RoundedRectangle(cornerRadius: 12))
						case .failure:
							ContentUnavailableView("Failed to load waterfall", systemImage: "photo")
						@unknown default:
							EmptyView()
						}
					}

					Link("Open Waterfall", destination: waterfallURL)
				} else {
					ContentUnavailableView("No waterfall image", systemImage: "photo")
				}
			}
			.padding()
		}
	}

	private var waterfallURL: URL? {
		ObservationAssetURLBuilder.waterfallURL(for: observation)
	}
}

