#
# Make the canopen test modules
#

MODULES = \
	co_test \
	co_node_SUITE \
	co_test_app \
	co_stream_app


EBIN = .
ERLC = erlc


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


-include depend.mk

./%.beam:	%.erl
	erlc -o ../ebin $(ERLC_FLAGS) $<
