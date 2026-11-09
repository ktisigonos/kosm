//! Why a file's block markers can't be trusted, and where.

const Failure = @This();

/// 1-based line of the offending marker.
line: usize = 0,
problem: Problem = .unknown_marker,

/// What is wrong with a marker.
pub const Problem = enum {
    unclosed_begin,
    unopened_end,
    nested_begin,
    unknown_marker,
    duplicate_id,
    marker_in_content,

    /// A sentence for the user.
    pub fn describe(problem: Problem) []const u8 {
        return switch (problem) {
            .unclosed_begin => "kosm:begin has no kosm:end after it",
            .unopened_end => "kosm:end has no kosm:begin before it",
            .nested_begin => "kosm:begin inside another block; blocks cannot nest",
            .unknown_marker => "a comment starting with kosm: must be exactly kosm:begin <id> or kosm:end",
            .duplicate_id => "a second block with this id; ids must be unique in a file",
            .marker_in_content => "the block's own content contains a kosm: marker line",
        };
    }
};
