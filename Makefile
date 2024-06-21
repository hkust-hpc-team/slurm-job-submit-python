.PHONY: summary install clean test

#*Usually you do not need to change these
PYTHON_PATH=/usr/bin/python3 # use system python3
PYTHON_VERSION?=autodetect # e.g. 3.9 ; if not specify, try autodetect 
SLURM_VERSION?=autodetect # e.g. 23.02.7 ; if not specify, detected using slurmctld -V
SLURM_SOURCE_TAG?=autodetect # e.g. slurm-23-02-7-1 ; if not specify, will attempt select from source
SLURM_DOT_SLASH_CONFIGURE_FLAGS?=--enable-pam --enable-really-no-cray --enable-shared --enable-x11 --disable-static --disable-debug --disable-salloc-background --disable-partial_attach --with-oneapi=no --with-shared-libslurm --without-rpath # Default for rocky 9.3.0
SLURM_CONF_DIR?=autodetect # default: /etc/slurm ; if not specify, will attempt infer from SLURM_CONF before default
SLURM_INCLUDE_DIR?=/usr/include/slurm
SLURM_PLUGIN_INSTALL_DIR?=/usr/lib64/slurm
#*set for debugging
DEBUG?=

ifeq ($(strip $(PYTHON_VERSION)),autodetect)
undefine PYTHON_VERSION
endif
ifeq ($(strip $(SLURM_VERSION)),autodetect)
undefine SLURM_VERSION
endif
ifeq ($(strip $(SLURM_SOURCE_TAG)),autodetect)
undefine SLURM_SOURCE_TAG
endif
ifeq ($(strip $(SLURM_CONF_DIR)),autodetect)
undefine SLURM_CONF_DIR
endif

ifndef PYTHON_VERSION
PYTHON_VERSION_AUTODETECT="(autodetect)"
PYTHON_VERSION=$(shell $(PYTHON_PATH) -V | grep -o 'Python 3\.[0-9]\+' | cut -d " " -f 2)
endif

ifndef SLURM_VERSION
ifdef SLURM_SOURCE_TAG
SLURM_VERSION=$(shell echo $(SLURM_SOURCE_TAG) | grep -o '^slurm-[0-9]\+-[0-9]\+-[0-9]\+-[0-9]\+$$' | cut -d "-" -f 2-4 | tr "-" "." )
else
SLURM_VERSION_AUTODETECT="(autodetect, EXPERIMENTAL)"
SLURM_VERSION=$(shell srun --version | grep -o '^slurm [0-9]\+\.[0-9]\+\.[0-9]\+$$' | cut -d " " -f 2)
endif
endif

ifndef SLURM_SOURCE_TAG
SLURM_SOURCE_TAG_AUTODETECT="(autodetect, EXPERIMENTAL)"
SLURM_SOURCE_TAG_PREFIX=slurm-$(shell echo $(SLURM_VERSION) | tr '.' '-')-
SLURM_SOURCE_TAG=$(shell cd slurm && git tag -l --sort=-creatordate $(SLURM_SOURCE_TAG_PREFIX)* | head -n 1)
endif

ifndef SLURM_CONF_DIR
ifdef SLURM_CONF
SLURM_CONF_AUTODETECT="(autodetect)"
SLURM_CONF_DIR=$(shell echo $$(dirname $(SLURM_CONF)))
else
SLURM_CONF_AUTODETECT="(default)"
SLURM_CONF_DIR=/etc/slurm
endif
endif

ifdef DEBUG
PYTHON_VERSION:=$(PYTHON_VERSION)d
endif

SLURM_LIBRARY_FLAGS=-lslurm
PYTHON_CONFIG?=python$(PYTHON_VERSION)-config
PYTHON_INCLUDE_FLAGS=$(shell $(PYTHON_CONFIG) --includes)
PYTHON_LIBRARY_FLAGS=$(shell $(PYTHON_CONFIG) --libs) -lpython$(PYTHON_VERSION)
SLURM_SRC_DIR=$(PWD)/slurm
INCLUDES=-I$(SLURM_INCLUDE_DIR) -I$(SLURM_SRC_DIR) $(PYTHON_INCLUDE_FLAGS)
LIBS=$(PYTHON_LIBRARY_FLAGS) $(SLURM_LIBRARY_FLAGS)

