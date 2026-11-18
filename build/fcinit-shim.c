/* fcinit-shim.c -- call FcInit() before an old app touches fontconfig.
 *
 * fontconfig 2.17+ (host 2.18.3 on CachyOS) prints
 *     Fontconfig warning: using without calling FcInit()
 * when an application calls FcNameUnparse()/FcConfigGetCurrent() before
 * FcInit(). xfce4-terminal 1.0.4 (the EL8 EPEL build we bundle) predates that
 * requirement and does not call FcInit(). The GUI wrapper preloads host
 * fontconfig because the bundled 2.13 cannot parse newer hosts' /etc/fonts,
 * so the warning is exposed on every launch on a new host.
 *
 * This shim is appended AFTER the host libfontconfig in LD_PRELOAD. Its
 * constructor dlopen()s the already-loaded library and calls FcInit() once,
 * before the app's first fontconfig call. No DT_NEEDED on fontconfig is
 * recorded: dlopen resolves the copy the wrapper chose, so the bundled 2.13
 * path (LOADOUT_GUI_HOST_FONTCONFIG=0) is not disturbed.
 *
 * Build: cc -shared -fPIC -O2 -Wl,-soname,libloadout-fcinit.so \
 *            -o libloadout-fcinit.so fcinit-shim.c -ldl
 */
#include <dlfcn.h>

typedef int (*fc_init_fn)(void);

__attribute__((constructor)) static void loadout_fc_init(void)
{
    void *fc = dlopen("libfontconfig.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!fc)
        return;
    fc_init_fn fc_init;
    *(void **)(&fc_init) = dlsym(fc, "FcInit");
    if (fc_init)
        (void)fc_init();
}
