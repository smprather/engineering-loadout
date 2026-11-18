/* xfce4-fcinit-probe.c -- a fontconfig client that calls FcNameUnparse()
 * before FcInit(), the shape that makes fontconfig 2.17+ print
 *     Fontconfig warning: using without calling FcInit()
 * A registered custom object type is what routes FcNameUnparse() through the
 * lazily-initialized registry (an empty pattern does not reach it). Used by
 * tests/xfce4-fcinit-shim against the real host library. Declarations are
 * written out rather than including headers so the test needs no -devel.
 */
typedef struct _FcPattern FcPattern;
typedef struct {
    const char *object;
    int type;
} FcObjectType;

extern FcPattern *FcPatternCreate(void);
extern int FcPatternAddString(FcPattern *, const char *, const unsigned char *);
extern int FcNameRegisterObjectTypes(const FcObjectType *, int);
extern char *FcNameUnparse(FcPattern *);

int main(void)
{
    FcObjectType custom = {"loadouttest", 3 /* FcTypeString */};

    FcNameRegisterObjectTypes(&custom, 1);
    FcPattern *pat = FcPatternCreate();
    FcPatternAddString(pat, "loadouttest", (const unsigned char *)"x");
    char *name = FcNameUnparse(pat);
    return name ? 0 : 1;
}
