#
# Make the canopen erlang implementation
#

MODULES = \
	canopen \
	co_crc \
	co_probe \
	co_test \
	co_format \
	co_file \
	co_sdo \
	co_mgr \
	co_transfer \
	co_session \
	co_sdo_cli_fsm \
	co_sdo_srv_fsm \
	co_tpdo \
	co_dict \
	co_codec \
	co_node \
	co_sdo_test



EBIN = ../ebin
ERLC = erlc

include ../vsn.mk
VSN=$(CAN_VSN)

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
