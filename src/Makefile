#
# Make the canopen erlang implementation
#

#
# Behaviours compiled first
#
MODULES = \
	co_app \
	co_stream_app \
	co_tpdo_app \
	canopen \
	canopen_sup \
	co_codec \
	co_crc \
	co_data_buf \
	co_dict \
	co_file \
	co_format \
	co_iset \
	co_lib \
	co_mgr \
	co_node \
	co_os_app \
	co_probe \
	co_proc \
	co_sdo \
	co_sdo_cli_fsm \
	co_sdo_srv_fsm \
	co_set_fsm \
	co_session \
	co_sys_app \
	co_tpdo \
	eds_file



EBIN = ../ebin
ERLC = erlc

include ../vsn.mk
VSN=$(CANOPEN_VSN)

APP_FILE= canopen.app
APP_SRC= $(APP_FILE).src
APP_TARGET= $(EBIN)/$(APP_FILE)

override ERLC_FLAGS = -Wall -I ../include 

debug: ERLC_FLAGS += +debug_info -Ddebug

OBJS = $(MODULES:%=$(EBIN)/%.beam)
TARGET_FILES = $(OBJS) $(APP_TARGET)

all: $(TARGET_FILES)

debug: all

depend:
	edep -MM -o ../ebin $(ERLC_FLAGS) $(MODULES:%=%.erl) > depend.mk

dialyze:
	dialyzer --src -o dia.out -I ../include -c $(MODULES:%=%.erl) 

edoc:
	erl -noshell -pa doc -run edoc_run application "canopen" '".."' '[{private,false},no_packages,{sort_functions,false}]'

clean:
	rm -f $(OBJS) 

$(APP_TARGET): $(APP_SRC) ../vsn.mk
	sed -e 's;%VSN%;$(VSN);'  $< > $@

-include depend.mk

../ebin/%.beam:	%.erl
	erlc -o ../ebin $(ERLC_FLAGS) $<
