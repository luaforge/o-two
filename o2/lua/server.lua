-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "orbconfig.lua"
require "address.lua"
require "giop.lua"
require "idl.lua"
require "reflex.lua"
require "util.lua"
require "mir.lua"
require "concur.lua"

local srv_objects = {}
local objects2keys = {}
CorbaServer = {}

-- check for interface repository
if ORB_CONFIG.EXTERNAL_IR_REF then
	verb( 2, "Retrieving interface repository reference..." )
	verb( 2, ORB_CONFIG.EXTERNAL_IR_REF  )
	--io.input("../ref/ir.ref")
	--I = io.read('*a')
	_irep = IOR.normalform( ORB_CONFIG.EXTERNAL_IR_REF )
	if VERB_LEVEL >= 4 then
		pr( _irep )
	end
	--io.close()
	verb( 3, "Done." )
end

function register_ior( server, port, id, ior )
  assert(type(server) == 'string')  
  assert(type(id) == 'string' )
  assert(type(ior) == 'string' )
  port = port or '8448'
  port = tonumber(port)
  assert(type(port) == 'number')
  
  local s, err = connect( server, port )
  err = err or 'no error'
  assert( s, err..' connecting to '..server..':'..port )
  
  s:send( 'GET /put?id='..id..'&ior='..ior..' HTTP/1.0\n' )
  s:timeout( 5 )  
  if not string.find( s:receive(), 'OK' ) then
    return false
  else
    return true
  end
end

function retrieve_ior( server, port, id, ior )
  assert(type(server) == 'string')  
  assert(type(id) == 'string' )  
  port = port or '8448'
  port = tonumber(port)
  assert(type(port) == 'number')
  
  local s, err = connect( server, port )
  err = err or 'no error'
  assert( s, err..' connecting to '..server..':'..port )
  
  s:send( 'GET /get?id='..id..' HTTP/1.0\n' )
  s:timeout( 15 )  
  local data, err = s:receive( '*a' )
  err = err or 'no error'
  assert( data, err..' receiving from '..server..':'..port )
  if not string.find( data, '200 OK' ) then
    return nil
  end
  return string.gsub( data, '.-\n\n(.+)$', '%1' )  
end

function lo_treatRequest ( req, no )
	verb( 3, 'treating request' )
    local msg_h = CDR.get(req, GIOP.MessageHeader_1_0)   -- message header

    if msg_h.message_type ~= 0 then   -- is it not a request?
      verb( 1, "unexpected message: "..msg_h.message_type)
      return
    end
    local req_h = CDR.get(req, GIOP.RequestHeader_1_0)

    verb( 2, 'request for ', req_h.operation)

    -- find operation
    local opsig, opimpl
    local parms = {srv_objects[req_h.object_key]} 
  verb( 3, "** Looking for sig for "..req_h.object_key..":"..req_h.operation)
    if basicorbops[req_h.operation] then
      verb( 4, "** Basic stuff.")

      opsig = basicorbops[req_h.operation].sig
      opimpl = basicorbops[req_h.operation].impl
    else
      -- look for operation signature
      opsig = IR.getsig (srv_objects[req_h.object_key], req_h.operation) 
      verb( 4, '->> opsig for ', req_h.operation, type(opsig), tostring(opsig) )
      opimpl = srv_objects[req_h.object_key].impl[req_h.operation]
      if not opimpl then
        if opsig.kind == 'dk_Attribute' then
--print("dk_Attr over here") 	  
--pr(opsig)
	  local impl = srv_objects[req_h.object_key].impl
	  if opsig.action == 'get' then
	    opimpl = function (self)
	      return self[opsig.name]
	    end
	  else
	    opimpl = function (self, val)
	     self[opsig.name] = val
	    end
	  end
	  impl[req_h.operation] = opimpl
	else
		  -- TODO: correct this, implement exception throwing here
          error("object does not implement " .. req_h.operation )
	end
      end

      if nil and opsig.kind == 'dk_Attribute' then
        --process attribute
	local res
	if opsig.action == 'set' then
	  srv_objects[req_h.object_key].impl[req_h.operation] = parms[1]
	elseif opsig.action == 'get' then
	  res = opimpl
	  verb( 5, 'res', type(res))
	else
	  error("invalid attribute action "..tostring(opsig.action).." on "
	  	..req_h.operation)
	end
verb( 4, 'send_reply', req_h.request_id )
	GIOP.send_reply (nil, nil, opsig, res, no, req_h.request_id)
	return
      end

      -- read parameters
verb( 6, 'reading parameters: ')
if VERB_LEVEL >= 6 then
	table.foreach( opsig, print )
end
if opsig.params_in == nil then opsig = IDL.operation( opsig ) end 
--pr( opsig.params_in)
      for i = 1, table.getn(opsig.params_in) do
