### toolchain
#
CC ?= gcc

PKG_CONFIG ?= pkg-config
XML2_CONFIG ?= xml2-config
LIBGCRYPT_CONFIG ?= libgcrypt-config

MKDIR = mkdir
MKDIR_P = mkdir -p
INSTALL = install
INSTALL_LIB = $(INSTALL) -m 755
INSTALL_DIR = $(INSTALL) -d -m 755
RM = rm
RM_RF = $(RM) -rf
CMAKE ?= cmake
CMAKE_FLAGS = -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS=-fPIC

### flags
#
GLIB_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags glib-2.0)
GLIB_LDFLAGS ?= $(shell $(PKG_CONFIG) --libs glib-2.0)

LIBPURPLE_CFLAGS=$(shell $(PKG_CONFIG) --cflags purple)
PURPLE_DIR=$(shell $(PKG_CONFIG) --variable=plugindir purple)
LIBPURPLE_LDFLAGS=$(shell $(PKG_CONFIG) --cflags purple) \
		    -L$(PURPLE_DIR)
		    
XML2_CFLAGS ?= $(shell $(XML2_CONFIG) --cflags)
XML2_LDFLAGS ?= $(shell $(XML2_CONFIG) --libs)

LIBGCRYPT_LDFLAGS ?= $(shell $(LIBGCRYPT_CONFIG) --libs)

PKGCFG_C=$(GLIB_CFLAGS) \
	 $(LIBPURPLE_CFLAGS) \
	 $(XML2_CFLAGS)


PKGCFG_L=$(shell $(PKG_CONFIG) --libs sqlite3 mxml) \
 	$(GLIB_LDFLAGS) \
	 $(LIBPURPLE_LDFLAGS) \
	 $(XML2_LDFLAGS) \
	 $(LIBGCRYPT_LDFLAGS)

ifneq ("$(wildcard /etc/redhat-release)","")
	LJABBER= -lxmpp
else
ifneq ("$(wildcard /etc/SuSE-release)","")
	LJABBER= -lxmpp
else
	LJABBER= -ljabber
endif
endif

HEADERS=-I$(HDIR)/jabber -I$(LOMEMO_SRC) -I$(AXC_SRC) -I$(AX_DIR)/src
CFLAGS += -std=c11 -Wall -g -Wstrict-overflow $(PKGCFG_C) $(HEADERS)
PLUGIN_CPPFLAGS=-DPURPLE_PLUGINS
# -D_BSD_SOURCE can be removed once nobody uses glibc <= 2.18 any more
CPPFLAGS += -D_XOPEN_SOURCE=700 -D_BSD_SOURCE -D_DEFAULT_SOURCE
LDFLAGS += -ldl -lm $(PKGCFG_L) $(LJABBER) -Wl,-rpath,$(PURPLE_PLUGIN_DIR)
LDFLAGS_T=$(LDFLAGS) -lpurple -lcmocka 

### directories
#
PURPLE_HOME_PLUGIN_DIR=$(HOME)/.purple/plugins
PURPLE_PLUGIN_DIR = $(shell $(PKG_CONFIG) --variable=plugindir purple)

LDIR=./lib
BDIR=./build
SDIR=./src
HDIR=./headers
TDIR=./test

LOMEMO_DIR=$(LDIR)/libomemo
LOMEMO_SRC=$(LOMEMO_DIR)/src
LOMEMO_BUILD=$(LOMEMO_DIR)/build
LOMEMO_PATH=$(LOMEMO_BUILD)/libomemo-conversations.a

AXC_DIR=$(LDIR)/axc
AXC_SRC=$(AXC_DIR)/src
AXC_BUILD=$(AXC_DIR)/build
AXC_PATH=$(AXC_BUILD)/libaxc-nt.a

AX_DIR=$(AXC_DIR)/lib/libsignal-protocol-c
AX_PATH=$(AX_DIR)/build/src/libsignal-protocol-c.a

