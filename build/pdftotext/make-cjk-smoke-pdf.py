#!/usr/bin/env python3
"""Emit a minimal PDF whose text extraction requires poppler-data.

One page, one Type0 font using the predefined UniJIS-UCS2-H CMap
(Adobe-Japan1), no embedded font program and no ToUnicode map. The content
stream shows UCS-2 codes 0x3042 0x3044; extracting them back demands the
poppler-data cMap + cidToUnicode tables, so the expected pdftotext output
is exactly the two hiragana characters (U+3042 U+3044).
"""

import sys


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT.pdf")

    content = b"BT /F1 12 Tf 72 720 Td <30423044> Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>",
        b"<< /Type /Font /Subtype /Type0 /BaseFont /KozMinPro-Regular "
        b"/Encoding /UniJIS-UCS2-H /DescendantFonts [5 0 R] >>",
        b"<< /Type /Font /Subtype /CIDFontType0 /BaseFont /KozMinPro-Regular "
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> "
        b"/FontDescriptor 6 0 R >>",
        b"<< /Type /FontDescriptor /FontName /KozMinPro-Regular /Flags 4 "
        b"/FontBBox [0 -120 1000 880] /ItalicAngle 0 /Ascent 880 /Descent -120 "
        b"/CapHeight 700 /StemV 80 >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream",
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for num, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{num} 0 obj\n".encode() + body + b"\nendobj\n"

    xref_pos = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n").encode()

    with open(sys.argv[1], "wb") as fh:
        fh.write(out)


if __name__ == "__main__":
    main()
