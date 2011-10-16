local obj = {
  bar = function(self, ...)
    return p('BAR', ...)
  end
}
local Foo
Foo = (function()
  local _parent_0 = nil
  local _base_0 = {
    foo = function()
      return p('FOO')
    end
  }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({
    __init = function(self, proto)
      p('NEW', self, proto)
      return setmetatable(self, {
        __index = proto
      })
    end
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  return _class_0
end)()
local foo = Foo(obj)
foo:foo()
foo:bar(1)
