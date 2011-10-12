local mime = require('mime').get_type

assert(mime('.aa.bb.cc.dd.js') == 'application/javascript')
assert(mime('Привет.Солнечный.Мир.Css') == 'text/css')
require('mime').default = 'foo/bar'
assert(mime('Привет.Солнечный.Мир') == 'foo/bar')
