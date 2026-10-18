/*
 * Test stand-ins (NOT Mazda code), one file, selected with -D:
 *   EEM      -> /jci/lib/libjcieem_client.so: prints the code it gets
 *   MMUI     -> /jci/mmui/svcjcimmui.so: loads the eco library ($ECO_LIB) RTLD_LOCAL,
 *               like a plugin
 *   LAUNCHER -> sm_svclauncher: dlopen()s a service and calls svc_run()
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(EEM)
int EEM_SetEEMUpdateScreenEnable(void *h, int screen, void *cb, void *arg)
{
    printf("eem screen=%d h=%p cb_set=%d arg=%p\n", screen, h, cb != NULL, arg);
    fflush(stdout);
    return 7;
}
#elif defined(MMUI)
int svc_run(void)
{
    void *h = dlopen(getenv("ECO_LIB"), RTLD_NOW);
    if (h == NULL) {
        printf("dlopen eco: %s\n", dlerror());
        return 1;
    }
    int (*run)(void) = (int (*)(void))dlsym(h, "eco_run");
    return run();
}
#elif defined(LAUNCHER)
int main(int argc, char **argv)
{
    (void)argc;
    void *h = dlopen(argv[1], RTLD_NOW);
    if (h == NULL) {
        printf("dlopen: %s\n", dlerror());
        return 1;
    }
    int (*run)(void) = (int (*)(void))dlsym(h, "svc_run");
    return run();
}
#else
#error "build with -DEEM, -DMMUI or -DLAUNCHER"
#endif
