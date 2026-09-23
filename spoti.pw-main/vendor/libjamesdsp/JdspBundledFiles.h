#ifndef JDSPBUNDLEDFILES_H
#define JDSPBUNDLEDFILES_H
// The files RootlessJamesDSP ships with the engine, assets/Liveprog and assets/DDC, compiled into the library
// (embed-assets.pl writes the table), for a host that has no files of its own to install them from. Not
// libjamesdsp's: spoti.pw's addition.

typedef struct {
    const char *kind;             // the directory it came from: "Liveprog" or "DDC"
    const char *name;             // the file's name, "stereowide.eel"
    const unsigned char *data;    // its bytes, followed by a NUL that `length` leaves out
    unsigned int length;
} JdspBundledFile;

extern const JdspBundledFile jdspBundledFiles[];
extern const unsigned int jdspBundledFileCount;

#endif // JDSPBUNDLEDFILES_H
