REBAR = $(shell pwd)/rebar

.PHONY: deps test rel eunit

all: deps compile

compile:
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean:
	$(REBAR) clean
	-rm test/*.beam

distclean: clean
	$(REBAR) delete-deps

eunit: all
	$(REBAR) skip_deps=true eunit

test: all
	$(REBAR) skip_deps=true eunit ct

testclean:
	-rm -r .eunit
	-rm -r logs

generate:
	$(REBAR) generate

rel: deps compile generate
