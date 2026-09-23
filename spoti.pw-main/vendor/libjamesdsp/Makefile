# libjamesdsp as a static library, apart from the tweak: its C builds with warnings off and its own flags,
# never under the tweak's -Werror, and every symbol it has is hidden, so none of its generic names (fft,
# linspace, src_*, drwav_*...) is exported from the tweak's dylib. tweak/Makefile runs this before it links
# (JDSP_PLATFORM=ios); the harnesses run it for the Mac and the simulator.
#
#     make [JDSP_PLATFORM=ios|sim|mac] [JDSP_SANITIZE=address|thread]
#
# Output goes to build/<platform>/ (gitignored) and is incremental: `make -C tweak clean` leaves it
# alone, and only what changed compiles again. The flags are JDSP4Linux's (libjamesdsp.pro): gnu11 at -O2,
# printf and Android's logging routed to handlers (PrintfStdOutExtension.c), Liveprog's output too
# (EELStdOutExtension.c, CUSTOM_CMD); but for DEBUG, whose only output is the convolution benchmark's table,
# printed on every engine start.

JDSP_PLATFORM ?= ios
JDSP_SANITIZE ?=

ifeq ($(JDSP_PLATFORM),ios)
JDSP_SDK := iphoneos
JDSP_TARGET := arm64-apple-ios16.0
else ifeq ($(JDSP_PLATFORM),sim)
JDSP_SDK := iphonesimulator
JDSP_TARGET := arm64-apple-ios16.0-simulator
else ifeq ($(JDSP_PLATFORM),mac)
JDSP_SDK := macosx
JDSP_TARGET := arm64-apple-macos13.0
else
$(error JDSP_PLATFORM is ios, sim or mac, not "$(JDSP_PLATFORM)")
endif

JDSP_OUT := build/$(JDSP_PLATFORM)$(if $(JDSP_SANITIZE),-$(JDSP_SANITIZE))
JDSP_LIB := $(JDSP_OUT)/libjamesdsp.a
JDSP_CC := $(shell xcrun --sdk $(JDSP_SDK) --find clang)
JDSP_AR := $(shell xcrun --sdk $(JDSP_SDK) --find libtool)
JDSP_SYSROOT := $(shell xcrun --sdk $(JDSP_SDK) --show-sdk-path)

JDSP_SRC := subtree/Main/libjamesdsp/jni/jamesdsp/jdsp
# Every C file of the engine is compiled, as libjamesdsp.pro lists them, plus JDSP4Linux's three beside it
# and the presets (assets/) made into C.
JDSP_SOURCES := $(sort $(shell find $(JDSP_SRC) -name '*.c')) JdspImpResToolbox.c EELStdOutExtension.c PrintfStdOutExtension.c
JDSP_OBJECTS := $(patsubst %.c,$(JDSP_OUT)/obj/%.o,$(JDSP_SOURCES)) $(JDSP_OUT)/obj/JdspBundledFiles.o

JDSP_CFLAGS := -target $(JDSP_TARGET) -isysroot $(JDSP_SYSROOT) -std=gnu11 -O2 -w -fvisibility=hidden -g \
	-I$(JDSP_SRC) -I$(JDSP_SRC)/.. -I. \
	-DLIBJAMESDSP_PLUGIN -DCUSTOM_CMD -Dprintf=redirected_printf -DANDROID_LOG_INFO=0 \
	$(if $(JDSP_SANITIZE),-fsanitize=$(JDSP_SANITIZE) -O1 -fno-omit-frame-pointer)

.PHONY: all clean
all: $(JDSP_LIB)

$(JDSP_LIB): $(JDSP_OBJECTS)
	@rm -f $@
	@$(JDSP_AR) -static -no_warning_for_no_symbols -o $@ $^
	@echo "libjamesdsp: $@"

# The flags as a file, rewritten only when they change, so a change of flags compiles everything again.
$(JDSP_OUT)/flags: FORCE
	@mkdir -p $(dir $@)
	@echo '$(JDSP_CC) $(JDSP_CFLAGS)' | cmp -s - $@ || echo '$(JDSP_CC) $(JDSP_CFLAGS)' > $@

$(JDSP_OUT)/obj/%.o: %.c $(JDSP_OUT)/flags
	@mkdir -p $(dir $@)
	@$(JDSP_CC) $(JDSP_CFLAGS) -MMD -MP -c $< -o $@

# The presets are regenerated every run but written only when they changed, so an unchanged tree compiles
# nothing (their names have spaces, which make's own dependencies cannot hold).
$(JDSP_OUT)/JdspBundledFiles.c: FORCE
	@mkdir -p $(dir $@)
	@perl embed-assets.pl assets > $@.tmp
	@if cmp -s $@.tmp $@; then rm $@.tmp; else mv $@.tmp $@; fi

$(JDSP_OUT)/obj/JdspBundledFiles.o: $(JDSP_OUT)/JdspBundledFiles.c $(JDSP_OUT)/flags
	@mkdir -p $(dir $@)
	@$(JDSP_CC) $(JDSP_CFLAGS) -MMD -MP -c $< -o $@

.PHONY: FORCE
FORCE:

clean:
	rm -rf build

-include $(JDSP_OBJECTS:.o=.d)
