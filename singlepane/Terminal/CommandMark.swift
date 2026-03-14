// CommandMark.swift
// Data model for OSC 133 shell integration marks.
// Each mark represents a boundary in the terminal's command lifecycle:
// prompt start → command start → output start → command finished.

import Foundation

/// The type of boundary an OSC 133 mark represents.
enum CommandMarkType {
    /// `A` — The shell is about to draw a prompt.
    case promptStart
    /// `B` — The prompt has been drawn; user input begins.
    case commandStart
    /// `C` — A command was entered and is about to execute; output follows.
    case outputStart
    /// `D` — The command has finished. Exit code is stored separately.
    case commandFinished
}

/// A single OSC 133 mark anchored to an absolute line in the terminal buffer.
struct CommandMark {
    /// Absolute line index in the terminal's circular buffer (`buffer.y + buffer.yBase`).
    let absoluteLine: Int
    /// Which phase of the command lifecycle this mark represents.
    let type: CommandMarkType
    /// Exit code of the completed command. Only populated for `.commandFinished` marks.
    let exitCode: Int?
}
