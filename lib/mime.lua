--
--
-- mime type lookup. dvv, 2011, MIT Licensed
--
--

local exports = {
  -- file extension to mime type mapping
  table = {
    -- fallback mime type
    default = 'application/octet-stream',
    ['.lua'] = 'text/plain',
  }
}

-- read map from file
for line in io.lines('lib/mime.types') do
  if not line:find('#') then
    --print(line)
    local mime = nil
    for token in line:gmatch('([^%s]+)') do
      if not mime then
        mime = token
      else
        exports.table['.' .. token] = mime
        --p(mime, token)
      end
    end
  end
end
--p(table)

--
-- given filename, return its mime type
--
function exports.by_filename(filename)
  local ext_offset = filename:find('.', 0, true)
  local ext = ext_offset and filename:sub(ext_offset)
  --p(filename, ext_offset, ext)
  return exports.table[ext] or exports.table['default']
end

--
-- given file starting chunk, return its mime type
--
--[[
function exports.by_content(content)
  error('Not Yet Implemented (and unlikely will be :)')
end
]]--

--p(exports.by_filename('a.js'))

--[[

local Mime = require('mime')
p(Mime.table)
p(Mime.by_filename('a.js'))
Mime.table['.js'] = 'myspecial/type'
p(Mime.by_filename('a.js'))

]]--

-- export module
return exports
