# Real Unicode 17 fixture

UnicodeData-17.0.0-tags.txt is the unchanged contiguous suffix, lines40235–40575, of the Unicode Consortium's Unicode17.0.0 data file:

https://github.com/unicode-org/unicodetools/blob/main/unicodetools/data/ucd/17.0.0/UnicodeData.txt

Exact original full-file Git blob: fca68e3e154e62e49727ecf69f1df442582bfa96 (2198209 bytes). The blob was actually read through the approved GitHub blob API. The fixture has341 lines/16408 bytes, beginning E0001 and ending10FFFD. No rows, categories, names, delimiters or private-use sentinels were synthesized or reordered. It is a minimized source excerpt, not the complete UCD file.

The suffix contains actual Cf tag characters, Mn variation selectors, the omitted code-point gaps, and real Co private-use rows that terminate the nonspacing interval. It can be given directly to the complete Perl generator. The two gap assertions follow the existing generator and wchar.c width contract, not a new character-width policy. The complete official data file remains necessary when regenerating the shipped full header.

The data is covered by the accompanying complete LICENSE.unicode notice (Unicode-3.0), from the same upstream repository LICENSE blob d7e7973c2fd6f2586a8999a69dc21e39af26be0f.
