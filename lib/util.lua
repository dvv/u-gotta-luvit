-----------------------------------------------------------
--
-- string helpers
--
-----------------------------------------------------------

String = require('string')

-- interpolation
function String:interpolate(data)
  if not data then
    return self
  elseif type(data) == 'table' then
    if data[1] then
      return self:format(unpack(b))
    else
      return (self:gsub('($%b{})', function(w)
        local var = w:sub(3, -2)
        local n, def = var:match('([^|]-)|(.*)')
        if n then var = n end
        local s = type(data[var]) == 'function' and data[var]() or data[var] or def or w
        s = s:escape()
        return s
      end))
    end
  else
    return self:format(data)
  end
end
getmetatable('').__mod = String.interpolate

function String:tohex()
  return (self:gsub('(.)', function(c)
    return String.format('%02x', String.byte(c))
  end))
end

function String:fromhex()
  return (self:gsub('(%x%x)', function(h)
    return String.format('%c', tonumber(h,16))
  end))
end

function String:escape()
  -- TODO: escape HTML entities
  --return self:gsub('&%w+;', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
  -- TODO: escape &
  return self:gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
  --return self
end

function String:unescape(s)
  -- TODO: unescape HTML entities
  return self
end

function String.url_decode(str)
  str = String.gsub(str, '+', ' ')
  str = String.gsub(str, '%%(%x%x)',
    function(h) return String.char(tonumber(h,16)) end)
  str = String.gsub(str, '\r\n', '\n')
  return str
end

function String.url_encode(str)
  if str then
    str = String.gsub(str, '\n', '\r\n')
    str = String.gsub(str, '([^%w ])',
      function (c) return String.format ('%%%02X', String.byte(c)) end)
    str = String.gsub(str, ' ', '+')
  end
  return str
end

-----------------------------------------------------------
--
-- collection of various helpers. when critical mass will accumulated
-- they should go to some lib file
--
-----------------------------------------------------------

Table = require('table')

function d(...)
  if env.DEBUG then p(...) end
end

-- is object an array
function is_array(obj)
  return type(obj) == 'table' and Table.maxn(obj) > 0
end

-- is object a hash
function is_hash(obj)
  return type(obj) == 'table' and Table.maxn(obj) == 0
end

-- shallow copy
function copy(obj)
  if type(obj) ~= 'table' then return obj end
  local x = {}
  setmetatable(x, {__index = obj})
  return x
end

-- deep copy of a table
-- FIXME: that's a blind copy-paste, needs testing
function clone(obj)
  local copied = {}
  local new = {}
  copied[obj] = new
  for k, v in pairs(obj) do
    if type(v) ~= 'table' then
      new[k] = v
    elseif copied[v] then
      new[k] = copied[v]
    else
      copied[v] = clone(v, copied)
      new[k] = setmetatable(copied[v], getmetatable(v))
    end
  end
  setmetatable(new, getmetatable(u))
  return new
end

function extend(obj, with)
  for k, v in pairs(with) do obj[k] = v end
  return obj
end

function extend_unless(obj, with)
  for k, v in pairs(with) do
    if obj[k] == nil then
      obj[k] = v
    end
  end
  return obj
end


-----------------------------------------------------------
--
-- augment Request and Response
--
-----------------------------------------------------------

local Request = require('request')
local Response = require('response')
local FS = require('fs')

function Response.prototype:safe_write(chunk, cb)
  self:write(chunk, function(err, result)
    if not err then cb(err, result) return end
    -- retry on EBUSY
    if err == 16 then
      self:safe_write(chunk, cb)
    else
p('WRITE FAILED', err)
      cb(err)
    end
  end)
end

function Response.prototype:send(code, data, headers)
--d('send', code, data, headers)
  self:write_head(code, headers or {})
  if data then
    self:safe_write(data, function() self:close() end)
  else
    self:close()
  end
end

function Response.prototype:render(template, data, options)
d('render', template, data)

  if not options then options = {} end
  local renderer = options.renderer

  FS.read_file(template, function(err, text)
    if err then
      self:send(404)
    else
      --local html = renderer(text)(data)
      local html = text % data
      self:send(200, html, {
        ['Content-Type'] = 'text/html',
        ['Content-Length'] = #html,
      })
    end
  end)

end

-------------------------------------

local UV = require('uv')
local FS = require('fs')

--
-- open file `path`, seek to `offset` octets from beginning and
-- read `size` subsequent octets.
-- call `progress` on each read chunk
--
local CHUNK_SIZE = 4096
local function noop() end
function stream_file(path, offset, size, progress, callback)
  UV.fs_open(path, 'r', '0666', function (err, fd)
    if err then return callback(err) end
    local function readchunk()
      local chunk_size = size < CHUNK_SIZE and size or CHUNK_SIZE
      UV.fs_read(fd, offset, chunk_size, function (err, chunk)
        if err or #chunk == 0 then
          callback(err)
          UV.fs_close(fd, noop)
        else
          chunk_size = #chunk
          offset = offset + chunk_size
          size = size - chunk_size
          if progress then
            progress(chunk, function()
              readchunk()
            end)
          end
        end
      end)
    end
    readchunk()
  end)
end
