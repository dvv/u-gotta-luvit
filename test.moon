class Foo
  new: () =>
  foo: -> p('FOO')

class Bar extends Foo
  bar: -> p('BAR')
