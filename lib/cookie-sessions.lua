#!/usr/bin/env luvit

--
--
-- keep small sessions safe in encrypted and signed cookies. by dvv, 2011
-- original idea: caolan/cookie-sessions
--
--

local exports = {}
--exports.__index = exports

local ffi = require('ffi')
ffi.cdef[[
char *crypt(const char *key, const char *salt);
]]
local Crypto = ffi.load('crypto')
--exports.__index = Crypto

function exports.read()
  return Crypto.crypt('foo', 'bar')
end

--p(exports)

exports.read()

-- export module
return exports
