//
//  WatchTargetEditorViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation
import Combine


@MainActor
final class WatchTargetEditorViewModel: ObservableObject {
	@Published var satellites: [SatelliteModel] = []
	@Published var transmitters: [Transmitter] = []
	@Published var stations: [GroundStation] = []

	@Published var selectedSatelliteID: String?
	@Published var selectedTransmitterID: String?
	@Published var selectedStationIDs: Set<Int> = []
	@Published var centerFrequencyMHzText = ""

	@Published var satelliteSearchText = ""
	@Published var errorMessage: String?
	@Published var isLoadingSatellites = false
	@Published var isLoadingTransmitters = false
	@Published var isLoadingStations = false
	@Published var isLoadingRecommendedTransmitter = false
	@Published var recommendedTransmitterID: String?
	@Published var recommendedTransmitterObservationCount: Int = 0
	
	@Published var stationSearchText = ""

	private let dbService = SatNOGSDBService()
	private let networkService = SatNOGSNetworkService()
	private var recommendationTask: Task<Void, Never>?

	private let editingTarget: WatchTarget?
	private var didPrepareEditingTarget = false

	init(editingTarget: WatchTarget? = nil) {
		self.editingTarget = editingTarget

		if let editingTarget {
			selectedSatelliteID = editingTarget.satelliteID
			selectedTransmitterID = editingTarget.transmitterID
			selectedStationIDs = Set(editingTarget.stationIDs)
			centerFrequencyMHzText = Self.frequencyMHzText(from: editingTarget.centerFrequency)
			satelliteSearchText = editingTarget.satelliteName ?? editingTarget.name
		}
	}

	var filteredSatellites: [SatelliteModel] {

		let keyword = satelliteSearchText
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		guard !keyword.isEmpty else {
			return satellites
		}
		return satellites.filter { satellite in
			let displayName = displayName(for: satellite).lowercased()
			let aliases = satellite.names?.lowercased() ?? ""
			let satID = satellite.id.lowercased()
			let norad = satellite.norad_cat_id.map(String.init) ?? ""
			return displayName.contains(keyword)
				|| aliases.contains(keyword)
				|| satID.contains(keyword)
				|| norad.contains(keyword)
		}

	}

	var filteredStations: [GroundStation] {
		let keyword = stationSearchText
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		guard !keyword.isEmpty else {
			return stations
		}

		return stations.filter { station in
			let idText = String(station.id)
			let name = station.displayName.lowercased()
			let status = (station.status ?? "").lowercased()
			let qthlocator = (station.qthlocator ?? "").lowercased()
			let owner = (station.owner ?? "").lowercased()
			let antenna = station.antennaText.lowercased()

			return idText.contains(keyword)
				|| name.contains(keyword)
				|| status.contains(keyword)
				|| qthlocator.contains(keyword)
				|| owner.contains(keyword)
				|| antenna.contains(keyword)
		}
	}
	
	var canSave: Bool {
		selectedSatelliteID != nil &&
		selectedTransmitterID != nil &&
		!selectedStationIDs.isEmpty &&
		centerFrequencyHz != nil
	}

	var selectedTransmitter: Transmitter? {
		guard let selectedTransmitterID else {
			return nil
		}

		return transmitters.first { $0.id == selectedTransmitterID }
	}

	var recommendedTransmitter: Transmitter? {
		guard let recommendedTransmitterID else {
			return nil
		}

		return transmitters.first { $0.id == recommendedTransmitterID }
	}

	var centerFrequencyHz: Int? {
		let trimmed = centerFrequencyMHzText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let mhz = Double(trimmed) else {
			return nil
		}

		guard mhz > 0 else {
			return nil
		}

		return Int((mhz * 1_000_000).rounded())
	}

	func selectTransmitter(_ transmitter: Transmitter) {
		selectedTransmitterID = transmitter.id

		if let frequency = transmitter.defaultCenterFrequencyHz {
			centerFrequencyMHzText = transmitter.formatFrequencyMHz(frequency)
		} else {
			centerFrequencyMHzText = ""
		}
	}

	func isRecommendedTransmitter(_ transmitter: Transmitter) -> Bool {
		transmitter.id == recommendedTransmitterID
	}

