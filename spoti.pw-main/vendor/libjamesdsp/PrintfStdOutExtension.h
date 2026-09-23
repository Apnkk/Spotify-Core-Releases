// spoti.pw: a guard of its own; it was EELStdOutExtension.h's, so including both left one out.
#ifndef PRINTFSTDOUTEXTENSION_H
#define PRINTFSTDOUTEXTENSION_H

typedef void (*stdOutHandler)(const char*, void*);


extern void setPrintfStdOutHandler(stdOutHandler funcPtr, void* userData);
extern int isPrintfStdOutHandlerSet();
extern void __android_log_print(int severity, const char* tag, const char* msg, ...)
#if defined(__GNUC__)
    __attribute__ ((format(printf, 3, 4)))
#endif
    ;

#endif // PRINTFSTDOUTEXTENSION_H
