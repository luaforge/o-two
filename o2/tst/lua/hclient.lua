O2_PATH=";../../lua/?;"
LUA_PATH="?;?.lua;../lua/?" .. O2_PATH .. os.getenv("LUA_PATH")

require'proxy.lua'
require'util.lua'
VERB_LEVEL = 4
VERB_NAME = 'cli '

require"server.lua"
io.input"../lua/testing.ref"
IORstr = io.read"*a"
assert(IORstr)
io.close()

if true then
	io.input("../apptest.idl")
	apptest_idl = io.read"*a"
	IDL.parse(apptest_idl)
end

testing_proxy = IOR.normalform(IORstr)
print('Proxy created: ',testing_proxy)

i = 0
while i < 7 do
  testing_proxy:say("Oi Lua " .. i)
  print("Send request " .. i ) 
  i = i + 1
end
