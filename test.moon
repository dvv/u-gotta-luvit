--EventEmitter = setmetatable({}, {__index: require('emitter').meta})

obj = {
  bar: (...) => p('BAR', ...)
}

class Foo
  new: (proto) =>
    p('NEW', self, proto)
    setmetatable self, __index: proto
  foo: -> p('FOO')

foo = Foo obj
foo\foo!
foo\bar 1
