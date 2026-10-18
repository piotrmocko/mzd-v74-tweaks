/*
 * Test stand-in for /jci/mmui/uia/libjciuiaecoenergy.so (NOT the Mazda library).
 * It mimics only what fuel_ending_mmui.so relies on:
 *   - the two ending guards and the HEV guard, same logic as stock
 *     (ending screen enabled + equipped-feature type),
 *   - a state table in .data that reaches the guards through R_ARM_ABS32 symbol
 *     relocations, in the stock order (HEV, Effectiveness, Fuel),
 *   - the EEM request: feature mask 0x4a -> code 11 (i-stop data),
 *     0x25 -> code 12 (fuel data), through the PLT.
 * FT (feature type) and ES (ending screen enabled) come from the environment.
 */
#include <stdio.h>
#include <stdlib.h>

int EEM_SetEEMUpdateScreenEnable(void *h, int screen, void *cb, void *arg);

static int env(const char *n, int d)
{
    const char *v = getenv(n);
    return v ? atoi(v) : d;
}

int UIA_ECOENERGY_DBUS_GetEndingScreenStatus(void) { return env("ES", 1); }
int UIA_ECOENERGY_DBUS_GetFeatureType(void) { return env("FT", 3); }

/* 0 NONE, 1 ISTOP, 2 IELOOP, 3 ISTOP_IELOOP, 4 HEV, 5 MHYBRID, 6 ISTOP_MHYBRID */
int UIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsFuelConsumption(void)
{
    int t = UIA_ECOENERGY_DBUS_GetFeatureType();
    return UIA_ECOENERGY_DBUS_GetEndingScreenStatus() == 1 && (t == 0 || t == 2 || t == 5);
}

int UIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsEffectiveness(void)
{
    int t = UIA_ECOENERGY_DBUS_GetFeatureType();
    return UIA_ECOENERGY_DBUS_GetEndingScreenStatus() == 1 && (t == 1 || t == 3 || t == 6);
}

int UIA_ECOENERGY_a_isPrevEngRunNEndingSetOnNHEV(void)
{
    return UIA_ECOENERGY_DBUS_GetEndingScreenStatus() == 1 && UIA_ECOENERGY_DBUS_GetFeatureType() == 4;
}

static void cb(void) {}

static void start_ending(void)
{
    int t = UIA_ECOENERGY_DBUS_GetFeatureType();
    int code = 14;
    if (t <= 6 && ((1 << t) & 0x4a)) {
        code = 11;
    } else if (t <= 6 && ((1 << t) & 0x25)) {
        code = 12;
    }
    printf("ret=%d\n", EEM_SetEEMUpdateScreenEnable((void *)0x1111, code, (void *)cb, 0));
}

void UIA_ECOENERGY_StartHEVEndingStatus(void) { printf("ending=HEV\n"); }
void UIA_ECOENERGY_StartEffectivenessEndingStatus(void) { printf("ending=ISTOP\n"); start_ending(); }
void UIA_ECOENERGY_StartFuelConsumptionEndingStatus(void) { printf("ending=FUEL\n"); start_ending(); }

struct transition {
    int (*guard)(void);
    void (*action)(void);
};

struct transition table[] = {
    { UIA_ECOENERGY_a_isPrevEngRunNEndingSetOnNHEV, UIA_ECOENERGY_StartHEVEndingStatus },
    { UIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsEffectiveness, UIA_ECOENERGY_StartEffectivenessEndingStatus },
    { UIA_ECOENERGY_isPrevEngRunNEndingSetOnNEndingIsFuelConsumption, UIA_ECOENERGY_StartFuelConsumptionEndingStatus },
};

int eco_run(void)
{
    unsigned i;
    for (i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (table[i].guard()) {
            table[i].action();
            break;
        }
    }
    if (i == sizeof(table) / sizeof(table[0])) {
        printf("ending=none\n");
    }
    /* the normal Fuel Consumption screen (code 8) must stay untouched */
    printf("ret=%d\n", EEM_SetEEMUpdateScreenEnable((void *)0x1111, 8, (void *)cb, 0));
    return 0;
}
