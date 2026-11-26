#!/usr/bin/env python3
"""The tables of the FM synthesizer of doc/DEVICES.md §12, as integers.

The model, opm_model.py, reads them from here. Two are computed from
their formulas, and three are data that the formulas do not give.
With --zig, it writes them as emulator/src/opm_tables.zig, and with
--vhdl as hdl/src/opm_tables_pkg.vhd. The make test of each directory
checks that its file is current.

SIN and POW are computed with the host's floats, which differ between
hosts in the last bits. So each value is checked to lie at least
MARGIN from a point where it would round the other way, and the
script fails if one does not. Then every host computes the same table.
"""

# The data tables follow ymfm by Aaron Giles, src/ymfm_fm.ipp, of
# https://github.com/aaronsgiles/ymfm at commit 81aec25. Its notice:
#
#     BSD 3-Clause License
#
#     Copyright (c) 2021, Aaron Giles
#     All rights reserved.
#
#     Redistribution and use in source and binary forms, with or without
#     modification, are permitted provided that the following conditions
#     are met:
#
#     1. Redistributions of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#
#     2. Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in
#        the documentation and/or other materials provided with the
#        distribution.
#
#     3. Neither the name of the copyright holder nor the names of its
#        contributors may be used to endorse or promote products derived
#        from this software without specific prior written permission.
#
#     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#     "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#     LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#     FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#     COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#     INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#     BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#     LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#     CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#     LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#     ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#     POSSIBILITY OF SUCH DAMAGE.

from __future__ import annotations

import math
import sys
from typing import List, Sequence, Tuple

MARGIN = 1e-6


def _round(x: float) -> int:
    """x rounded to the nearest integer, checked to be far from a tie."""
    f = x - math.floor(x)
    if abs(f - 0.5) < MARGIN:
        raise ValueError(f"{x!r} is too close to a tie to round the same on every host")
    return int(math.floor(x + 0.5))


def _sin_table() -> List[int]:
    """-log2(sin(x)) * 256 over the first quarter of the wave, at the
    middles of 256 steps: the attenuation of the sine, 4.8 bits."""
    return [_round(-math.log2(math.sin((2 * i + 1) * math.pi / 1024)) * 256) for i in range(256)]


def _pow_table() -> List[int]:
    """2^(-(i+1)/256) * 2048, less the implied 1024: the mantissas of the
    linear level of the attenuation i/256, 10 bits."""
    return [_round(2.0 ** (-(i + 1) / 256) * 2048) - 1024 for i in range(256)]


# The attenuation of |sin| for a quarter of the wave, and the mantissas of
# the linear level of an attenuation's fraction.
SIN: List[int] = _sin_table()
POW: List[int] = _pow_table()

