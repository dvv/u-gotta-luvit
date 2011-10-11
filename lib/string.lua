local String = require('string')

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
  return self:gsub('&%w+;', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
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
    str = Sring.gsub(str, '\n', '\r\n')
    str = String.gsub(str, '([^%w ])',
      function (c) return String.format ('%%%02X', String.byte(c)) end)
    str = String.gsub(str, ' ', '+')
  end
  return str
end

-- export module
return String
