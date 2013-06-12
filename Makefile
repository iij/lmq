REBAR = $(shell pwd)/rebar

.PHONY: deps test

all: deps compile

compile:
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean:
	$(REBAR) clean

distclean: clean
	$(REBAR) delete-deps

test:
	$(REBAR) skip_deps=true compile eunit ct
