local gsub = require('string').gsub
local byte = require('string').byte
local format = require('string').format

local function url_encode1(str)
  return gsub(str, '([%r%n%0%%])', function(c)
    return c and format('%%%02X', byte(c)) or '%00'
  end)
end

local function url_encode(str)
  s = ''
  for i = 1, #str do
    local c = str:sub(i,i)
    if c == '%' then c = '%25' end
    if c == '\0' then c = '%00' end
    if c == '\r' then c = '%0A' end
    if c == '\n' then c = '%0D' end
    s = s .. c
  end
  return s
end

p(url_encode('o%\rba\0r\nfoo'))
p(url_encode(' \r '))
