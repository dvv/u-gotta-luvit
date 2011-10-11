--
-- creationix/Stack ported
--

local exports = {}

--
-- handles errors inside stack, both exceptions and soft errors
--
function exports.error_handler(req, res, err)
  if err then
    local reason = err
    print('\n' .. reason .. '\n')
    res:send(500, reason, {['Content-Type'] = 'text/plain'})
  else
    res:send(404, nil, {['Content-Type'] = 'text/plain'})
  end
end

--
-- given table of middleware layers, returns the function
-- suitable to pass as HTTP request handler
--
function exports.create(layers)
  local error_handler = exports.error_handler
  local handle = error_handler
  for i = #layers,1,-1 do
    local layer = layers[i]
    local child = handle
    handle = function(req, res)
      local status, err = pcall(layer, req, res, function(err)
        if err then return error_handler(req, res, err) end
        child(req, res)
      end)
      if err then error_handler(req, res, err) end
    end
  end
  return handle
end

--
-- given table of middleware layers, creates and returns listening
-- HTTP server.
-- E.g. create_server({layer1,layer2,...}, 3001, '127.0.0.1')
--
function exports.create_server(layers, port, host)
  local stack = exports.create(layers)
  local server = require('http').create_server(host or '0.0.0.0', port, stack)
  return server
end

exports.health = require('lib/stack/health')
exports.static = require('lib/stack/static')
exports.session = require('lib/stack/session').session
exports.auth = require('lib/stack/session').auth
exports.body = require('lib/stack/body')
exports.rest = require('lib/stack/rest')
exports.route = require('lib/stack/route')
exports.chrome = require('lib/stack/chrome')

-------------------------------------
-- augment Request and Response
-------------------------------------

local Request = require('request')
local Response = require('response')
local FS = require('fs')

function Response.prototype:safe_write(chunk, cb)
  self:write(chunk, function(err, result)
    if not err then cb(err, result) return end
    -- retry on EBUSY
    if err == 16 then
      self:safe_write(chunk, cb)
    else
p('WRITE FAILED', err)
      cb(err)
    end
  end)
end

function Response.prototype:send(code, data, headers)
--d('send', code, data, headers)
  self:write_head(code, headers or {})
  if data then
    self:safe_write(data, function() self:close() end)
  else
    self:close()
  end
end

function Response.prototype:render(template, data, options)
d('render', template, data)
      --if not data then data = req.context end

local function idem_renderer(template)
  return function(data)
    return template
  end
end

if not options then options = {} end
local renderer = options.renderer or idem_renderer

  FS.read_file(template, function(err, text)
    if err then
      self:send(404)
    else
      local html = renderer(text)(data)
      self:send(200, html, {
        ['Content-Type'] = 'text/html',
        ['Content-Length'] = #html,
      })
    end
  end)

end

-------------------------------------

-- export module
return exports
