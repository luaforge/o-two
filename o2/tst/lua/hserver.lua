O2_PATH=";../../lua/?;"
LUA_PATH="?;?.lua;../lua/?" .. O2_PATH .. os.getenv("LUA_PATH")

require'util.lua'
VERB_LEVEL = 4
VERB_NAME = 'srv '

arg = arg or {}

arg.ior_out_file = 'testing.ref'

require"server.lua"

local apptest_impl = {
   say = function (self, msg)
      print(msg)
   end,
}

if true then
  io.input("../apptest.idl")
  apptest_idl = io.read"*a"
  IDL.parse(apptest_idl)
end

apptest_servant = lo_createservant(apptest_impl,"AppTest::Testing")

io.output(arg.ior_out_file)
io.write(apptest_servant:_get_ior())
io.close()
io.output(io.stdout)

while 1 and not SHOULD_QUIT do
  lo_handleRequest()
end
