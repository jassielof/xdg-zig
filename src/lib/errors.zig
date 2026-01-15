//! Error types for the XDG desktop entry parser

/// Errors that can occur during parsing
pub const ParseError = error{
    /// The file is not valid UTF-8
    InvalidUtf8,

    /// A group header is malformed
    InvalidGroupHeader,

    /// A group name contains invalid characters
    InvalidGroupName,

    /// Multiple groups have the same name
    DuplicateGroup,

    /// An entry appears before any group header
    EntryBeforeGroup,

    /// A key name is empty
    EmptyKey,

    /// A key name contains invalid characters
    InvalidKeyName,

    /// A line cannot be parsed
    InvalidLine,

    /// The required [Desktop Entry] group is missing
    MissingDesktopEntryGroup,
};
