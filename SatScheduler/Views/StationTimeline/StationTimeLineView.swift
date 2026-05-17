//
//  StationTimeLineView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import SwiftUI

struct StationTimeLineView: View {
	@StateObject private var viewModel = StationTimeLineViewModel()

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 16) {
				headerView

				if viewModel.isLoading && viewModel.stationSchedules.isEmpty {
					loadingView
				} else if viewModel.stationSchedules.isEmpty {
					emptyView
				} else {
					StationScheduleTimelineView(
						start: viewModel.startDate,
						end: viewModel.endDate,
						stationSchedules: viewModel.stationSchedules,
						refreshingStationID: viewModel.refreshingStationID,
						onRefreshStation: { stationID in
							await viewModel.refreshStation(stationID)
						}

					)

//					Divider()
//
//					StationScheduleListView(stationSchedules: viewModel.stationSchedules)
				}
			}
			.padding(20)
			.navigationTitle("Station Timeline")
//			.toolbar {
//				ToolbarItem(placement: .primaryAction) {
//					Button {
//						Task {
//							await viewModel.refresh()
//						}
//					} label: {
//						if viewModel.isLoading {
//							ProgressView()
//								.controlSize(.small)
//							Text("Refreshing...")
//						} else {
//							Image(systemName: "arrow.clockwise")
//							Text("Refresh")
//						}
//					}
//					.disabled(viewModel.isLoading)
//				}
//			}
			.alert("Station Timeline", isPresented: Binding(
				get: { viewModel.message != nil },
				set: { if !$0 { viewModel.message = nil } }
			)) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(viewModel.message ?? "")
			}
			.task {
				viewModel.loadCachedSchedule()
			}
		}
	}

	private var headerView: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Cached station observation schedule")
				.font(.headline)

			Text(viewModel.cacheStatusText)
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var loadingView: some View {
		HStack(spacing: 10) {
			ProgressView()
			Text("Loading station schedule...")
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
	}

	private var emptyView: some View {
		ContentUnavailableView(
			"No Cached Schedule",
			systemImage: "calendar",
			description: Text("Click Refresh to fetch the latest station observation schedule.")
		)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

