-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "idl.lua"
require "cdr.lua"
require "address.lua"
require "luasocket"

O2Socket = socket
GIOP = {}

local Version = IDL.struct{{name="major",type=IDL.octet},
                           {name="minor",type=IDL.octet}}


GIOP.MessageHeader_1_0 = IDL.struct{
  {name="magic",type=IDL.array{IDL.char;length=4}},
  {name="GIOP_version",type=Version},
  {name="byte_order",type=IDL.boolean},
  {name="message_type",type=IDL.octet},
  {name="message_size",type=IDL.ulong}
}


-- the same, but without size (we need the flags before we can read the size)
local ReadHeader = IDL.struct{
  {name="magic",type=IDL.array{IDL.char;length=4}},
  {name="GIOP_version",type=Version},
  {name="byte_order",type=IDL.boolean},
  {name="message_type",type=IDL.octet},
}

local IORAddressingInfo = IDL.struct{
  {name="selected_profile_index", type=IDL.ulong},
  {name="ior", type=IOP.IOR}
}


local ServiceContext = IDL.struct{
  {name="context_id", type=IDL.ulong},
  {name="context_data", type=IDL.sequence{IDL.octet}},
}

GIOP.RequestHeader_1_0 = IDL.struct{
  {name="service_context",type=IDL.sequence{ServiceContext}},
  {name="request_id",type=IDL.ulong},
  {name="response_expected",type=IDL.boolean},
  {name="object_key",type=IDL.sequence{IDL.octet}},
  {name="operation",type=IDL.string},
  {name="requesting_principal",type=IDL.sequence{IDL.octet}},
}


local ReplyStatusType_1_0 = IDL.enum{
  "NO_EXCEPTION", "USER_EXCEPTION", "SYSTEM_EXCEPTION", "LOCATION_FORWARD",
}

GIOP.ReplyHeader_1_0 = IDL.struct{
  {name="service_context",type=IDL.sequence{ServiceContext}},
  {name="request_id",type=IDL.ulong},
  {name="reply_status", type=ReplyStatusType_1_0},
}


--------------------------------------
-- basic call

local rq_Header = {
  magic = "GIOP",
  GIOP_version = {major=1, minor=0},
  byte_order = nil,  -- ENDIAN
  message_type = 0,  -- request
  message_size = 0,
}


local Request = {
  service_context = {},
  response_expected = 1,
  requesting_principal = {},
  request_id = 0,
}

local create_request = function (obj, method, args, sig)
  Request.request_id = Request.request_id + 1
  Request.object_key = obj.object_key
  Request.operation = method
  if table.getn(args) ~= table.getn(sig.params_in) then
    verb( 1, 'expected '..table.getn(sig.params_in)..' arguments, got '..table.getn(args) )
    pr( sig.params_in )
    print '=============='
    pr( args )
    error("wrong number of arguments")
  end
  local state = CDR.writebuffer("123456789012")
  CDR.set(state, Request, GIOP.RequestHeader_1_0)
  for i = 1,table.getn(args) do
    CDR.set(state, args[i], sig.params_in[i].type)
  end
  local buff = string.sub(CDR.finalwrite(state), 13)   -- remove alignment dummy
  rq_Header.message_size = string.len(buff)
  rq_Header.message_type = 0
  buff = CDR.marshaling(rq_Header, GIOP.MessageHeader_1_0) .. buff
  return buff
end


local get_reply = function (socket)
  local reply, err = socket:receive(12)   -- receives reply's header
  --assert(reply, err) print(reply, err)
  if err == "closed" then
    return nil, err
  end
  assert(string.sub(reply, 1, 4) == "GIOP")
  local order = string.byte(reply, 7)
  local buffer = CDR.createBuffer(reply)
  CDR.setorder(buffer, order)
  CDR.setpos(buffer, 9)
  size = CDR.get(buffer, IDL.ulong)
  reply = reply .. socket:receive(size)   -- receive rest of the message
  buffer = CDR.createBuffer(reply)
  CDR.setorder(buffer, order)

  if VERB_LEVEL >= 11 then
    io.write('reply got:')
    string.gsub( reply, '(.)', function(c) io.write( string.byte( c )..' ') end )
    io.write('\n')
  end
  
  return buffer
