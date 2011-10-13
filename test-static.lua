require('lib/util')
local Stack = require('lib/stack')

local function layers() return {

  -- serve static files
  Stack.use('static')('/public/', 'public/', {
    -- should the `file` contents be cached?
    --is_cacheable = function(file) return file.size <= 65536 end,
    --is_cacheable = function(file) return true end,
  }),

  -- test serving requested amount of octets
  function(req, res, nxt)
    local n = tonumber(req.url:sub(2), 10)
    if not n then nxt() return end
    local s = (' '):rep(n)
    res:write_head(200, {
      ['Content-Type'] = 'text/plain',
      ['Content-Length'] = s:len()
    })
    res:safe_write(s, function()
      res:finish()
    end)
  end,

  -- report health status to load balancer
  Stack.use('health')(),

}end

Stack(layers()):run(65401)
print('Server listening at http://localhost:65401/')
--stack():run(65402)
--stack():run(65403)
--stack():run(65404)
