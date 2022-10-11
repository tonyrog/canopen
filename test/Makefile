#
# Make the canopen test modules
#

MODULES = \
	co_test \
	co_test_lib \
	co_node_SUITE \
	co_nmt_SUITE \
	co_os_SUITE \
	co_proc_SUITE \
	co_script_SUITE \
	co_sdo_cli_SUITE \
	co_sdo_srv_SUITE \
	co_tpdo_SUITE \
	co_test_app \
	co_test_tpdo_app \
	co_test_stream_app \
	co_test_dict_app \
	co_ex_app \
	codec_bench \
	co_codec_SUITE

DEPDIR = depend
ERLC = erlc
EBIN = .

ERLDIR  := $(shell erl -noshell -eval "io:format([126,115,126,110],[code:root_dir()])" -s erlang halt)

override ERLC_FLAGS = -Wall -I ../include  +nowarn_export_all

debug: ERLC_FLAGS += +debug_info -Ddebug

COMPILE.erl = $(ERLC) $(DEPFLAGS) $(ERLC_FLAGS)

OBJS = $(MODULES:%=$(EBIN)/%.beam)

all: $(OBJS)

debug: all

dialyze:
	dialyzer --src -o dia.out -I ../include -c $(MODULES:%=%.erl) 

edoc:
	erl -noshell -pa doc -run edoc_run application "canopen" '".."' '[{private,false},no_packages,{sort_functions,false}]'

clean:
	rm -f $(OBJS) 

test:
	$(ERLDIR)/bin/ct_run -include ../include -config co_test.cfg # -suite co_node_SUITE

test_all:
	$(ERLDIR)/bin/ct_run -include ../include -config co_test.cfg

$(shell mkdir -p $(DEPDIR) >/dev/null)
DEPFLAGS = -MT $@ -MMD -MP -MF $(DEPDIR)/$*.Td

POSTCOMPILE = mv -f $(DEPDIR)/$*.Td $(DEPDIR)/$*.d

$(EBIN)/%.beam:	%.erl $(DEPDIR)/%.d
	$(COMPILE.erl) -o $(EBIN) $(ERLC_FLAGS) $<
	$(POSTCOMPILE)

$(DEPDIR)/%.d: ;
.PRECIOUS: $(DEPDIR)/%.d

-include $(patsubst %,$(DEPDIR)/%.d,$(basename $(ALLSRC)))
