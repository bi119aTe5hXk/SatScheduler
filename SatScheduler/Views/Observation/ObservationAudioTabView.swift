//
//  ObservationAudioTabView.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//

import SwiftUI
import Combine

#if canImport(MobileVLCKit)
import MobileVLCKit
private typealias SatSchedulerVLCMediaPlayer = VLCMediaPlayer
private typealias SatSchedulerVLCMedia = VLCMedia
#elseif canImport(VLCKit)
import VLCKit
private typealias SatSchedulerVLCMediaPlayer = VLCMediaPlayer
private typealias SatSchedulerVLCMedia = VLCMedia
#endif

struct ObservationAudioTabView: View {
	let observation: Observation

	var body: some View {
		VStack(spacing: 16) {
			if let audioURL {
#if canImport(MobileVLCKit) || canImport(VLCKit)
				ObservationInlineAudioPlayerView(audioURL: audioURL)
#else
				VStack(spacing: 12) {
					ContentUnavailableView(
						"OGG playback is not available",
						systemImage: "waveform",
						description: Text("SatNOGS payload audio is usually OGG/Vorbis. AVPlayer does not reliably play this format on Apple platforms, so add VLCKit/MobileVLCKit to enable in-app playback.")
					)

					Link(destination: audioURL) {
						Label("Open Audio Playback", systemImage: "safari")
							.font(.headline)
					}
				}
#endif

				Text(audioURL.absoluteString)
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			} else {
				ContentUnavailableView("No audio playback", systemImage: "waveform")
			}
		}
		.padding()
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var audioURL: URL? {
		ObservationAssetURLBuilder.audioURL(for: observation)
	}
}

#if canImport(MobileVLCKit) || canImport(VLCKit)
private struct ObservationInlineAudioPlayerView: View {
	let audioURL: URL
	@StateObject private var playerController = ObservationAudioPlayerController()

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: playerController.isPlaying ? "waveform.circle.fill" : "waveform.circle")
				.font(.system(size: 56))
				.foregroundStyle(.secondary)

			HStack(spacing: 12) {
				Button {
					playerController.togglePlayback()
				} label: {
					Label(playerController.isPlaying ? "Pause" : "Play", systemImage: playerController.isPlaying ? "pause.fill" : "play.fill")
				}
				.buttonStyle(.borderedProminent)

				Button {
					playerController.stop()
				} label: {
					Label("Stop", systemImage: "stop.fill")
				}
				.buttonStyle(.bordered)
			}

			Slider(
				value: $playerController.sliderPosition,
				in: 0...1,
				onEditingChanged: { isEditing in
					playerController.setSeeking(isEditing)
				}
			)
			.disabled(!playerController.canSeek)

			HStack {
				Text(playerController.elapsedTimeText)
				Spacer()
				Text(playerController.durationText)
			}
			.font(.caption.monospacedDigit())
			.foregroundStyle(.secondary)

			if let statusMessage = playerController.statusMessage {
				Text(statusMessage)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity)
		.onAppear {
			playerController.prepare(url: audioURL)
		}
		.onDisappear {
			playerController.stop()
		}
	}
}

@MainActor
private final class ObservationAudioPlayerController: ObservableObject {
	@Published var isPlaying = false
	@Published var sliderPosition: Double = 0
	@Published var canSeek = false
	@Published var elapsedTimeText = "00:00"
	@Published var durationText = "--:--"
	@Published var statusMessage: String?

	private let player = SatSchedulerVLCMediaPlayer()
	private var timer: Timer?
	private var currentURL: URL?
	private var isSeeking = false

	func prepare(url: URL) {
		guard currentURL != url else {
			return
		}

		currentURL = url
		player.media = SatSchedulerVLCMedia(url: url)
		sliderPosition = 0
		elapsedTimeText = "00:00"
		durationText = "--:--"
		canSeek = false
		statusMessage = "Ready"
		startProgressTimer()
	}

	func togglePlayback() {
		if player.isPlaying {
			player.pause()
			isPlaying = false
			statusMessage = "Paused"
		} else {
			player.play()
			isPlaying = true
			statusMessage = "Playing"
			startProgressTimer()
		}
	}

	func stop() {
		player.stop()
		isPlaying = false
		sliderPosition = 0
		elapsedTimeText = "00:00"
		statusMessage = "Stopped"
		stopProgressTimer()
	}

	func setSeeking(_ seeking: Bool) {
		isSeeking = seeking

		guard !seeking else {
			return
		}

		seek(to: sliderPosition)
	}

	private func seek(to position: Double) {
		guard canSeek else {
			return
		}

		let clampedPosition = Float(max(0, min(1, position)))
		player.position = clampedPosition
		sliderPosition = Double(clampedPosition)
		updateTimeText()
	}

	private func startProgressTimer() {
		guard timer == nil else {
			return
		}

		timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
			Task { @MainActor in
				guard let self else {
					return
				}

				self.isPlaying = self.player.isPlaying
				self.canSeek = self.mediaLengthMilliseconds > 0

				if !self.isSeeking {
					self.sliderPosition = Double(max(0, min(1, self.player.position)))
				}

				self.updateTimeText()
			}
		}
	}

	private func stopProgressTimer() {
		timer?.invalidate()
		timer = nil
	}

	private var mediaLengthMilliseconds: Int32 {
		player.media?.length.intValue ?? 0
	}

	private func updateTimeText() {
		let currentMilliseconds = player.time.intValue
		let durationMilliseconds = mediaLengthMilliseconds

		elapsedTimeText = formatTime(milliseconds: currentMilliseconds)

		if durationMilliseconds > 0 {
			durationText = formatTime(milliseconds: durationMilliseconds)
		} else {
			durationText = "--:--"
		}
	}

	private func formatTime(milliseconds: Int32) -> String {
		guard milliseconds > 0 else {
			return "00:00"
		}

		let totalSeconds = Int(milliseconds / 1000)
		let minutes = totalSeconds / 60
		let seconds = totalSeconds % 60
		return String(format: "%02d:%02d", minutes, seconds)
	}

	deinit {
		timer?.invalidate()
	}
}
#endif
