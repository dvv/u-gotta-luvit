local String = require('string')

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
  return self
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

function String:url_parse(parse_querystring)
  -- '(.-)(?.*)'
  local index = (self:find('?'))
  local uri = index and {
    pathname = self:sub(1, index - 1),
    search = self:sub(index + 1),
  } or {
    pathname = self,
    search = '',
  }
  if (parse_querystring) then
  end
  return uri
end

-- export module
return String
