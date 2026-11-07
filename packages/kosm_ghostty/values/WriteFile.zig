//! The parameter of the `write_*_file` actions: what to do with the temporary file, and how.

const WriteFile = @This();

/// Copy its path, paste its path into the terminal, or open it in the default editor.
action: enum { copy, paste, open },
/// The contents: plain text, text with terminal escapes, or HTML. null: ghostty's default, `plain`.
format: ?enum { plain, vt, html } = null,
