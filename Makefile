.PHONY: all compile clean

all: compile

compile:
	echo "Fetching dependencies..."
	./rebar get-deps
	echo "Compiling..."
	./rebar compile


clean:
	./rebar clean

distclean: clean
	rm -rf ./deps/
