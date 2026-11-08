//! An adapter name that two packages export as different adapters (D107). Kosm finds these
//! before planning; an app using the name fails naming both packages.

/// The adapter name both packages export, as apps pass it in `.lang`.
name: []const u8,
/// The package the first of the two comes from, as the user spells it ("kosm_ini").
first_package: []const u8,
/// The package the second comes from; the same as `first_package` when one package exports both.
second_package: []const u8,
