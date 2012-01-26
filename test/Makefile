#
# Make the canopen test modules
#

MODULES = \
	co_test \
	co_test_lib \
	co_node_SUITE \
	co_sdo_srv_SUITE \
	co_sdo_cli_SUITE \
	co_os_SUITE \
	co_tpdo_SUITE \
	co_test_app \
	co_test_tpdo_app \
	co_test_stream_app \
	codec_bench


EBIN = .
ERLC = erlc

ERLDIR  := $(shell erl -noshell -eval "io:format([126,115,126,110],[code:root_dir()])" -s erlang halt)

override ERLC_FLAGS = -Wall -I ../include 

debug: ERLC_FLAGS += +debug_info -Ddebug

OBJS = $(MODULES:%=$(EBIN)/%.beam)

all: $(OBJS)

debug: all

depend:
	edep -MM -o ../ebin $(ERLC_FLAGS) $(MODULES:%=%.erl) > depend.mk

dialyze:
	dialyzer --src -o dia.out -I ../include -c $(MODULES:%=%.erl) 

edoc:
	erl -noshell -pa doc -run edoc_run application "canopen" '".."' '[{private,false},no_packages,{sort_functions,false}]'

clean:
	rm -f $(OBJS) 

test:
	$(ERLDIR)/bin/ct_run -include ../include -config co_test.cfg -suite co_node_SUITE

-include depend.mk

./%.beam:	%.erl
	erlc -o ../ebin $(ERLC_FLAGS) $<
