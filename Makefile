.PHONY: summary install clean test

#*Usually you do not need to change these
PYTHON_PATH=/usr/bin/python3 # use system python3
PYTHON_VERSION?=autodetect # e.g. 3.9 ; if not specify, try autodetect 
SLURM_VERSION?=autodetect # e.g. 23.02.7 ; if not specify, detected using slurmctld -V
SLURM_SOURCE_TAG?=autodetect # e.g. slurm-23-02-7-1 ; if not specify, will attempt select from source
SLURM_CONF_DIR?=autodetect # default: /etc/slurm ; if not specify, will attempt infer from SLURM_CONF before default
SLURM_INCLUDE_DIR?=/usr/include/slurm
SLURM_PLUGIN_INSTALL_DIR?=/usr/lib64/slurm/
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
SLURM_VERSION=$(shell slurmctld -V | grep -o '^slurm [0-9]\+\.[0-9]\+\.[0-9]\+$$' | cut -d " " -f 2)
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

CC=gcc

ifdef DEBUG
DEBUG_BUILD=Yes
CFLAGS=-g -O0 -DDEBUG -Wall -lslurmfull-${SLURM_VERSION}
else
DEBUG_BUILD=No
CFLAGS=-O3 -Wfatal-errors
endif
CFLAGS+=-fPIC -std=c99 -DDEFAULT_SCRIPT_DIR=\"$(SLURM_CONF_DIR)\"

SOURCES=job_submit_python.c
OUTPUT_LIBRARY=job_submit_python.so
TEST_BINARY=job_submit_python.out

$(OUTPUT_LIBRARY): $(SOURCES) slurm/config.h
	$(MAKE) summary
	$(CC) $(SOURCES) -o $@ -shared -I $(SLURM_INCLUDE_DIR) -I $(SLURM_SRC_DIR) $(PYTHON_INCLUDE_FLAGS) $(PYTHON_LIBRARY_FLAGS) $(SLURM_LIBRARY_FLAGS) $(CFLAGS)

$(TEST_BINARY): $(SOURCES) slurm/config.h
	$(MAKE) summary
	$(CC) $(SOURCES) -o $@ -I $(SLURM_INCLUDE_DIR) -I $(SLURM_SRC_DIR) $(PYTHON_INCLUDE_FLAGS) $(PYTHON_LIBRARY_FLAGS) $(SLURM_LIBRARY_FLAGS) $(CFLAGS)

summary:
	@echo ========= Summary =========
	@echo Python API Version: $(PYTHON_VERSION) $(PYTHON_VERSION_AUTODETECT)
	@echo SLURM slurmctld API Version: $(SLURM_VERSION) $(SLURM_VERSION_AUTODETECT)
	@echo SLURM source tag: $(SLURM_SOURCE_TAG) $(SLURM_SOURCE_TAG_AUTODETECT)
	@echo SLURM slurm.conf directory: $(SLURM_CONF_DIR) $(SLURM_CONF_AUTODETECT)
	@echo Debug: $(DEBUG_BUILD)
	@echo
	@sleep 3

slurm/config.h: slurm/src slurm/git-tag-$(SLURM_SOURCE_TAG)

slurm/git-tag-$(SLURM_SOURCE_TAG): slurm/src
	cd slurm && \
	if [ "$$(git describe --tags)" != "$(SLURM_SOURCE_TAG)" ] || [ ! -f config.h ]; then \
		git add . && git reset --hard && git checkout $(SLURM_SOURCE_TAG) -f && ./configure; \
	fi
	touch $@

slurm/src: .gitmodules
	git submodule update --init
	$(MAKE)

clean:
	-rm -f $(OUTPUT_LIBRARY) $(TEST_BINARY)

dist-clean:
	-rm -f $(OUTPUT_LIBRARY) $(TEST_BINARY)
	-git submodule deinit --all -f

install: $(OUTPUT_LIBRARY)
	install $(OUTPUT_LIBRARY) $(SLURM_PLUGIN_INSTALL_DIR)

test:
	tests/run_local.sh