	func recommendedDisplayName(for transmitter: Transmitter) -> String {
		let baseName = displayName(for: transmitter)
		guard isRecommendedTransmitter(transmitter) else {
			return baseName
		}

		return "👍 \(baseName)"
	}

	func loadInitialData() async {
		if editingTarget == nil {
			async let satelliteTask: Void = loadSatellites()
			async let stationTask: Void = loadStations()

			_ = await (satelliteTask, stationTask)
		} else {
			await loadStations()
		}
	}

	func prepareForEditingIfNeeded() async {
		guard !didPrepareEditingTarget, let editingTarget else {
			return
		}

		didPrepareEditingTarget = true
		selectedSatelliteID = editingTarget.satelliteID
		selectedTransmitterID = editingTarget.transmitterID
		selectedStationIDs = Set(editingTarget.stationIDs)
		centerFrequencyMHzText = Self.frequencyMHzText(from: editingTarget.centerFrequency)

		satelliteSearchText = editingTarget.satelliteName ?? editingTarget.name

		await loadTransmittersForEditing(satelliteID: editingTarget.satelliteID)
	}

	func loadSatellites() async {
		isLoadingSatellites = true
		defer { isLoadingSatellites = false }

		do {
			satellites = try await dbService.fetchAliveSatellites()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func loadStations() async {
		isLoadingStations = true
		defer { isLoadingStations = false }

		do {
			stations = try await networkService.fetchOnlineStations()
		} catch {
			errorMessage = error.localizedDescription
		}
	}

	func loadTransmitters(for satelliteID: String?) async {
		guard let satelliteID else {
			transmitters = []
			selectedTransmitterID = nil
			centerFrequencyMHzText = ""
			return
		}

		recommendationTask?.cancel()
		recommendedTransmitterID = nil
		recommendedTransmitterObservationCount = 0
		isLoadingRecommendedTransmitter = false

		isLoadingTransmitters = true
		defer { isLoadingTransmitters = false }

		do {
			transmitters = try await dbService.fetchTransmitters(satelliteID: satelliteID)
			selectedTransmitterID = nil
			centerFrequencyMHzText = ""
			startRecommendedTransmitterLoad(for: satelliteID)
		} catch {
			errorMessage = error.localizedDescription
			transmitters = []
			selectedTransmitterID = nil
			centerFrequencyMHzText = ""
		}
	}

	private func loadTransmittersForEditing(satelliteID: String) async {
		recommendationTask?.cancel()
		recommendedTransmitterID = nil
		recommendedTransmitterObservationCount = 0
		isLoadingRecommendedTransmitter = false

		isLoadingTransmitters = true
		defer { isLoadingTransmitters = false }

		do {
			transmitters = try await dbService.fetchTransmitters(satelliteID: satelliteID)

			if let editingTarget,
			   transmitters.contains(where: { $0.id == editingTarget.transmitterID }) {
				selectedTransmitterID = editingTarget.transmitterID
			} else if selectedTransmitterID == nil {
				selectedTransmitterID = nil
			}

			if centerFrequencyMHzText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			   let editingTarget {
				centerFrequencyMHzText = Self.frequencyMHzText(from: editingTarget.centerFrequency)
			}

			startRecommendedTransmitterLoad(for: satelliteID)
		} catch {
			errorMessage = error.localizedDescription
			transmitters = []
		}
	}

	private func startRecommendedTransmitterLoad(for satelliteID: String) {
		guard let satellite = satellites.first(where: { $0.id == satelliteID }),
			  let noradCatID = satellite.norad_cat_id else {
			return
		}

		recommendationTask?.cancel()
		recommendationTask = Task { [weak self] in
			await self?.loadRecommendedTransmitter(
				noradCatID: noradCatID,
				satelliteID: satelliteID
			)
		}
	}

	private func loadRecommendedTransmitter(
		noradCatID: Int,
		satelliteID: String
	) async {
		isLoadingRecommendedTransmitter = true
		defer {
			isLoadingRecommendedTransmitter = false
		}

		do {
			let observations = try await networkService.fetchGoodObservations(
				noradCatID: noradCatID,
				maxPages: 2
			)

			guard !Task.isCancelled,
				  selectedSatelliteID == satelliteID else {
				return
			}

			let availableTransmitterIDs = Set(transmitters.map { $0.id })
			let transmitterCounts = observations.reduce(into: [String: Int]()) { counts, observation in
				guard let transmitterID = observation.transmitter_uuid,
					  availableTransmitterIDs.contains(transmitterID) else {
					return
				}

				counts[transmitterID, default: 0] += 1
			}

			guard let best = transmitterCounts.max(by: { lhs, rhs in
				if lhs.value != rhs.value {
					return lhs.value < rhs.value
				}

				return lhs.key > rhs.key
			}) else {
				recommendedTransmitterID = nil
				recommendedTransmitterObservationCount = 0
				return
			}

			recommendedTransmitterID = best.key
			recommendedTransmitterObservationCount = best.value
		} catch is CancellationError {
			return
		} catch {
			guard !Task.isCancelled else {
				return
			}

			print("Failed to load recommended transmitter: \(error.localizedDescription)")
			recommendedTransmitterID = nil
			recommendedTransmitterObservationCount = 0
		}
	}

	func toggleStation(_ station: GroundStation) {
		if selectedStationIDs.contains(station.id) {
			selectedStationIDs.remove(station.id)
		} else {
			selectedStationIDs.insert(station.id)
		}
	}

	func makeWatchTarget() -> WatchTarget? {
		guard
			let satelliteID = selectedSatelliteID,
			let transmitterID = selectedTransmitterID
		else {
			return nil
		}

		let satellite = satellites.first { $0.id == satelliteID }
		let transmitter = transmitters.first { $0.id == transmitterID }
		let satelliteName = satellite.map(displayName(for:))
		let transmitterDescription = transmitter.map(displayName(for:))
		let centerFrequency = centerFrequencyHz
		
		let selectedStations = stations.filter { selectedStationIDs.contains($0.id) }

		let selectedStationNames = Dictionary(

			uniqueKeysWithValues: selectedStations.map { ($0.id, $0.displayName) }

		)

		let selectedStationSnapshots = Dictionary(

			uniqueKeysWithValues: selectedStations.map { station in
				(
					station.id,
					WatchStationSnapshot(
						id: station.id,
						name: station.displayName,
						latitude: station.lat,
						longitude: station.lng,
						altitude: station.altitude,
						minHorizon: station.min_horizon
					)
				)
			}

		)

		return WatchTarget(
			name: satelliteName ?? satelliteID,
			satelliteID: satelliteID,
			satelliteName: satelliteName,
			transmitterID: transmitterID,
			transmitterDescription: transmitterDescription,
			centerFrequency: centerFrequency,
			stationIDs: Array(selectedStationIDs).sorted(),
			stationNames: selectedStationNames,
			stationSnapshots: selectedStationSnapshots,
			minElevation: nil,
			enabled: true
		)
	}

	private static func frequencyMHzText(from frequencyHz: Int?) -> String {
		guard let frequencyHz, frequencyHz > 0 else {
			return ""
		}

		let mhz = Double(frequencyHz) / 1_000_000
		return String(format: "%g", mhz)
	}

	func displayName(for satellite: SatelliteModel) -> String {
		if let name = satellite.name, !name.isEmpty {
			return name
		}

		if let names = satellite.names, !names.isEmpty {
			return names
		}

		if let norad = satellite.norad_cat_id {
			return "NORAD \(norad)"
		}

		return satellite.id
	}

	func displayName(for transmitter: Transmitter) -> String {
		let description = transmitter.description?.trimmingCharacters(in: .whitespacesAndNewlines)
		let mode = transmitter.mode?.trimmingCharacters(in: .whitespacesAndNewlines)
		let frequencyText = transmitter.downlinkFrequencyText

		let name: String
		if let description, !description.isEmpty, let mode, !mode.isEmpty {
			name = "\(description) / \(mode)"
		} else if let description, !description.isEmpty {
			name = description
		} else if let mode, !mode.isEmpty {
			name = mode
		} else {
			name = transmitter.id
		}

		if frequencyText == "-" {
			return name
		}

		return "\(name) / \(frequencyText)"
	}
}