end


local get_replyheader = function (sig, reply)
  local reply_h = CDR.get(reply, GIOP.ReplyHeader_1_0)
  return reply_h.reply_status
end

local handleexc = function (obj, sig, reply)
  local repId = CDR.get(reply, IDL.string)
  if not sig.exceptions[repId] then
    error("undeclared exception returned "..repId)
  end
  -- get exception
  local exc = CDR.get(reply,  sig.exceptions[repId].type)
  -- invoke handler
  if obj.exc_handlers[sig.exceptions[repId].name] then
    return obj.exc_handlers[sig.exceptions[repId].name](exc)
  else
    return nil
  end 
end

local getresults = function (sig, reply)
  local results = {CDR.get(reply, sig.result)}
  
  verb( 4, "[getresults: number of results: ",table.getn(results),"]")
  if 6 <= VERB_LEVEL then
    table.foreachi( results, function (i, v)
                               if type(v) == "table" then
                                 print( i..":" )
                                 table.foreach( v, print )
                               else
                                 print( i, v )
                               end
                             end ) 
  end
  
  for i=1, table.getn(sig.params_out) do
    table.insert(results, CDR.get(reply, sig.params_out[i].type))
    verb( 5, "[getresults: param out ",i,results[table.getn(results)],"]")
  end
  return unpack(results)
end


local connections = {}
--setmode(connections, 'v') --  <<- GC in LuaSockets is buggy
setmetatable( connections, { __mode = 'v' } )

local open_connection = function (host, port)
  local key = host .. ':' .. port
--  desativamos a manitencao de conexoes abertas
--  refazer depois que passarmos para 5.0!!!
  local sq = connections[key]
  if sq then
    verb( 4, "Found connection in cache.")
    pr( connections )
    -- ok, return this socket, it's all good
    return sq 
  end
  -- otherwise, establish new connection
  local err
  
  sq, err = O2Socket.connect(host, port)
  err = err or 'no'
  assert(sq, err.." connecting to "..host..":"..port)
  connections[key] = sq
  return sq
end

local close_connection = function (sock)
  -- por enquanto fechando a cada pedido! refazer qdo passarmos pra 5.0!
  --rmello: se fecharmos o socket aqui, ele vai continuar nao nulo na tabela e 
  -- pode gerar segmentation fault. ?Bug in luasocket 2.0 alpha ?
 --sock:close()
end

function GIOP.call (obj, method, args, sig)
  verb( 6, 'GIOP.call', obj, method, args, sig )

  local iobj = IOR.openIIOP(obj)
  if iobj == nil then
    verb( 6, 'attempting local call' )
    return obj[method]( obj, unpack( args ))
  end
  assert( iobj, 'got nil object from IIOP' )
  local request = create_request(iobj, method, args, sig)
  local sq, reply, err

  repeat 
    local sq = open_connection(iobj.host, iobj.port)
    
    -- Changed in luasocket 2.0alpha .. change again in beta ?
    if( O2Socket == socket ) then
      assert(sq:send(request), "connection error sending request")
    else
      assert(sq:send(request) == nil, "connection error sending request")
    end

    reply, err = get_reply(sq)
  -- should loop at most once 
  -- what should we do if we get a timeout? Exception?
  -- shouldn't get stuck in infinite retries here.
  until err ~= "closed"
  
  --close_connection(sq)

  local reply_h = CDR.get(reply, GIOP.MessageHeader_1_0)   -- message header
  if reply_h.message_type ~= 1 then   -- is it not a reply?
    error("unexpected message: "..reply_h.message_type)
  end
  local rep_status = get_replyheader(sig, reply)

--print("[GIOP.call: rep_status: ", rep_status, "]" )
  
  if rep_status == "NO_EXCEPTION" then
    return getresults(sig, reply)
  elseif rep_status == "LOCATION_FORWARD" then
    return GIOP.call(CDR.get(reply, IDL.Object()), method, args, sig)
  elseif rep_status == "USER_EXCEPTION" then
    return handleexc(obj, sig, reply)
  else
    error("reply status: "..rep_status)
  end
end

