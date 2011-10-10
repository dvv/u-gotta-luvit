--
-- Provide req.session and user capabilities (req.context)
--

local exports = {}

local OS = require('os')
local Crypto = require('openssl')
local JSON = require('cjson')
local String = require('lib/string')

function expires_in(ttl)
  return OS.date('%c', OS.time() + ttl)
end

function sign(secret, data)
  local digest = Crypto.get_digest('sha1', secret)
  local mdc = digest:init()
  mdc:update(data)
  return mdc:final():tohex()
end

function encrypt(secret, data)
  local cipher = Crypto.get_cipher('aes192')
  return cipher:encrypt(data, secret):tohex()
end

function uncrypt(secret, data)
  local cipher = Crypto.get_cipher('aes192')
  return cipher:decrypt(data:fromhex(), secret)
end

function serialize(secret, obj)
  local str = JSON.encode(obj)
  local str_enc = encrypt(secret, str)
  local timestamp = OS.time()
  local hmac_sig = sign(secret, timestamp .. str_enc)
--p('ENC', hmac_sig, timestamp, str_enc)
  local result = hmac_sig .. timestamp .. str_enc
  return result
end

function deserialize(secret, ttl, str)
  local hmac_signature = str:sub(1, 40)
  local timestamp = tonumber(str:sub(41, 50), 10)
  local data = str:sub(51)
--p(DEC, hmac_signature, timestamp, data)
  local hmac_sig = sign(secret, timestamp .. data)
  if hmac_signature ~= hmac_sig or timestamp + ttl <= OS.time() then
    return nil
  end
  local data = uncrypt(secret, data)
  return JSON.decode(data)
end

function exports.read_session(key, secret, ttl, req)
  local cookie = type(req) == 'string' and req or req.headers.cookie
  if cookie then
    cookie = cookie:match('%s*;*%s*' .. key .. '=(%w*)')
    if cookie and cookie ~= '' then
--d('raw read', cookie)
      return deserialize(secret, ttl, cookie)
    end
  end
  return nil
end

--
-- we keep sessions safely in encrypted and signed cookies.
-- inspired by caolan/cookie-sessions
--
function exports.session(options)

  -- defaults
  if not options then options = {} end
  local key = options.key or 'sid'
  local ttl = options.ttl or 15 * 24 * 60 * 60 * 1000
  local secret = options.secret --or 'change-me-in-production'
  local context = options.context or {}

  -- handler
  return function(req, res, nxt)

    -- read session data from request and store it in req.session
    req.session = exports.read_session(key, secret, ttl, req)

    -- proxy write_head to add cookie to response
    -- TODO: res.req = req ; then it's possible to avoid making this
    -- closure for each request
    local _write_head = res.write_head
    res.write_head = function(self, status, headers)
      local cookie
      if not req.session then
        if req.headers.cookie then
          cookie = ('%s=; expires=; httponly; path=/'):format(
            key,
            expires_in(0)
          )
        end
      else
        cookie = ('%s=%s; expires=; httponly; path=/'):format(
          key,
          serialize(secret, req.session),
          expires_in(ttl)
        )
      end
      -- Set-Cookie
      -- FIXME: support multiple Set-Cookie:
      if cookie then
        if not headers then headers = {} end
        headers['Set-Cookie'] = cookie
      end
      -- call original method
--d('response with cookie', headers)
      return _write_head(self, status, headers)
    end

    -- always create a session if options.default_session specified
    if options.default_session and not req.session then
      req.session = options.default_session
    end

    -- use authorization callback if specified
    if options.authorize then
      -- given current session, return context
      options.authorize(req.session, function(context)
        req.context = context or {}
        nxt()
      end)
    -- assign static context
    else
      -- default is guest context
      req.context = context.guest or {}
      -- user authenticated?
      if req.session and req.session.uid then
        -- provide user context
        req.context = context.user or req.context
      end
      -- FIXME: admin context somehow?
      nxt()
    end
  
  end

end

--
-- Handle signin/signout
--
function exports.auth(url, options)

  -- defaults
  if not url then url = '/rpc/auth' end
  if not options then options = {} end

  return function(req, res, nxt)

    if req.url == url then
      -- given current session and request body, request new session
      options.authenticate(req.session, req.body, function(session)
        -- falsy session means to remove current session
        req.session = session
        -- go back
        res:write_head(302, {
          ['Location'] = req.headers.referer or req.headers.referrer or '/'
        })
        res:finish()
      end)
    else
      nxt()
    end

  end

end

-- tests
if false then
local secret = 'foo-bar-baz$'
local obj = {a = {foo = 123, bar = "456"}, b = {1,2,nil,3}, c = false, d = 0}
local ser = serialize(secret, obj)
p(ser)
local deser = deserialize(secret, 1, ser)
-- N.B. nils are killed
p(deser, deser == obj)
end

-- export module
return exports
