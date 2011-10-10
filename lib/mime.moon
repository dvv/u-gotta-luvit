--
--
-- mime database
--
--

exports =
  -- file extension to mime type mapping
  table:
    -- fallback mime type
    default: 'application/octet-stream'
    ['.lua']: 'text/plain'

-- read map from file
IO = require 'io'
for line in IO.lines 'lib/mime.types'
  if not line\find '#'
    --print line
    mime = nil
    for token in line\gmatch '([^%s]+)'
      if not mime
        mime = token
      else
        exports.table['.' .. token] = mime
        --p mime, token
--p table

--
-- given filename, return its mime type
--
exports.by_filename = (filename) ->
  ext = filename\lower()\match '([.]%w+)$'
  exports.table[ext] or exports.table.default

-- export module
return exports
