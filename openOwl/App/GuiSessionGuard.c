#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

/// Runs before main(). Prevents SIGABRT crash in _RegisterApplication
/// when the binary is executed without Window Server access.
__attribute__((constructor))
static void openowl_require_gui_session(void) {
    SecuritySessionId sid = 0;
    SessionAttributeBits attrs = 0;
    OSStatus st = SessionGetInfo(callerSecuritySession, &sid, &attrs);
    if (st != errSecSuccess || !(attrs & sessionHasGraphicAccess)) {
        fprintf(stderr,
                "[openOwl] Fatal: no GUI session (Window Server unreachable).\n"
                "Launch with:  open <path-to>/openOwl.app\n");
        _exit(1);
    }
}
