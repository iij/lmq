REBAR = $(shell pwd)/rebar

.PHONY: deps test rel

all: deps compile

compile:
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean:
	$(REBAR) clean

distclean: clean
	$(REBAR) delete-deps

test: all
	$(REBAR) skip_deps=true eunit ct

generate:
	$(REBAR) generate

rel: deps compile generate
