
--| Simple reference server. Listens on given port and manages IORs.
--| Can process any (text) data, really.

--$Id: servref.lua,v 1.1 2004-07-21 03:16:01 rmello Exp $
--b Pedro Miller Rabinovitch <miller@inf.puc-rio.br>

arg = arg or {}

-- files to be served (besides put-fed data)
local local_files = {
	Lppt = '../ppt/pclient.lua',
	Lfred = '../fred.lua',
}

-- IOR (actually, information) database.
local ior_db = { hello='Hullo!' }

function read_all (filename)
	assert(type(filename) == 'string')
	fin = io.open(filename, 'r')
	if fin == nil then
		return nil
	end
	local data = fin:read"*a"
	fin:close()
	return data
end

for i, v in local_files do 
	print(v)
	local data = read_all( v )
	if data == nil then
		print( "warning: couldn't read local file "..v )
	else
		print( "read local file "..v )
		ior_db[i] = data
	end
end

--% Listen for commands that come HTTP-style.
-- GET /get?id=hello
-- GET /put?id=hello&ior=IOR00234823749812734...
function big_server()
   arg.port = tonumber( arg.port )
   assert( arg.port and arg.port > 0, "invalid port number" )
   
   local ms = bind( "*", arg.port )
   while 1 do
      print"- ready;"
      local s = ms:accept()
      print"- got connection. Receiving command;"
      local cmd = s:receive()      
      print( cmd )
      
      local reply = process_cmd( cmd )
      
      print"- sending reply;"
      s:send( "HTTP/1.0 200 OK\nContent-type: text/plain\n\n" )
      s:send( reply or "" )
      
      s:close()
   end
end

--% Process a command line.
--% Parses a (simple) HTTP command line.
--@ line (string) The HTTP command.
--: (string) The required information.
function process_cmd( line )
   local _, __, cmd = string.find( line, '^GET /([a-z]+)' )
   line = string.gsub( line, '^.- (.-) .-$', '%1' )
   local id, val
   _, __, id = string.find( line..'&', 'id=(.-)&' )
   if not id then
      return "Missing `id' argument.\n"
   end
   id = string.gsub( id, '+', ' ' )   
   
   if cmd == 'put' then
      _, __, ior_db[id] = string.find( line..'&', 'ior=(.-)&' )
      return 'Done.\n'
   elseif cmd == 'get' then
      return ior_db[id]..'\n'
   else
      return "Unknown command: "..(cmd or 'nil').."\n"
   end
end


--% Go into fast-serving mode.
--% Broadcast data from io input to all connectees without
--% further ado.
function read_and_serve ()
	arg.port = tonumber( arg.port )
	assert( arg.port and arg.port > 0, "invalid port number" )
	
	data = io.read"*a"

	assert( type(data) == 'string' )

	local ms = bind( "*", arg.port )
	while 1 do
		print"- ready;"
		s = ms:accept()
		print"- got connection. Sending data;"
		print( s:send( data ))
	  s:close()
	end
end

--% Convert a corbaloc: reference to an IOR
--@ str (string) corbaloc string to be converted
--@ type_id (string) object reference's type RepositoryId
--: (string) IOR to referenced object
function corbaloc_to_ior( str, type_id )
	assert( type(str) == 'string' )
	require"idl.lua"
	require"cdr.lua"
	require"address.lua"

	local a, b, host, port, objkey = 
		string.find (str, "corbaloc::([%w._-]+):?(%d*)/(.+)")

	local prof_body = {
		iiop_version = {major = 1, minor = 0},
		host = host,
		port = port,
		object_key = objkey,
	}

	local body = CDR.marshaling(prof_body, IIOP.ProfileBody_1_0, 1 )

	local myior = {
		type_id = type_id,
		profiles = {
			{ tag = 0, profile_data = body }
		}
	}

	return IDL.tohexa(CDR.marshaling(myior, IOP.IOR, 1))
end

-- main processing
if arg[1] == '-c' then
	print"corbaloc: conversion mode."
	local url = io.read()
	local type_id = io.read()
	print( corbaloc_to_ior( url, type_id ))
elseif arg[1] == '-s' then
   print"Cool server mode."
   arg.port = arg[2] or 8448
   big_server()
else
   arg.port = arg[1] or 33033
	read_and_serve()
end