# The phase step of each of the 768 steps of an octave (12 notes of 64
# fractions), from C# of the highest octave, in units of 32 of the 10.10
# phase. ymfm has them from David Viens' analysis of the chip.
PHASE_STEP: List[int] = [
    1299, 1300, 1301, 1302, 1303, 1304, 1305, 1306, 1308, 1309, 1310, 1311, 1313, 1314, 1315, 1316,
    1318, 1319, 1320, 1321, 1322, 1323, 1324, 1325, 1327, 1328, 1329, 1330, 1332, 1333, 1334, 1335,
    1337, 1338, 1339, 1340, 1341, 1342, 1343, 1344, 1346, 1347, 1348, 1349, 1351, 1352, 1353, 1354,
    1356, 1357, 1358, 1359, 1361, 1362, 1363, 1364, 1366, 1367, 1368, 1369, 1371, 1372, 1373, 1374,
    1376, 1377, 1378, 1379, 1381, 1382, 1383, 1384, 1386, 1387, 1388, 1389, 1391, 1392, 1393, 1394,
    1396, 1397, 1398, 1399, 1401, 1402, 1403, 1404, 1406, 1407, 1408, 1409, 1411, 1412, 1413, 1414,
    1416, 1417, 1418, 1419, 1421, 1422, 1423, 1424, 1426, 1427, 1429, 1430, 1431, 1432, 1434, 1435,
    1437, 1438, 1439, 1440, 1442, 1443, 1444, 1445, 1447, 1448, 1449, 1450, 1452, 1453, 1454, 1455,
    1458, 1459, 1460, 1461, 1463, 1464, 1465, 1466, 1468, 1469, 1471, 1472, 1473, 1474, 1476, 1477,
    1479, 1480, 1481, 1482, 1484, 1485, 1486, 1487, 1489, 1490, 1492, 1493, 1494, 1495, 1497, 1498,
    1501, 1502, 1503, 1504, 1506, 1507, 1509, 1510, 1512, 1513, 1514, 1515, 1517, 1518, 1520, 1521,
    1523, 1524, 1525, 1526, 1528, 1529, 1531, 1532, 1534, 1535, 1536, 1537, 1539, 1540, 1542, 1543,
    1545, 1546, 1547, 1548, 1550, 1551, 1553, 1554, 1556, 1557, 1558, 1559, 1561, 1562, 1564, 1565,
    1567, 1568, 1569, 1570, 1572, 1573, 1575, 1576, 1578, 1579, 1580, 1581, 1583, 1584, 1586, 1587,
    1590, 1591, 1592, 1593, 1595, 1596, 1598, 1599, 1601, 1602, 1604, 1605, 1607, 1608, 1609, 1610,
    1613, 1614, 1615, 1616, 1618, 1619, 1621, 1622, 1624, 1625, 1627, 1628, 1630, 1631, 1632, 1633,
    1637, 1638, 1639, 1640, 1642, 1643, 1645, 1646, 1648, 1649, 1651, 1652, 1654, 1655, 1656, 1657,
    1660, 1661, 1663, 1664, 1666, 1667, 1669, 1670, 1672, 1673, 1675, 1676, 1678, 1679, 1681, 1682,
    1685, 1686, 1688, 1689, 1691, 1692, 1694, 1695, 1697, 1698, 1700, 1701, 1703, 1704, 1706, 1707,
    1709, 1710, 1712, 1713, 1715, 1716, 1718, 1719, 1721, 1722, 1724, 1725, 1727, 1728, 1730, 1731,
    1734, 1735, 1737, 1738, 1740, 1741, 1743, 1744, 1746, 1748, 1749, 1751, 1752, 1754, 1755, 1757,
    1759, 1760, 1762, 1763, 1765, 1766, 1768, 1769, 1771, 1773, 1774, 1776, 1777, 1779, 1780, 1782,
    1785, 1786, 1788, 1789, 1791, 1793, 1794, 1796, 1798, 1799, 1801, 1802, 1804, 1806, 1807, 1809,
    1811, 1812, 1814, 1815, 1817, 1819, 1820, 1822, 1824, 1825, 1827, 1828, 1830, 1832, 1833, 1835,
    1837, 1838, 1840, 1841, 1843, 1845, 1846, 1848, 1850, 1851, 1853, 1854, 1856, 1858, 1859, 1861,
    1864, 1865, 1867, 1868, 1870, 1872, 1873, 1875, 1877, 1879, 1880, 1882, 1884, 1885, 1887, 1888,
    1891, 1892, 1894, 1895, 1897, 1899, 1900, 1902, 1904, 1906, 1907, 1909, 1911, 1912, 1914, 1915,
    1918, 1919, 1921, 1923, 1925, 1926, 1928, 1930, 1932, 1933, 1935, 1937, 1939, 1940, 1942, 1944,
    1946, 1947, 1949, 1951, 1953, 1954, 1956, 1958, 1960, 1961, 1963, 1965, 1967, 1968, 1970, 1972,
    1975, 1976, 1978, 1980, 1982, 1983, 1985, 1987, 1989, 1990, 1992, 1994, 1996, 1997, 1999, 2001,
    2003, 2004, 2006, 2008, 2010, 2011, 2013, 2015, 2017, 2019, 2021, 2022, 2024, 2026, 2028, 2029,
    2032, 2033, 2035, 2037, 2039, 2041, 2043, 2044, 2047, 2048, 2050, 2052, 2054, 2056, 2058, 2059,
    2062, 2063, 2065, 2067, 2069, 2071, 2073, 2074, 2077, 2078, 2080, 2082, 2084, 2086, 2088, 2089,
    2092, 2093, 2095, 2097, 2099, 2101, 2103, 2104, 2107, 2108, 2110, 2112, 2114, 2116, 2118, 2119,
    2122, 2123, 2125, 2127, 2129, 2131, 2133, 2134, 2137, 2139, 2141, 2142, 2145, 2146, 2148, 2150,
    2153, 2154, 2156, 2158, 2160, 2162, 2164, 2165, 2168, 2170, 2172, 2173, 2176, 2177, 2179, 2181,
    2185, 2186, 2188, 2190, 2192, 2194, 2196, 2197, 2200, 2202, 2204, 2205, 2208, 2209, 2211, 2213,
    2216, 2218, 2220, 2222, 2223, 2226, 2227, 2230, 2232, 2234, 2236, 2238, 2239, 2242, 2243, 2246,
    2249, 2251, 2253, 2255, 2256, 2259, 2260, 2263, 2265, 2267, 2269, 2271, 2272, 2275, 2276, 2279,
    2281, 2283, 2285, 2287, 2288, 2291, 2292, 2295, 2297, 2299, 2301, 2303, 2304, 2307, 2308, 2311,
    2315, 2317, 2319, 2321, 2322, 2325, 2326, 2329, 2331, 2333, 2335, 2337, 2338, 2341, 2342, 2345,
    2348, 2350, 2352, 2354, 2355, 2358, 2359, 2362, 2364, 2366, 2368, 2370, 2371, 2374, 2375, 2378,
    2382, 2384, 2386, 2388, 2389, 2392, 2393, 2396, 2398, 2400, 2402, 2404, 2407, 2410, 2411, 2414,
    2417, 2419, 2421, 2423, 2424, 2427, 2428, 2431, 2433, 2435, 2437, 2439, 2442, 2445, 2446, 2449,
    2452, 2454, 2456, 2458, 2459, 2462, 2463, 2466, 2468, 2470, 2472, 2474, 2477, 2480, 2481, 2484,
    2488, 2490, 2492, 2494, 2495, 2498, 2499, 2502, 2504, 2506, 2508, 2510, 2513, 2516, 2517, 2520,
    2524, 2526, 2528, 2530, 2531, 2534, 2535, 2538, 2540, 2542, 2544, 2546, 2549, 2552, 2553, 2556,
    2561, 2563, 2565, 2567, 2568, 2571, 2572, 2575, 2577, 2579, 2581, 2583, 2586, 2589, 2590, 2593,
]

