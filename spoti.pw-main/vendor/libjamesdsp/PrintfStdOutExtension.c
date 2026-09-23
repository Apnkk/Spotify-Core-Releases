#include "PrintfStdOutExtension.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

static stdOutHandler _printfStdOutHandlerPtr = 0;
static void* _printfStdOutHandlerUserPtr = 0;

// spoti.pw: formatted into a buffer on the stack instead of vasprintf, so a message printed while audio is
// being processed allocates nothing; a longer one is cut at 512 bytes.
int redirected_printf(const char * format, ...) {
    char outstr[512];
    va_list ap;
    va_start(ap, format);
    int result = vsnprintf(outstr, sizeof outstr, format, ap);
    va_end(ap);
    if(result < 0)
        return result;

    if(_printfStdOutHandlerPtr != 0)
    {
        _printfStdOutHandlerPtr(outstr, _printfStdOutHandlerUserPtr);
    }
    return result;
}

// spoti.pw: formats the message with its arguments (it was passed on unformatted), on the stack as above.
void __android_log_print(int severity, const char* tag, const char* msg, ...) {
    char s[512];
    int used = snprintf(s, sizeof s, "%s: ", tag);
    if (used < 0 || used >= (int)sizeof s)
        return;
    va_list ap;
    va_start(ap, msg);
    vsnprintf(s + used, sizeof s - used, msg, ap);
    va_end(ap);
    if(_printfStdOutHandlerPtr != 0)
    {
        _printfStdOutHandlerPtr(s, _printfStdOutHandlerUserPtr);
    }
}

void setPrintfStdOutHandler(stdOutHandler funcPtr, void* userData)
{
    _printfStdOutHandlerPtr = funcPtr;
    _printfStdOutHandlerUserPtr = userData;
}

int isPrintfStdOutHandlerSet()
{
    return _printfStdOutHandlerPtr != 0;
}
