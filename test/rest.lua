local JSON = require('cjson')

local handler = require('lib/stack/rest')('/rpc/', {
  jsonrpc = true,
  --put_new = '_new',
  context = {
    foo = {
      query = function(query, cb)
        p('FOO.query', query)
        cb(nil, { {a = 1, b = 2} })
      end,
      get = function(id, cb)
        p('FOO.get', id)
        cb(nil, {c = 2, d = 3})
      end,
      add = function(obj, cb)
        p('FOO.add', obj)
        cb(403)
      end,
      update = function(query, obj, cb)
        p('FOO.update', query, obj)
        cb(503)
      end,
      remove = function(query, cb)
        p('FOO.remove', query)
        cb(406)
      end,
    },
    bar = {
      baz = {
        query = function(query, cb)
          p('BAR.BAZ.query', query)
          cb(nil, { {a = 1, b = 2} })
        end,
        get = function(id, cb)
          p('BAR.BAZ.get', id)
          cb(nil, {c = 2, d = 3})
        end,
        add = function(obj, cb)
          p('BAR.BAZ.add', obj)
          cb(nil, obj)
        end,
        update = function(query, obj, cb)
          p('BAR.BAZ.update', query, obj)
          cb(403)
        end,
        remove = function(query, cb)
          p('BAR.BAZ.remove', query)
          cb(406)
        end,
      },
    },
  }
})

local res = {
  write_head = function(self, code, headers) p('write_head', code, headers) end,
  write = function(self, data) p('write', data) end,
  finish = function() p('finish') end,
}

local method = argv[2]
local url = argv[3]
local body = argv[4] and JSON.decode(argv[4]) or {}

p('url', url)
local req = { url = url, method = method, body = body, headers = {} }
handler(req, res, function() p('stop') end)