# The detune of DT1 = 0 to 3 for each key code (block and the note's top
# two bits), in steps of the 10.10 phase. DT1 = 4 to 7 negates them.
DETUNE: List[Tuple[int, int, int, int]] = [
    ( 0,  0,  1,  2), ( 0,  0,  1,  2), ( 0,  0,  1,  2), ( 0,  0,  1,  2),
    ( 0,  1,  2,  2), ( 0,  1,  2,  3), ( 0,  1,  2,  3), ( 0,  1,  2,  3),
    ( 0,  1,  2,  4), ( 0,  1,  3,  4), ( 0,  1,  3,  4), ( 0,  1,  3,  5),
    ( 0,  2,  4,  5), ( 0,  2,  4,  6), ( 0,  2,  4,  6), ( 0,  2,  5,  7),
    ( 0,  2,  5,  8), ( 0,  3,  6,  8), ( 0,  3,  6,  9), ( 0,  3,  7, 10),
    ( 0,  4,  8, 11), ( 0,  4,  8, 12), ( 0,  4,  9, 13), ( 0,  5, 10, 14),
    ( 0,  5, 11, 16), ( 0,  6, 12, 17), ( 0,  6, 13, 19), ( 0,  7, 14, 20),
    ( 0,  8, 16, 22), ( 0,  8, 16, 22), ( 0,  8, 16, 22), ( 0,  8, 16, 22),
]

# The increment of the attenuation for each rate, 0 to 63, in the eight
# steps of the envelope's counter: nibble i is the increment of step i.
INCREMENT: List[int] = [
    0x00000000, 0x00000000, 0x10101010, 0x10101010,  # 0-3
    0x10101010, 0x10101010, 0x11101110, 0x11101110,  # 4-7
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 8-11
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 12-15
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 16-19
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 20-23
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 24-27
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 28-31
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 32-35
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 36-39
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 40-43
    0x10101010, 0x10111010, 0x11101110, 0x11111110,  # 44-47
    0x11111111, 0x21112111, 0x21212121, 0x22212221,  # 48-51
    0x22222222, 0x42224222, 0x42424242, 0x44424442,  # 52-55
    0x44444444, 0x84448444, 0x84848484, 0x88848884,  # 56-59
    0x88888888, 0x88888888, 0x88888888, 0x88888888,  # 60-63
]

