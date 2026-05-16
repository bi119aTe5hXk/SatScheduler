//
//  TimeDisplayMode.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//
import Foundation

enum TimeDisplayMode: String {
	case utc
	case local

	var timeZone: TimeZone {
		switch self {
		case .utc:
			return TimeZone(secondsFromGMT: 0)!
		case .local:
			return .current
		}
	}

	var label: String {
		switch self {
		case .utc:
			return "UTC"
		case .local:
			return TimeZone.current.identifier
		}
	}
}
