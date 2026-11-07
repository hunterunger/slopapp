import Foundation

/// Why a line has no value. Every case is shown to the user (dimmed, in the result column),
/// so each reads as a short plain phrase.
public enum EvalError: Error, Equatable, Hashable, Sendable {
    case incompatibleUnits
    case divisionByZero
    case unknownName(String)
    case tooLarge
    case tooSmall
    case notReal
    case wholeNumberNeeded(String)
    case reservedName(String, kind: String)
    /// Currency conversion needs rates and none are downloaded or written in the sheet.
    case ratesOff
    /// The rates file exists but couldn't be read.
    case ratesUnavailable
    /// Rates are loaded but this currency isn't in them.
    case noRate(String)
    case blockUnits
    /// A date that doesn't exist (Feb 30).
    case invalidDate

    public var message: String {
        switch self {
        case .incompatibleUnits: "incompatible units"
        case .divisionByZero: "division by zero"
        case .unknownName(let name): "unknown name “\(name)”"
        case .tooLarge: "number too large"
        case .tooSmall: "number too small"
        case .notReal: "not a real number"
        case .wholeNumberNeeded(let what): "\(what) needs a whole number"
        case .reservedName(let name, let kind): "“\(name)” is \(kind)"
        case .ratesOff: "rates off"
        case .ratesUnavailable: "rates unavailable"
        case .noRate(let code): "no rate for \(code)"
        case .blockUnits: "lines above have mixed units"
        case .invalidDate: "not a real date"
        }
    }

    /// What to do about it, for the tooltip and VoiceOver.
    public var advice: String? {
        switch self {
        case .ratesOff: "Turn on exchange rates in Settings, or write a rate like 1 USD = 1.37 CAD."
        case .ratesUnavailable: "The saved rates couldn’t be read. Update them in Settings."
        case .noRate(let code): "Write a rate for \(code), like 1 EUR = 1.5 \(code)."
        case .reservedName: "Pick another name."
        case .unknownName: "Define it on a line above, like name = 10."
        default: nil
        }
    }
}

/// Internal: the line isn't a calculation (unknown words, half-typed). Shown as nothing.
struct NotACalculation: Error {}
