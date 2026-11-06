//! Why a path did not parse, for the message naming it.

/// 1-based column in the path text where the problem is.
column: usize = 0,
/// What is wrong there.
problem: Problem = .empty_path,

/// The ways path text can be malformed.
pub const Problem = enum {
    empty_path,
    empty_segment,
    unterminated_quote,
    text_after_quote,

    /// A short sentence for the message.
    pub fn describe(problem: Problem) []const u8 {
        return switch (problem) {
            .empty_path => "the path is empty",
            .empty_segment => "a segment is empty (two dots, or a dot at an end)",
            .unterminated_quote => "a quoted segment has no closing quote",
            .text_after_quote => "a quoted segment must be followed by a dot or the end",
        };
    }
};
