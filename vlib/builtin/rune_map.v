module builtin

enum MapMode {
	to_upper
	to_lower
	to_title
}

// vfmt off
// Quotes from golang source code `src/unicode/tables.go`
/*
struct RuneMap {
	s int // start
	e int // end
	u int // upper offset
	l int // lower offset
}
*/
const rune_maps_columns_in_row = 4
// upper, lower, upper, lower, ... sequence
const rune_maps_ul = -3 // NOTE: this should *NOT* be used anywhere in rune_maps, as a normal offset.
// upper, title, lower, upper, title, lower, ... sequence
const rune_maps_utl = -2 // NOTE: this should *NOT* be used anywhere in rune_maps, as a normal offset.
// The rune_maps table below, has rows, each containing 4 integers, equivalent to the RuneMap struct from above.
// It is represented that way, instead of the more natural array of structs, to save on the .c encoding used for the initialisation.
// The overhead for representing it as an array of structs was ~28KB in .c, while with the flat array of ints, it is ~7.5KB.
// Given that xz can compress it to ~1.8KB, it could be probably represented in an even more compact way...
const rune_maps = [
	i32(0xB5), 0xB5, 743, 0,
	0xC0, 0xD6, 0, 32,
	0xD8, 0xDE, 0, 32,
	0xE0, 0xF6, -32, 0,
	0xF8, 0xFE, -32, 0,
	0xFF, 0xFF, 121, 0,
	0x100, 0x12F, -3, -3,
	0x130, 0x130, 0, -199,
	0x131, 0x131, -232, 0,
	0x132, 0x137, -3, -3,
	0x139, 0x148, -3, -3,
	0x14A, 0x177, -3, -3,
	0x178, 0x178, 0, -121,
	0x179, 0x17E, -3, -3,
	0x17F, 0x17F, -300, 0,
	0x180, 0x180, 195, 0,
	0x181, 0x181, 0, 210,
	0x182, 0x185, -3, -3,
	0x186, 0x186, 0, 206,
	0x187, 0x188, -3, -3,
	0x189, 0x18A, 0, 205,
	0x18B, 0x18C, -3, -3,
	0x18E, 0x18E, 0, 79,
	0x18F, 0x18F, 0, 202,
	0x190, 0x190, 0, 203,
	0x191, 0x192, -3, -3,
	0x193, 0x193, 0, 205,
	0x194, 0x194, 0, 207,
	0x195, 0x195, 97, 0,
	0x196, 0x196, 0, 211,
	0x197, 0x197, 0, 209,
	0x198, 0x199, -3, -3,
	0x19A, 0x19A, 163, 0,
	0x19C, 0x19C, 0, 211,
	0x19D, 0x19D, 0, 213,
	0x19E, 0x19E, 130, 0,
	0x19F, 0x19F, 0, 214,
	0x1A0, 0x1A5, -3, -3,
	0x1A6, 0x1A6, 0, 218,
	0x1A7, 0x1A8, -3, -3,
	0x1A9, 0x1A9, 0, 218,
	0x1AC, 0x1AD, -3, -3,
	0x1AE, 0x1AE, 0, 218,
	0x1AF, 0x1B0, -3, -3,
	0x1B1, 0x1B2, 0, 217,
	0x1B3, 0x1B6, -3, -3,
	0x1B7, 0x1B7, 0, 219,
	0x1B8, 0x1B9, -3, -3,
	0x1BC, 0x1BD, -3, -3,
	0x1BF, 0x1BF, 56, 0,
	0x1C4, 0x1CC, -2, -2,
	0x1CD, 0x1DC, -3, -3,
	0x1DD, 0x1DD, -79, 0,
	0x1DE, 0x1EF, -3, -3,
	0x1F1, 0x1F3, -2, -2,
	0x1F4, 0x1F5, -3, -3,
	0x1F6, 0x1F6, 0, -97,
	0x1F7, 0x1F7, 0, -56,
	0x1F8, 0x21F, -3, -3,
	0x220, 0x220, 0, -130,
	0x222, 0x233, -3, -3,
	0x23A, 0x23A, 0, 10795,
	0x23B, 0x23C, -3, -3,
	0x23D, 0x23D, 0, -163,
	0x23E, 0x23E, 0, 10792,
	0x23F, 0x240, 10815, 0,
	0x241, 0x242, -3, -3,
	0x243, 0x243, 0, -195,
	0x244, 0x244, 0, 69,
	0x245, 0x245, 0, 71,
	0x246, 0x24F, -3, -3,
	0x250, 0x250, 10783, 0,
	0x251, 0x251, 10780, 0,
	0x252, 0x252, 10782, 0,
	0x253, 0x253, -210, 0,
	0x254, 0x254, -206, 0,
	0x256, 0x257, -205, 0,
	0x259, 0x259, -202, 0,
	0x25B, 0x25B, -203, 0,
	0x25C, 0x25C, 42319, 0,
	0x260, 0x260, -205, 0,
	0x261, 0x261, 42315, 0,
	0x263, 0x263, -207, 0,
	0x265, 0x265, 42280, 0,
	0x266, 0x266, 42308, 0,
	0x268, 0x268, -209, 0,
	0x269, 0x269, -211, 0,
	0x26A, 0x26A, 42308, 0,
	0x26B, 0x26B, 10743, 0,
	0x26C, 0x26C, 42305, 0,
	0x26F, 0x26F, -211, 0,
	0x271, 0x271, 10749, 0,
	0x272, 0x272, -213, 0,
	0x275, 0x275, -214, 0,
	0x27D, 0x27D, 10727, 0,
	0x280, 0x280, -218, 0,
	0x282, 0x282, 42307, 0,
	0x283, 0x283, -218, 0,
	0x287, 0x287, 42282, 0,
	0x288, 0x288, -218, 0,
	0x289, 0x289, -69, 0,
	0x28A, 0x28B, -217, 0,
	0x28C, 0x28C, -71, 0,
	0x292, 0x292, -219, 0,
	0x29D, 0x29D, 42261, 0,
	0x29E, 0x29E, 42258, 0,
	0x345, 0x345, 84, 0,
	0x370, 0x373, -3, -3,
	0x376, 0x377, -3, -3,
	0x37B, 0x37D, 130, 0,
	0x37F, 0x37F, 0, 116,
	0x386, 0x386, 0, 38,
	0x388, 0x38A, 0, 37,
	0x38C, 0x38C, 0, 64,
	0x38E, 0x38F, 0, 63,
	0x391, 0x3A1, 0, 32,
	0x3A3, 0x3AB, 0, 32,
	0x3AC, 0x3AC, -38, 0,
	0x3AD, 0x3AF, -37, 0,
	0x3B1, 0x3C1, -32, 0,
	0x3C2, 0x3C2, -31, 0,
	0x3C3, 0x3CB, -32, 0,
	0x3CC, 0x3CC, -64, 0,
	0x3CD, 0x3CE, -63, 0,
	0x3CF, 0x3CF, 0, 8,
	0x3D0, 0x3D0, -62, 0,
	0x3D1, 0x3D1, -57, 0,
	0x3D5, 0x3D5, -47, 0,
	0x3D6, 0x3D6, -54, 0,
	0x3D7, 0x3D7, -8, 0,
	0x3D8, 0x3EF, -3, -3,
	0x3F0, 0x3F0, -86, 0,
	0x3F1, 0x3F1, -80, 0,
	0x3F2, 0x3F2, 7, 0,
	0x3F3, 0x3F3, -116, 0,
	0x3F4, 0x3F4, 0, -60,
	0x3F5, 0x3F5, -96, 0,
	0x3F7, 0x3F8, -3, -3,
	0x3F9, 0x3F9, 0, -7,
	0x3FA, 0x3FB, -3, -3,
	0x3FD, 0x3FF, 0, -130,
	0x400, 0x40F, 0, 80,
	0x410, 0x42F, 0, 32,
	0x430, 0x44F, -32, 0,
	0x450, 0x45F, -80, 0,
	0x460, 0x481, -3, -3,
	0x48A, 0x4BF, -3, -3,
	0x4C0, 0x4C0, 0, 15,
	0x4C1, 0x4CE, -3, -3,
	0x4CF, 0x4CF, -15, 0,
	0x4D0, 0x52F, -3, -3,
	0x531, 0x556, 0, 48,
	0x561, 0x586, -48, 0,
	0x10A0, 0x10C5, 0, 7264,
	0x10C7, 0x10C7, 0, 7264,
	0x10CD, 0x10CD, 0, 7264,
	0x10D0, 0x10FA, 3008, 0,
	0x10FD, 0x10FF, 3008, 0,
	0x13A0, 0x13EF, 0, 38864,
	0x13F0, 0x13F5, 0, 8,
	0x13F8, 0x13FD, -8, 0,
	0x1C80, 0x1C80, -6254, 0,
	0x1C81, 0x1C81, -6253, 0,
	0x1C82, 0x1C82, -6244, 0,
	0x1C83, 0x1C84, -6242, 0,
	0x1C85, 0x1C85, -6243, 0,
	0x1C86, 0x1C86, -6236, 0,
	0x1C87, 0x1C87, -6181, 0,
	0x1C88, 0x1C88, 35266, 0,
	0x1C90, 0x1CBA, 0, -3008,
	0x1CBD, 0x1CBF, 0, -3008,
	0x1D79, 0x1D79, 35332, 0,
	0x1D7D, 0x1D7D, 3814, 0,
	0x1D8E, 0x1D8E, 35384, 0,
	0x1E00, 0x1E95, -3, -3,
	0x1E9B, 0x1E9B, -59, 0,
	0x1E9E, 0x1E9E, 0, -7615,
	0x1EA0, 0x1EFF, -3, -3,
	0x1F00, 0x1F07, 8, 0,
	0x1F08, 0x1F0F, 0, -8,
	0x1F10, 0x1F15, 8, 0,
	0x1F18, 0x1F1D, 0, -8,
	0x1F20, 0x1F27, 8, 0,
	0x1F28, 0x1F2F, 0, -8,
	0x1F30, 0x1F37, 8, 0,
	0x1F38, 0x1F3F, 0, -8,
	0x1F40, 0x1F45, 8, 0,
	0x1F48, 0x1F4D, 0, -8,
	0x1F51, 0x1F51, 8, 0,
	0x1F53, 0x1F53, 8, 0,
	0x1F55, 0x1F55, 8, 0,
	0x1F57, 0x1F57, 8, 0,
	0x1F59, 0x1F59, 0, -8,
	0x1F5B, 0x1F5B, 0, -8,
	0x1F5D, 0x1F5D, 0, -8,
	0x1F5F, 0x1F5F, 0, -8,
	0x1F60, 0x1F67, 8, 0,
	0x1F68, 0x1F6F, 0, -8,
	0x1F70, 0x1F71, 74, 0,
	0x1F72, 0x1F75, 86, 0,
	0x1F76, 0x1F77, 100, 0,
	0x1F78, 0x1F79, 128, 0,
	0x1F7A, 0x1F7B, 112, 0,
	0x1F7C, 0x1F7D, 126, 0,
	0x1F80, 0x1F87, 8, 0,
	0x1F88, 0x1F8F, 0, -8,
	0x1F90, 0x1F97, 8, 0,
	0x1F98, 0x1F9F, 0, -8,
	0x1FA0, 0x1FA7, 8, 0,
	0x1FA8, 0x1FAF, 0, -8,
	0x1FB0, 0x1FB1, 8, 0,
	0x1FB3, 0x1FB3, 9, 0,
	0x1FB8, 0x1FB9, 0, -8,
	0x1FBA, 0x1FBB, 0, -74,
	0x1FBC, 0x1FBC, 0, -9,
	0x1FBE, 0x1FBE, -7205, 0,
	0x1FC3, 0x1FC3, 9, 0,
	0x1FC8, 0x1FCB, 0, -86,
	0x1FCC, 0x1FCC, 0, -9,
	0x1FD0, 0x1FD1, 8, 0,
	0x1FD8, 0x1FD9, 0, -8,
	0x1FDA, 0x1FDB, 0, -100,
	0x1FE0, 0x1FE1, 8, 0,
	0x1FE5, 0x1FE5, 7, 0,
	0x1FE8, 0x1FE9, 0, -8,
	0x1FEA, 0x1FEB, 0, -112,
	0x1FEC, 0x1FEC, 0, -7,
	0x1FF3, 0x1FF3, 9, 0,
	0x1FF8, 0x1FF9, 0, -128,
	0x1FFA, 0x1FFB, 0, -126,
	0x1FFC, 0x1FFC, 0, -9,
	0x2126, 0x2126, 0, -7517,
	0x212A, 0x212A, 0, -8383,
	0x212B, 0x212B, 0, -8262,
	0x2132, 0x2132, 0, 28,
	0x214E, 0x214E, -28, 0,
	0x2160, 0x216F, 0, 16,
	0x2170, 0x217F, -16, 0,
	0x2183, 0x2184, -3, -3,
	0x24B6, 0x24CF, 0, 26,
	0x24D0, 0x24E9, -26, 0,
	0x2C00, 0x2C2F, 0, 48,
	0x2C30, 0x2C5F, -48, 0,
	0x2C60, 0x2C61, -3, -3,
	0x2C62, 0x2C62, 0, -10743,
	0x2C63, 0x2C63, 0, -3814,
	0x2C64, 0x2C64, 0, -10727,
	0x2C65, 0x2C65, -10795, 0,
	0x2C66, 0x2C66, -10792, 0,
	0x2C67, 0x2C6C, -3, -3,
	0x2C6D, 0x2C6D, 0, -10780,
	0x2C6E, 0x2C6E, 0, -10749,
	0x2C6F, 0x2C6F, 0, -10783,
	0x2C70, 0x2C70, 0, -10782,
	0x2C72, 0x2C73, -3, -3,
	0x2C75, 0x2C76, -3, -3,
	0x2C7E, 0x2C7F, 0, -10815,
	0x2C80, 0x2CE3, -3, -3,
	0x2CEB, 0x2CEE, -3, -3,
	0x2CF2, 0x2CF3, -3, -3,
	0x2D00, 0x2D25, -7264, 0,
	0x2D27, 0x2D27, -7264, 0,
	0x2D2D, 0x2D2D, -7264, 0,
	0xA640, 0xA66D, -3, -3,
	0xA680, 0xA69B, -3, -3,
	0xA722, 0xA72F, -3, -3,
	0xA732, 0xA76F, -3, -3,
	0xA779, 0xA77C, -3, -3,
	0xA77D, 0xA77D, 0, -35332,
	0xA77E, 0xA787, -3, -3,
	0xA78B, 0xA78C, -3, -3,
	0xA78D, 0xA78D, 0, -42280,
	0xA790, 0xA793, -3, -3,
	0xA794, 0xA794, 48, 0,
	0xA796, 0xA7A9, -3, -3,
	0xA7AA, 0xA7AA, 0, -42308,
	0xA7AB, 0xA7AB, 0, -42319,
	0xA7AC, 0xA7AC, 0, -42315,
	0xA7AD, 0xA7AD, 0, -42305,
	0xA7AE, 0xA7AE, 0, -42308,
	0xA7B0, 0xA7B0, 0, -42258,
	0xA7B1, 0xA7B1, 0, -42282,
	0xA7B2, 0xA7B2, 0, -42261,
	0xA7B3, 0xA7B3, 0, 928,
	0xA7B4, 0xA7C3, -3, -3,
	0xA7C4, 0xA7C4, 0, -48,
	0xA7C5, 0xA7C5, 0, -42307,
	0xA7C6, 0xA7C6, 0, -35384,
	0xA7C7, 0xA7CA, -3, -3,
	0xA7D0, 0xA7D1, -3, -3,
	0xA7D6, 0xA7D9, -3, -3,
	0xA7F5, 0xA7F6, -3, -3,
	0xAB53, 0xAB53, -928, 0,
	0xAB70, 0xABBF, -38864, 0,
	0xFF21, 0xFF3A, 0, 32,
	0xFF41, 0xFF5A, -32, 0,
	0x10400, 0x10427, 0, 40,
	0x10428, 0x1044F, -40, 0,
	0x104B0, 0x104D3, 0, 40,
	0x104D8, 0x104FB, -40, 0,
	0x10570, 0x1057A, 0, 39,
	0x1057C, 0x1058A, 0, 39,
	0x1058C, 0x10592, 0, 39,
	0x10594, 0x10595, 0, 39,
	0x10597, 0x105A1, -39, 0,
	0x105A3, 0x105B1, -39, 0,
	0x105B3, 0x105B9, -39, 0,
	0x105BB, 0x105BC, -39, 0,
	0x10C80, 0x10CB2, 0, 64,
	0x10CC0, 0x10CF2, -64, 0,
	0x118A0, 0x118BF, 0, 32,
	0x118C0, 0x118DF, -32, 0,
	0x16E40, 0x16E5F, 0, 32,
	0x16E60, 0x16E7F, -32, 0,
	0x1E900, 0x1E921, 0, 34,
	0x1E922, 0x1E943, -34, 0,
]!
// vfmt on