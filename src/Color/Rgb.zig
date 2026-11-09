//! A color in gamma-encoded sRGB, one f64 per channel. Channels may leave 0..1.

const Rgb = @This();

red: f64,
green: f64,
blue: f64,
alpha: f64 = 1,
