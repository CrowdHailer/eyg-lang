//! Embedding surface for native hosts and the standalone verification runners.
pub const interpreter = @import("interpreter.zig");
pub const parser = @import("parser.zig");
pub const inference = @import("inference.zig");
pub const capture = @import("capture.zig");
pub const pretty = @import("pretty.zig");
