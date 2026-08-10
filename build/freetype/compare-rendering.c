/* compare-rendering -- quantify what a freetype bump does to glyph output.
 *
 * `ldd` clean says nothing about pixels, and libfreetype.so.6 is the shared
 * rasterizer for every GUI and terminal tool in the loadout, so a bump's real
 * risk is rendering drift. This dumps one line per rendered glyph with the
 * bitmap dimensions, the exact pixel bytes (hashed) and the advance reported
 * SEPARATELY -- a metrics-only change must not be able to masquerade as a
 * raster change, and vice versa, because they have very different blast
 * radii (an advance shift breaks a terminal's cell grid; a pixel shift is
 * cosmetic).
 *
 * Build ONCE against the OLD headers, then run it against each lib. That way
 * it doubles as a real ABI test: an old-header consumer driving the new
 * shared object, which is exactly what every already-built payload binary
 * does after the swap.
 *
 *   gcc -o /tmp/cmp build/freetype/compare-rendering.c \
 *       $(pkg-config --cflags --libs freetype2)
 *   for m in normal light autohint mono; do
 *       LD_LIBRARY_PATH=/usr/lib64  /tmp/cmp FONT.ttf $m > old.txt
 *       LD_LIBRARY_PATH=<newlibdir> /tmp/cmp FONT.ttf $m > new.txt
 *       paste old.txt new.txt | awk '{if($7!=$15)a++; if($8!=$16)p++}
 *           END{printf "%s adv=%d px=%d\n", "'$m'", a+0, p+0}'
 *   done
 *
 * Test the bundled Nerd Fonts (payload/fonts/*.zip), not just a system font:
 * DejaVu was bit-identical across 2.9.1 -> 2.14.3 while every CascadiaCode
 * face moved, so a one-font check would have reported a false all-clear.
 * Results for that bump are recorded in ADDING_BINARIES.md -> freetype.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ft2build.h>
#include FT_FREETYPE_H

int main(int argc, char **argv) {
    FT_Library lib; FT_Face face;
    int extra = 0;
    if (argc > 2) {
        if (!strcmp(argv[2],"autohint")) extra = FT_LOAD_FORCE_AUTOHINT;
        else if (!strcmp(argv[2],"light")) extra = FT_LOAD_TARGET_LIGHT;
        else if (!strcmp(argv[2],"mono")) extra = FT_LOAD_TARGET_MONO;
    }
    if (FT_Init_FreeType(&lib)) return 1;
    if (FT_New_Face(lib, argv[1], 0, &face)) return 1;
    const char *s = "Hamburgefonstiv0123@#$%&";
    int sizes[] = {9,11,12,14,16,24,32};
    for (unsigned si=0; si<sizeof(sizes)/sizeof(*sizes); si++) {
        FT_Set_Pixel_Sizes(face, 0, sizes[si]);
        for (const char *p=s; *p; p++) {
            if (FT_Load_Char(face,(unsigned char)*p, FT_LOAD_RENDER|extra)) continue;
            FT_Bitmap *b=&face->glyph->bitmap;
            unsigned long px=1469598103934665603UL;
            for (unsigned r=0;r<b->rows;r++)
                for (unsigned c=0;c<b->width;c++)
                    px=(px^b->buffer[r*b->pitch+c])*1099511628211UL;
            printf("sz=%d ch=%c w=%u h=%u left=%d top=%d adv=%ld px=%016lx\n",
                sizes[si], *p, b->width, b->rows,
                face->glyph->bitmap_left, face->glyph->bitmap_top,
                (long)face->glyph->advance.x, px);
        }
    }
    return 0;
}
