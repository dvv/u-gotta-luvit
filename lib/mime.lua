local exports = {
  table = {
    default = 'application/octet-stream',
    ['.lua'] = 'text/plain'
  }
}
local IO = require('io')
for line in IO.lines('lib/mime.types') do
  if not line:find('#') then
    local mime = nil
    for token in line:gmatch('([^%s]+)') do
      if not mime then
        mime = token
      else
        exports.table['.' .. token] = mime
      end
    end
  end
end
exports.by_filename = function(filename)
  local ext = filename:lower():match('([.]%w+)$')
  return exports.table[ext] or exports.table.default
end
return exports