SOURCES := $(wildcard $(SDIR)/*.c)
OBJECTS := $(patsubst $(SDIR)/%.c, $(BDIR)/%.o, $(SOURCES))
OBJECTS_W_COVERAGE := $(patsubst $(SDIR)/%.c, $(BDIR)/%_w_coverage.o, $(SOURCES))
TEST_SOURCES := $(wildcard $(TDIR)/test_*.c)
TEST_OBJECTS := $(patsubst $(TDIR)/test_%.c, $(BDIR)/test_%.o, $(TEST_SOURCES))
TEST_TARGETS := $(patsubst $(TDIR)/test_%.c, $(BDIR)/test_%, $(TEST_SOURCES))
VENDOR_LIBS=$(LOMEMO_PATH) $(AXC_PATH) $(AX_PATH)


### make rules
#
all: $(BDIR)/lurch.so

$(BDIR):
	$(MKDIR_P) build

$(AX_PATH):
	cd $(AX_DIR)/ && \
	   $(MKDIR_P) build && \
	   cd build && \
	   $(CMAKE) $(CMAKE_FLAGS) .. \
	   && $(MAKE)

$(AXC_PATH):
	$(MAKE) -C "$(AXC_DIR)" build/libaxc-nt.a

$(LOMEMO_PATH):
	$(MAKE) -C "$(LOMEMO_DIR)" build/libomemo-conversations.a

$(BDIR)/%.o: $(SDIR)/%.c | $(BDIR)
	$(CC) -fPIC $(CFLAGS) $(CPPFLAGS) $(PLUGIN_CPPFLAGS) -c $(SDIR)/$*.c -o $@

$(BDIR)/%_w_coverage.o: $(SDIR)/%.c | $(BDIR)
	$(CC) -O0 --coverage $(CFLAGS) $(CPPFLAGS) $(PLUGIN_CPPFLAGS) -c $(SDIR)/$*.c -o $@

$(BDIR)/test_%.o: $(TDIR)/test_%.c | $(BDIR)
	$(CC) $(CFLAGS) -O0 -c $(TDIR)/test_$*.c -o $@

$(BDIR)/lurch.so: $(OBJECTS) $(VENDOR_LIBS)
	$(CC) -fPIC -shared $(CFLAGS) $(CPPFLAGS) $(PLUGIN_CPPFLAGS) \
		$^ \
		-o $@ $(LDFLAGS)
$(BDIR)/lurch.a: $(BDIR)/lurch.o $(VENDOR_LIBS)
	$(AR) rcs $@ $^

install: $(BDIR)/lurch.so
	[ -e "$(DESTDIR)/$(PURPLE_PLUGIN_DIR)" ] || \
		$(INSTALL_DIR) "$(DESTDIR)/$(PURPLE_PLUGIN_DIR)"
	$(INSTALL_LIB) "$(BDIR)/lurch.so" "$(DESTDIR)/$(PURPLE_PLUGIN_DIR)/lurch.so"

install-home: $(BDIR)/lurch.so
	[ -e "$(PURPLE_HOME_PLUGIN_DIR)" ] || \
		$(INSTALL_DIR) "$(PURPLE_HOME_PLUGIN_DIR)"
	$(INSTALL_LIB) "$(BDIR)/lurch.so" "$(PURPLE_HOME_PLUGIN_DIR)/lurch.so"


LURCH_VERSION ?= 0.0.0
TARBALL_DIR_NAME=lurch-$(LURCH_VERSION)
TARBALL_FILE_NAME=$(TARBALL_DIR_NAME)-src.tar.gz

tarball: | clean-all $(BDIR)
	$(MKDIR) $(TARBALL_DIR_NAME)
	rsync -av --progress . $(TARBALL_DIR_NAME)/ --exclude $(TARBALL_DIR_NAME)/ --exclude-from=.gitignore
	-find $(TARBALL_DIR_NAME)/ -name "*.git*" -exec rm -rf "{}" \;
	tar czf $(TARBALL_FILE_NAME) $(TARBALL_DIR_NAME)/
	mv $(TARBALL_FILE_NAME) $(TARBALL_DIR_NAME)/
	mv $(TARBALL_DIR_NAME) $(BDIR)/

$(BDIR)/test_lurch_util: $(OBJECTS_W_COVERAGE) $(VENDOR_LIBS) $(BDIR)/test_lurch_util.o
	$(CC) $(CFLAGS) $(CPPFLAGS) -O0 --coverage $^ $(PURPLE_DIR)/libjabber.so.0 -o $@ $(LDFLAGS_T) \
	-Wl,--wrap=purple_user_dir \
	-Wl,--wrap=purple_prefs_get_bool \
	-Wl,--wrap=purple_prefs_get_int \
	-Wl,--wrap=purple_debug_error \
	-Wl,--wrap=purple_debug_info \
	-Wl,--wrap=purple_debug_misc
	bash -c "set -o pipefail; $@ 2>&1 | grep -Ev ".*CRITICAL.*" | tr -s '\n'" # filter annoying and irrelevant glib output

$(BDIR)/test_lurch_api: $(OBJECTS_W_COVERAGE) $(VENDOR_LIBS) $(BDIR)/test_lurch_api.o
	$(CC) $(CFLAGS) $(CPPFLAGS) -O0 --coverage $^ $(PURPLE_DIR)/libjabber.so.0 -o $@ $(LDFLAGS_T)
	bash -c "set -o pipefail; $@ 2>&1 | grep -Ev ".*CRITICAL.*" | tr -s '\n'" # filter annoying and irrelevant glib output

test: $(OBJECTS_W_COVERAGE) $(VENDOR_LIBS) $(TEST_TARGETS)

coverage: test
	gcovr -r . --html --html-details -o build/coverage.html
	gcovr -r . -s

clean:
	$(RM_RF) "$(BDIR)"

clean-all: clean
	$(MAKE) -C "$(LOMEMO_DIR)" clean
	$(MAKE) -C "$(AXC_DIR)" clean-all

.PHONY: clean clean-all install install-home tarball test coverage

