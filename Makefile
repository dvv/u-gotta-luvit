ROOT=$(shell pwd)

all: luvit json crypto

crypto: build/lua-openssl/openssl.so

build/lua-openssl/openssl.so:
	wget https://github.com/zhaozg/lua-openssl/tarball/master -O - | tar -xzpf - -C build
	mv build/zhaozg-lua-* build/lua-openssl
	sed -i 's,$$(CC) -c -o $$@ $$?,$$(CC) -c -I$(ROOT)/build/luvit/deps/luajit/src -o $$@ $$?,' build/lua-openssl/makefile
	make -C build/lua-openssl

json: build/lua-cjson/cjson.so

build/lua-cjson/cjson.so:
	wget http://www.kyne.com.au/~mark/software/lua-cjson-1.0.3.tar.gz -O - | tar -xzpf - -C build
	mv build/lua-cjson-* build/lua-cjson
	LUA_INCLUDE_DIR=$(ROOT)/build/luvit/deps/luajit/src make -C build/lua-cjson

luvit: build/luvit/build/luvit

build/luvit/build/luvit:
	mkdir -p build
	git clone https://github.com/creationix/luvit.git build/luvit
	make -C build/luvit

.PHONY: all crypto
