ROOT=$(shell pwd)
LUA_DIR=$(ROOT)/build/luvit/deps/luajit/src

all: luvit json
#crypto zeromq

luvit: build/luvit/build/luvit

build/luvit/build/luvit: build/luvit
	make -C $^

build/luvit:
	mkdir -p build
	git clone http://github.com/creationix/luvit.git build/luvit

json: build/lua-cjson/cjson.so

build/lua-cjson/cjson.so: build/lua-cjson
	LUA_INCLUDE_DIR=$(LUA_DIR) make -C $^

build/lua-cjson:
	wget http://www.kyne.com.au/~mark/software/lua-cjson-1.0.3.tar.gz -O - | tar -xzpf - -C build
	mv build/lua-cjson-* $@

crypto: build/lua-openssl/openssl.so

build/lua-openssl/openssl.so: build/lua-openssl
	sed -i 's,$$(CC) -c -o $$@ $$?,$$(CC) -c -I$(ROOT)/build/luvit/deps/luajit/src -o $$@ $$?,' build/lua-openssl/makefile
	make -C $^

build/lua-openssl:
	wget http://github.com/zhaozg/lua-openssl/tarball/master -O - | tar -xzpf - -C build
	mv build/zhaozg-lua-* $@

#
# requires cmake, uuid-dev, and libzmq-dev :(
#
zeromq: build/lua-zmq/build/zmq.so

build/lua-zmq/build/zmq.so: build/lua-zmq/build
	#apt-get install uuid-dev libzmq-dev cmake
	( cd $^ ; LUA_DIR=$(LUA_DIR) cmake .. )
	make -C $^

build/lua-zmq/build:
	wget http://github.com/Neopallium/lua-zmq/tarball/master -O - | tar -xzpf - -C build
	mv build/Neopallium-lua-* build/lua-zmq
	# lua-zmq will look for liblua, let's link libluajit
	#ln -sf libluajit.a $(LUA_DIR)/liblua.a
	ln -sf libluajit.so $(LUA_DIR)/liblua.so
	mkdir -p $@

.PHONY: all crypto
