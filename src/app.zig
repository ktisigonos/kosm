//! What kosm counts as an app.

const Output = @import("Output.zig");

/// Whether `T` is an app: a struct with exactly `pub fn apply(self: T, output: *kosm.Output) !void`.
/// `Modifier.apply(Color) Color` does not count.
pub fn is(comptime T: type) bool {
    @setEvalBranchQuota(100_000);
    if (@typeInfo(T) != .@"struct" or !@hasDecl(T, "apply")) return false;
    const function = switch (@typeInfo(@TypeOf(T.apply))) {
        .@"fn" => |function| function,
        else => return false,
    };
    if (function.is_generic or function.param_types.len != 2) return false;
    if (function.param_types[0] != T or function.param_types[1] != *Output) return false;
    const Return = function.return_type orelse return false;
    return switch (@typeInfo(Return)) {
        .error_union => |error_union| error_union.payload == void,
        else => false,
    };
}
