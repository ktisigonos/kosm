//! Extra steps of a composed modifier, stored inline so composing needs no memory.

const Chain = @This();

const Step = @import("Step.zig");
const max_steps = @import("../Modifier.zig").max_steps;

steps: [max_steps - 1]Step = undefined,
length: usize = 0,
