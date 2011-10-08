local uv = require('uv')
local Stack = require('lib/stack')

--
-- collection of various helpers. when critical mass will accumulated
-- they should go to some lib file
--
function d(...)
  if env.DEBUG then p(...) end
end

function clone(obj)
  if type(obj) ~= 'table' then return obj end
  local x = {}
  for k, v in pairs(obj) do x[k] = v end
  return x
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

function stack()
  return {
    --[[function (req, res, nxt)
      --error('AAA')
      nxt()
    end,
    function (req, res, nxt)
      nxt()
    end,]]--
    require('lib/static')('/public/', '', {
      -- should the `file` contents be cached?
      is_cacheable = function(file) return true end,
    }),
--[[
    function (req, res, nxt)
      if req.method ~= 'GET' then
        p(req)
        req.socket:set_handler('read', function(data)
--        req:on('data', function(data)
          p('data coming' .. data)
        end)
        res:finish()
      else
        nxt()
      end
    end,]]--
    -- GET
    function (req, res, nxt)
      local s = ('Привет, Мир') --:rep(100)
      res:write_head(200, {
        ['Content-Type'] = 'text/plain',
        ['Content-Length'] = s:len()
      })
      res:write(s)
      res:finish()
    end
  }
end

Stack.create_server(stack(), 65401)
print('Server listening at http://localhost:65401/')
--Stack.create_server(stack(), 65402)
--Stack.create_server(stack(), 65403)
--Stack.create_server(stack(), 65404)