local socket_master 
local srvmustwatch = {}

function GIOP.startServer (port)
  local ms, error, host 
  host = ORB_CONFIG.LISTEN_HOST or '*'
  if port then  
    ms, err = O2Socket.bind(host, port)
    if not ms then
      error("bind error"..err)
    end
  else
    port = 30000
    repeat  -- should we limit the number of trials?
      port = port + 1
      ms, err = O2Socket.bind(host, port)
    until ms
  end
  socket_master = ms
  table.insert( srvmustwatch, ms )
  return ms, port
end

local accept_conn = function ()
  local s, err = socket_master:accept()
  if s then
    table.insert( srvmustwatch, s )
    return s
  else error("error on accept!")
  end
end

local getsocket = function (socks)
  for i,s in socks do
      if s == socket_master then
        accept_conn()
      else
        return s
      end
  end
  return nil
end

local reqno = 0
local pendingrequests = {}

GIOP.get_request = function ()
  local ready
  local sock, pos
  local request
  
  repeat
    ready = O2Socket.select(srvmustwatch, nil)

    sock = getsocket(ready)
    if sock then
      request, err = sock:receive(12)   -- receives request's header
      if err=='closed' then
        request = nil -- should be the value returned by receive!!!
        for i, v in ipairs(srvmustwatch) do
          if v == sock then
            table.remove( srvmustwatch, i ) -- connection closed - don't look at this anymore!
          end
        end
      end
    end
  until request
  
  assert(string.sub(request, 1, 4) == "GIOP")
  local order = string.byte(request, 7)
  local buffer = CDR.createBuffer(request)
  CDR.setorder(buffer, order)
  CDR.setpos(buffer, 9)
  size = CDR.get(buffer, IDL.ulong)
  request = request .. sock:receive(size)   -- receive rest of the message
  buffer = CDR.createBuffer(request)
  
  reqno = reqno+1
  pendingrequests[reqno] = sock

  CDR.setorder(buffer, order)
  
  return buffer, reqno
end


local Reply = IDL.struct{
  service_context = {},
  request_id = 1,
  reply_status = "NO_EXCEPTION",
}

local rp_Header = {
  magic = "GIOP",
  GIOP_version = {major=1, minor=0},
  byte_order = nil,  -- ENDIAN
  message_type = 1,  -- reply
  message_size = 0,
}

-- this moved inside CDR.set
local marshal = CDR.set

local create_reply = function (sig, res, rn, req_id, except_type)

  Reply.request_id = req_id
  if except_type then
    Reply.reply_status = 'USER_EXCEPTION'
  else
    Reply.reply_status = 'NO_EXCEPTION'
  end
  assert( req_id )
  local state = CDR.writebuffer("123456789012")
  CDR.set(state, Reply, GIOP.ReplyHeader_1_0)
  local res_idx = 0

  -- this should be done if sig.result is not void. Sometimes
  -- we have results (out parameters) for void functions.
  verb( 7, 'marshalling this kind of result:' )
  verb_pr( 7, sig.result )
  if sig.result ~= IDL.void then
    res_idx = res_idx + 1
    verb_pr( 8, res[res_idx] )
    marshal(state, res[res_idx], sig.result)
  end

  -- some return values may be nil (e.g., boolean returns for people used to Lua 4)
  for i = 1,table.getn(sig.params_out) do
    marshal(state, res[res_idx+i], sig.params_out[i].type)
  end

--print("state:",string.len(state.s), IDL.tohexa(state.s))

  local buff = string.sub(CDR.finalwrite(state), 13)   -- remove alignment dummy
  rp_Header.message_size = string.len(buff)
  rp_Header.message_type = 1
  buff = CDR.marshaling(rp_Header, GIOP.MessageHeader_1_0) .. buff

--print("reply:",string.len(buff), IDL.tohexa(buff))
  
  return buff
end

GIOP.send_reply = function (obj, meth, sig, results, rn, req_id, except_type)
  assert( req_id )
  pendingrequests[rn]:send(create_reply(sig, results, rn, req_id, except_type))
  -- don't close it anymore
  -- close(pendingrequests[rn])
  pendingrequests[rn] = nil
end
