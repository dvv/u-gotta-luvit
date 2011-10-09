--
--
-- mime database
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
local IO = require('io')
for line in IO.lines('lib/mime.types') do
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
  local ext = filename:lower():match('([.]%w+)$')
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

-- export module
return exports
