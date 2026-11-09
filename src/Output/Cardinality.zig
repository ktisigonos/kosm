//! Which of a path's matches a set changes. Indices are 0-based in match order: files
//! sorted by path, then file order. Zero matches is always an error.

/// Which matches to set.
pub const Cardinality = union(enum) {
    /// Exactly one match must exist (`set`).
    one,
    /// The first of one or more (`setFirst`).
    first,
    /// Every one of one or more (`setAll`).
    all,
    /// The match at this index (`setNth`).
    nth: usize,
    /// The matches at these indices, each of which must exist (`setIndices`).
    indices: []const usize,
    /// The matches at indices `start` up to but not including `end` (`setRange`).
    range: struct { start: usize, end: usize },
};
