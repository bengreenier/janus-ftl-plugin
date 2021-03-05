/**
 * @file Watchdog.cpp
 * @author Daniel Stiner (danstiner@gmail.com)
 * @version 0.1
 * @date 2021-03-04
 * 
 * @copyright Copyright (c) 2021 Daniel Stiner
 * 
 */

#include "Watchdog.h"

#if defined(SYSTEMD_WATCHDOG_SUPPORT)
    #include <systemd/sd-daemon.h>    
#endif

#pragma region Public methods

/*
if (char* watchdogIntervalUsecEnv = std::getenv("WATCHDOG_USEC"))
{
}
*/

void Watchdog::KeepAlive()
{
#if defined(SYSTEMD_WATCHDOG_SUPPORT)
    sd_notify(0, "WATCHDOG=1");
#endif
}
#pragma endregion