CC=gcc

ifdef DEBUG
DEBUG_BUILD=Yes
DEBUG_TARGETS=Makefile
CFLAGS=-g -O0 -DDEBUG -Wall
else
DEBUG_BUILD=No
DEBUG_TARGETS=
CFLAGS=-O3 -Wfatal-errors
endif
CFLAGS+=-fPIC -std=c99 -DDEFAULT_SCRIPT_DIR=\"$(SLURM_CONF_DIR)\"

SOURCES=job_submit_python.c
OUTPUT_LIBRARY=job_submit_python.so
TEST_BINARY=test.out

$(OUTPUT_LIBRARY): $(SOURCES) slurm/git-tag-$(SLURM_SOURCE_TAG) $(DEBUG_TARGETS)
	$(MAKE) summary
	$(CC) $(SOURCES) -o $@ -shared $(CFLAGS) $(INCLUDES) $(LIBS)

$(TEST_BINARY): LIBS+=-lslurmfull-${SLURM_VERSION}
$(TEST_BINARY): $(SOURCES) slurm/git-tag-$(SLURM_SOURCE_TAG) Makefile
	$(MAKE) summary
	$(CC) $(SOURCES) -o $@ $(CFLAGS) $(INCLUDES) $(LIBS)

summary: slurm/config.h
	@echo [I] ========= Summary =========
	@echo [I] Python API Version: $(PYTHON_VERSION) $(PYTHON_VERSION_AUTODETECT)
	@echo [I] SLURM slurmctld API Version: $(SLURM_VERSION) $(SLURM_VERSION_AUTODETECT)
	@echo [I] SLURM source tag: $(SLURM_SOURCE_TAG) $(SLURM_SOURCE_TAG_AUTODETECT)
	@echo [I] SLURM slurm.conf directory: $(SLURM_CONF_DIR) $(SLURM_CONF_AUTODETECT)
	@echo [I] Debug: $(DEBUG_BUILD)
	@echo [I] CC: $(CC)
	@echo [I] CFLAGS: $(CFLAGS)
	@echo
	@sleep 3

slurm/config.h: slurm/git-tag-$(SLURM_SOURCE_TAG)
	cd slurm && ./configure $(SLURM_DOT_SLASH_CONFIGURE_FLAGS) -q && touch config.h || \
		( echo -e "Error: SLURM configure failed, please check log at $(SLURM_SRC_DIR)/config.log\n"; exit 1 )

slurm/git-tag-$(SLURM_SOURCE_TAG): slurm/TAGS
	cd slurm && \
	if [[ ! "$$(git describe --tags)" -eq "$(SLURM_SOURCE_TAG)" ]] || [[ ! -f ./config.h ]]; then \
		echo "git checkout $(SLURM_SOURCE_TAG) -f"; \
		git add . && git reset --hard && git checkout $(SLURM_SOURCE_TAG) -f; \
	fi
	touch slurm/git-tag-$(SLURM_SOURCE_TAG)

slurm/TAGS: .gitmodules
	if [[ ! -f slurm/TAGS ]]; then \
		echo "SLURM source is not checked out in submodule."; \
		echo "Initializing SLURM submodule..."; \
		git submodule update --init; \
		cd slurm && git tag -l --sort=-creatordate > TAGS; \
		echo -e "\nError: Makefile target changed after submodule init, please rerun make.\n"; exit 1; \
	fi

clean:
	-rm -f $(OUTPUT_LIBRARY) $(TEST_BINARY)

distclean:
	-rm -f $(OUTPUT_LIBRARY) $(TEST_BINARY)
	-git submodule deinit --all -f

install: summary $(OUTPUT_LIBRARY)
	if [[ ! -f $(OUTPUT_LIBRARY) ]]; then \
		echo "Error: $(OUTPUT_LIBRARY) not found, please `make` first."; \
		exit 1; \
	fi
	install $(OUTPUT_LIBRARY) $(SLURM_PLUGIN_INSTALL_DIR)

test:
	tests/run_local.sh