-- falta modificar o cdr para, ao ler um objeto,
-- verificar se e' local e fazer uma transformacao!!!
        table.insert (parms, CDR.get(req, opsig.params_in[i].type))
      end
    end

    -- call
    local res
    verb( 6, 'calling operation. unpacking parameter table:')
    --table.foreach(parms, print)
    verb( 6, 'end of unpack' )
    --res = {opimpl(unpack(parms))}
    --res = { pcall( opimpl, unpack(parms) )}
    res = { Concur:pcall( opimpl, unpack(parms) )}
    --res = { Concur:spawn( opimpl, unpack(parms) )}
    local except_type
    if res[1] == false then
    	verb( 1, 'got exception/error in call.' )
	if VERB_LEVEL >= 2 then
		pr( res )
	end
    	table.remove( res, 1 )
    	except_type = 'USER_EXCEPTION'
	opsig = { result = IDL.string, params_out = {} }
    else
    	table.remove( res, 1 )
    	except_type = nil
    end
    
    verb( 6, 'op '.. req_h.operation ..' returned. Sending reply with opsig' )
    verb_pr( 7, opsig )

    GIOP.send_reply (nil, nil, opsig, res, no, req_h.request_id, except_type)
end

function lo_handleRequest ()
    verb( 2, 'wait for request ')

    local req, no = GIOP.get_request()
    --return Concur:spawn( lo_treatRequest, req, no )
    return lo_treatRequest( req, no )
end

local stringified = function (myior)
  local ior = CDR.marshaling(myior, IOP.IOR, 1)
  return 'IOR:'.. IDL.tohexa (ior)
end

basicorbops = {
  _interface = {
    impl = function (self)
      local interface = IR.getinterface(self.type_id)
      --local interface = MIR:get_interface(self)
--[[--
print"**** interface retrieved:" 
pr(interface)
table.foreach( interface.profiles, print )
      assert (interface.profiles.n>0, "my type_id ".. self.type_id .. " not registered in IR!!!")
--]]--
      return interface
    end,
    sig = IDL.operation{
      result = IDL.Object( 'IDL:omg.org/CORBA/InterfaceDef:1.0' ),
      --result = MIR.IDLType:_new( 'IDL:omg.org/CORBA/InterfaceDef:1.0' ),
        parameters = {
        },
    }
  },
  _get_ior = {
    impl = function (self)
      return stringified(self.ior)
    end,
    sig = IDL.operation{
      result = IDL.string,
        parameters = {
        },
    }
  },
  _describe = {
    impl = function (self)
--print("*** _describe method called! "..tostring(self))
--pr(self)
    end,
    sig = IDL.operation {
      result = IDL.struct{
        {name="kind", type=IR.DefinitionKind},
        {name="value", type=IDL.any},
      },
      parameters = {
      },
    },
  },
}

local master, port
local servantno = 0

function lo_createservant (impl, type_id)
  assert( impl, 'nil servant' )
  assert( type_id, 'empty type_id' )
  type_id = type_id or ''
  --type_id = type_id or 'IDL:omg.org/CORBA/Object:1.0'

  -- is this object already a servant?
  if objects2keys[impl] then
    return srv_objects[objects2keys[impl]]
  end

  -- has this program registered as a server?
  if not master then
    master, port = GIOP.startServer()
  end

  -- does `type_id' use `::' notation?
  type_id = string.gsub(type_id, "::", "/")
  -- does it start with IDL?
  if string.find(type_id, "^IDL", 1) == nil then
    -- correct it
    type_id = "IDL:"..type_id..":1.0"
  end

  -- create key
  servantno = servantno + 1
  local mykey = tostring(servantno)..' tipo: '..type_id
  srv_objects[mykey] = {} 
  srv_objects[mykey].impl = impl
  objects2keys[impl] = mykey

  setmetatable(srv_objects[mykey], CorbaServer)

  -- create IOR

  local myprof_body = {
    iiop_version = {major = 1, minor = 0},
    --host = "localhost",
    host = ORB_CONFIG.LISTEN_HOST,
    port = port,
    object_key = mykey,
  }

  local body = CDR.marshaling(myprof_body, IIOP.ProfileBody_1_0, 1 )

  local myior = {
    type_id = type_id,
    profiles = {
      {tag = 0,
       profile_data = body
      }
    }
  }

  srv_objects[mykey].type_id = type_id
  srv_objects[mykey].ior = myior
  --srv_objects[mykey]:get_interface()


  return srv_objects[mykey]

end
 
CorbaServer.__index = function (obj, method)
  if basicorbops[method] then
    return (basicorbops[method].impl)
  else
    -- return rawget(obj.impl, method)
    -- why was this like this? It screwed up my meta inside impl
    local v = obj.impl[method]
    local ior = rawget( obj, 'ior' )
    if ior then
      v = v or rawget( ior, 'method' )
    end
    return v
  end
end