# The step of DT2 = 0 to 3, in 64ths of a semitone: 0, 600, 781, and
# 950 cents.
DT2: Tuple[int, int, int, int] = (0, (600 * 64 + 50) // 100, (781 * 64 + 50) // 100, (950 * 64 + 50) // 100)


def lfo_wave(shape: int, index: int) -> Tuple[int, int]:
    """The LFO's AM (0 to 255) and PM (-128 to 127) at index 0 to 255 of
    the waveforms 0 to 2: the saw, the square, and the triangle. The
    waveform 3, the noise, is the model's."""
    if shape == 0:
        am = index ^ 0xFF
        pm = index
    elif shape == 1:
        am = 0 if index & 0x80 else 0xFF
        pm = am ^ 0x80
    else:
        am = ((index << 1) if index & 0x80 else ((index ^ 0xFF) << 1)) & 0xFF
        pm = am if index & 0x40 else am ^ 0xFF
    return am, pm - 256 if pm & 0x80 else pm


def _zig_array(name: str, typ: str, values: Sequence[int], per_line: int, fmt: str) -> List[str]:
    lines = [f"pub const {name} = [{len(values)}]{typ}{{"]
    for i in range(0, len(values), per_line):
        lines.append("    " + " ".join(fmt.format(v) + "," for v in values[i : i + per_line]))
    lines.append("};")
    return lines


def zig() -> str:
    """The tables as Zig, for emulator/src/opm_tables.zig."""
    out = [
        "// The tables of the sound, DEVICES.md §12. Written by",
        "// test/opm_tables.py --zig; make test checks that it is current. Do",
        "// not edit. PHASE_STEP, DETUNE, and INCREMENT follow ymfm, whose notice",
        "// is in the header of test/opm_tables.py.",
        "",
        "/// The attenuation of |sin| for a quarter of the wave, 4.8 bits.",
    ]
    out += _zig_array("SIN", "u16", SIN, 12, "{:#05x}")
    out += ["", "/// The mantissas of the linear level of an attenuation's fraction."]
    out += _zig_array("POW", "u16", POW, 12, "{:#05x}")
    out += ["", "/// The phase step of each of the 768 steps of an octave, in units of 32."]
    out += _zig_array("PHASE_STEP", "u16", PHASE_STEP, 12, "{:4d}")
    out += ["", "/// The detune of DT1 = 0 to 3 for each key code."]
    out.append(f"pub const DETUNE = [{len(DETUNE)}][4]u8{{")
    for row in DETUNE:
        out.append("    .{ " + ", ".join(str(v) for v in row) + " },")
    out.append("};")
    out += ["", "/// The increment of the attenuation of each rate: nibble i for step i."]
    out += _zig_array("INCREMENT", "u32", INCREMENT, 4, "0x{:08X}")
    out += ["", "/// The step of DT2 = 0 to 3, in 64ths of a semitone."]
    out += _zig_array("DT2", "u16", DT2, 4, "{:d}")
    return "\n".join(out) + "\n"


def _vhdl_array(name: str, values: Sequence[int], per_line: int) -> List[str]:
    lines = [f"   constant {name} : t_table(0 to {len(values) - 1}) := ("]
    for i in range(0, len(values), per_line):
        row = ", ".join(str(v) for v in values[i : i + per_line])
        last = i + per_line >= len(values)
        lines.append("      " + row + (");" if last else ","))
    return lines


def vhdl() -> str:
    """The tables as VHDL, for hdl/src/opm_tables_pkg.vhd. DETUNE is
    indexed by 4 * the key code + DT1 mod 4, and INCREMENT, a nibble a
    step, by 8 * the rate + the step."""
    out = [
        "-- The tables of the sound, DEVICES.md §12. Written by",
        "-- emulator/test/opm_tables.py --vhdl; make test checks that it is",
        "-- current. Do not edit. PHASE_STEP, DETUNE, and INCREMENT follow ymfm,",
        "-- whose notice is in the header of emulator/test/opm_tables.py.",
        "",
        "package opm_tables_pkg is",
        "",
        "   type t_table is array (natural range <>) of natural;",
        "",
        "   -- The attenuation of |sin| for a quarter of the wave, 4.8 bits.",
    ]
    out += _vhdl_array("C_SIN", SIN, 12)
    out += ["", "   -- The mantissas of the linear level of an attenuation's fraction."]
    out += _vhdl_array("C_POW", POW, 12)
    out += ["", "   -- The phase step of each of the 768 steps of an octave, in units of 32."]
    out += _vhdl_array("C_PHASE_STEP", PHASE_STEP, 12)
    out += ["", "   -- The detune of DT1 = 0 to 3 for each key code."]
    out += _vhdl_array("C_DETUNE", [v for row in DETUNE for v in row], 8)
    out += ["", "   -- The increment of the attenuation of each rate, for each of its 8 steps."]
    out += _vhdl_array("C_INCREMENT", [(w >> (4 * i)) & 15 for w in INCREMENT for i in range(8)], 16)
    out += ["", "   -- The step of DT2 = 0 to 3, in 64ths of a semitone."]
    out += _vhdl_array("C_DT2", DT2, 4)
    out += ["", "end package opm_tables_pkg;"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    if sys.argv[1:] == ["--zig"]:
        sys.stdout.write(zig())
    elif sys.argv[1:] == ["--vhdl"]:
        sys.stdout.write(vhdl())
    else:
        sys.exit("usage: opm_tables.py --zig | --vhdl")
