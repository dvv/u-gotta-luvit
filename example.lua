local String = require('lib/string')
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

--[[
 *
 * Application
 *
]]--

local function authenticate(session, credentials, cb)
  -- N.B. this is simple "toggle" logic.
  -- in real world you should check credentials passed in `credentials`
  -- to decide whether to let user in.
  -- just assign `null` to session in case of error.
  -- session already set? drop session
  if session then
    session = nil
  -- no session so far? get new session
  else
    session = {
      uid = tostring(require('math').random()):sub(3),
    }
  end
  -- set the session
  cb(session)
end

local function authorize(session, cb)
  -- N.B. this is a simple wrapper for static context
  -- in real world you should vary capabilities depending on the
  -- current user defined in `session`
  if session and session.uid then
    cb({
      uid = session.uid,
      -- GET /foo?bar=baz ==> this.foo.query('bar=baz')
      foo = {
        query = function(query, cb)
          cb(nil, {['you are'] = 'an authorized user!'})
        end
      },
      bar = {
        baz = {
          add = function(data, cb)
            cb({['nope'] = 'nomatter you are an authorized user ;)'})
          end
        }
      },
      context = {
        query = function(query, cb)
          cb(nil, session or {})
        end
      },
    })
  else
    cb({
      -- GET /foo?bar=baz ==> this.foo.query('bar=baz')
      foo = {
        query = function(query, cb)
          cb(nil, {['you are'] = 'a guest!'})
        end
      },
      context = {
        query = function(query, cb)
          cb(nil, session or {})
        end
      },
    })
  end
end

local function stack() return {

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

  -- serve static files
  Stack.static('/public/', 'public/', {
    -- should the `file` contents be cached?
    --is_cacheable = function(file) return file.size <= 65536 end,
    --is_cacheable = function(file) return true end,
  }),

  -- handle session
  Stack.session({
    secret = 'change-me-in-production',
    ttl = 15 * 60 * 1000,
    -- called to get current user capabilities
    authorize = authorize,
  }),

  -- parse request body
  Stack.body(),

  -- process custom routes
  Stack.route({
    -- serve chrome page
    ['GET /'] = function(req, res, params, nxt)
      res:render('index.html', req.context, {renderer = String.interp})
    end,
    ['GET /foo'] = function(req, res, params, nxt)
      res:send(200, 'FOOO', {})
    end,
  }),

  -- handle authentication
  Stack.auth('/rpc/auth', {
    -- called to get current user capabilities
    authenticate = authenticate,
  }),

  -- RPC & REST
  Stack.rest('/rpc/'),

  -- GET
  function (req, res, nxt)
--d(req)
    local data = req.session and req.session.uid or 'Мир'
    local s = ('Привет, ' .. data) --:rep(100)
    res:write_head(200, {
      ['Content-Type'] = 'text/plain',
      ['Content-Length'] = s:len()
    })
    res:write(s)
    res:close()
  end,

  -- report health status to load balancer
  Stack.health(),

}end

Stack.create_server(stack(), 65401)
print('Server listening at http://localhost:65401/')
--Stack.create_server(stack(), 65402)
--Stack.create_server(stack(), 65403)
--Stack.create_server(stack(), 65404)
