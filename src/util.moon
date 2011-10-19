-----------------------------------------------------------
--
-- string helpers
--
-----------------------------------------------------------

export String
String = require 'string'

-- interpolation
String.interpolate = (data) =>
  return self if not data
  if type(data) == 'table'
    return String.format(self, unpack(b)) if data[1]
    return String.gsub self, '($%b{})', (w) ->
      var = String.sub w, 3, -2
      n, def = String.match var, '([^|]-)|(.*)'
      var = n if n
      s = type(data[var]) == 'function' and data[var]() or data[var] or def or w
      s = String.escape s
      s
  else
    String.format self, data

getmetatable('').__mod = String.interpolate

String.tohex = (str) ->
  (String.gsub str, '(.)', (c) -> String.format('%02x', String.byte(c)))

String.fromhex = (str) ->
  (String.gsub str, '(%x%x)', (h) -> String.format('%c', tonumber(h,16)))

String.escape = (str) ->
  -- TODO: escape HTML entities
  --return self:gsub('&%w+;', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
  -- TODO: escape &
  String.gsub(str, '<', '&lt;')\gsub('>', '&gt;')\gsub('"', '&quot;')

String.unescape = (str) ->
  -- TODO: unescape HTML entities
  str

String.url_decode = (str) ->
  str = String.gsub str, '+', ' '
  str = String.gsub str, '%%(%x%x)', (h) -> String.char tonumber(h,16)
  str = String.gsub str, '\r\n', '\n'
  str

String.url_encode = (str) ->
  if str
    str = String.gsub str, '\n', '\r\n'
    str = String.gsub str, '([^%w ])', (c) -> String.format '%%%02X', String.byte(c)
    str = String.gsub str, ' ', '+'
  str

String.parse_query = (str) ->
  allvars = {}
  for pair in String.gmatch tostring(str), '[^&]+'
      key, value = String.match pair, '([^=]*)=(.*)'
      if key
          allvars[key] = String.url_decode value
  allvars

-----------------------------------------------------------
--
-- collection of various helpers. when critical mass will accumulated
-- they should go to some lib file
--
-----------------------------------------------------------

_G.Table = require 'table'

_G.d = (...) -> if process.env.DEBUG then p(...)

-- is object an array
_G.is_array = (obj) -> type(obj) == 'table' and Table.maxn(obj) > 0

-- is object a hash
_G.is_hash = (obj) -> type(obj) == 'table' and Table.maxn(obj) == 0

-- shallow copy
_G.copy = (obj) ->
  return obj if type(obj) != 'table'
  x = {}
  setmetatable x, __index: obj
  x

-- deep copy of a table
-- FIXME: that's a blind copy-paste, needs testing
_G.clone = (obj) ->
  copied = {}
  new = {}
  copied[obj] = new
  for k, v in pairs(obj)
    if type(v) != 'table'
      new[k] = v
    elseif copied[v]
      new[k] = copied[v]
    else
      copied[v] = clone v, copied
      new[k] = setmetatable copied[v], getmetatable v
  setmetatable new, getmetatable u
  new

_G.extend = (obj, with_obj) ->
  for k, v in pairs(with_obj)
    obj[k] = v
  obj

_G.extend_unless = (obj, with_obj) ->
  for k, v in pairs(with_obj)
    obj[k] = v if obj[k] == nil
  obj
