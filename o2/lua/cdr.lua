-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "idl.lua"
require "tcode.lua"
require "proxy.lua"


-- definitions for Object

local IOR = IDL.struct{
     {name="type_id", type=IDL.string},
     {name="profiles",
        type=IDL.sequence{IDL.struct{
          {name="tag", type = IDL.alias{IDL.ulong}},
          {name="profile_data", type = IDL.sequence{elementtype=IDL.octet}}
        }}
     }
}


--{-------------------------------------------------------------
-- unmarshalling
----------------------------------------------------------------
do


local private = {}

CDR = {}

CDR.createBuffer = function (octet_seq, getorder)
  local state = {}
  state._buffer = octet_seq
  state._cursor = 1
  if getorder then
    CDR.setorder(state, bitlib.unpack("B", octet_seq))
    state._cursor = 2
  end
  return state 
end

function CDR.setorder (state, order)
  state._order = (order == 0) and ">" or "<"
end

function CDR.setpos (state, pos)
  state._cursor = pos
end

private.string = function (state)
  local length = private.ulong(state) --ULong()
  local string = string.sub(state._buffer,state._cursor,state._cursor + length -2)
  state._cursor = state._cursor + length
  return string
end

private.octet = function (state)
  local val = bitlib.unpack("B", state._buffer, state._cursor)
  state._cursor = state._cursor + 1
  return val
end

private.char = function (state)
  local pos = state._cursor
  local val = string.sub(state._buffer, pos, pos)
  state._cursor = pos + 1
  return val
end

private.boolean = function (state)
--print(string.len(state._buffer))
--print(IDL.tohexa(state._buffer))
--table.foreach(state, print)
  return (private.octet(state) ~= 0)
end

local alignment = function (state,n)
  local d = math.mod(state._cursor-1,n)
  if d ~= 0 then
    state._cursor = state._cursor + (n - d)
  end
end

CDR.align = alignment

local create_getnumber = function (size, format)
  local alignment = alignment  -- 4.0
  return function (state)
    alignment(state, size)
--print("state._buffer length: ", string.len(state._buffer), "state._cursor: ", state._cursor)
    local n = bitlib.unpack(state._order..format, state._buffer, state._cursor)
    state._cursor = state._cursor + size
    return n
  end
end

private.void = function (s, f) return nil end

private.ushort = create_getnumber(2, "S")

private.short = create_getnumber(2, "s")

private.ulong = create_getnumber(4, "L")

private.long = create_getnumber(4, "l")

private.float = create_getnumber(4, "f")

private.double = create_getnumber(8, "d")


private.alias = function (state,type)
  return CDR.get(state,type.type) 
end

private.TypeCode = function (state)
  return typecode(state)
end

private.struct = function (state, type)
  local result = {}
  for i=1,table.getn(type) do
    local v = type[i]
    result[v.name] = CDR.get(state,v.type)
  end
--print'777777777777777777777777777777'
--pr(result)
  return result
end

private.except = function (state, type)
  local result = {}
  for i=1,table.getn(type) do
    local v = type[i]
    result[v.name] = CDR.get(state,v.type)
  end
  return result
end

private.union = function (state, type)
  local selector = CDR.get(state, type.switch)
  local val = CDR.get(state, type.options[selector].type)
  return {val; switch = selector}
end

private.enum = function (state, type)
  local n = private.ulong(state) + 1
  if n > table.getn(type.enumvalues) then
    error("invalid enumeration value: "..n)
  end
  -- pedro: que comportamento deve ser esperado? Em LuaORB, a função
  --        recebe o índice do enum, e não a string.
  return type.enumvalues[n]
  --return n
end

private.array = function (state,type)
  local n = type.length
  local c_type = type.elementtype
  if c_type._type == "octet" or  c_type._type == "char" then
    local arr = string.sub(state._buffer,state._cursor,state._cursor + n -1)
    state._cursor = state._cursor + n
    return arr
  else
    local arr = {n=n}
    for i=1,arr.n do
      arr[i] = CDR.get(state,c_type)
    end
    return arr
  end
end

private.sequence = function (state,type)
  local n = private.ulong(state)
  local c_type = type.elementtype
  if c_type._type == "octet" or  c_type._type == "char" then
    local seq = string.sub(state._buffer,state._cursor,state._cursor + n -1)
    state._cursor = state._cursor + n
    return seq
  else
    local seq = {n=n}
    for i=1,seq.n do
      seq[i] = CDR.get(state,c_type)
    end
    return seq
  end
end

private.any = function (state)
  local t = typecode(state)
  if t == IDL.null or t == IDL.void then
    return nil
  else
    return CDR.get(state, t)
  end
end

private.Object = function (state, type)
  local ior = private.struct(state, IOR)   -- read IOR
  if ior.type_id == '' then
    verb( 6, 'returning nil object' )
    return nil
  end
  verb( 6, 'creating new object:' )
  verb_pr( 6, ior )
  return Proxy:new(ior, ior.type_id)
  --return IDL.newObject(ior)
end

CDR.get = function (state, vtype)
  assert( type(state) == 'table', 'state should be a table, got '..tostring(state) )
  local f = private[vtype._type]
  if not f then error("type "..vtype._type.." not supported") end
  local res = f(state,vtype)
  verb( 8, 'got res ', res )
  verb_pr( 9, res )
  return res

end
 
CDR.getulong = private.long
CDR.getsequence = private.sequence

end
--}-------------------------------------------------------------



--{-------------------------------------------------------------
-- marshalling
----------------------------------------------------------------
do


local private = {}


private.align = function (state, al)
  local extra = math.mod(string.len(state.s), al)
  if extra > 0 then
    state.s = state.s .. string.rep('\255', al - extra)
     -- should be \0, but a different value is easier for testing.
  end
end

private.put = function (state, s)
  state.s = state.s .. s
end

private.octet = function (state, o)
  private.put(state, bitlib.pack("B", o))
end

private.char = function (state, o)
  assert(string.len(o) == 1, "invalid char value")
  private.put(state, o)
end

private.boolean = function (state, o)
  if o then
    private.octet(state, 1)
  else
    private.octet(state, 0)
  end

--print(string.len(state.s))
--print(IDL.tohexa(state.s))
end

local create_setnumber = function (size, format)
  local put = private.put  -- 4.0
  local align = private.align -- 4.0
  return function (state, v)
    align(state, size)
    put(state, bitlib.pack(">"..format, v))
  end
end

private.ulong = create_setnumber(4, "L")

private.long = create_setnumber(4, "l")

private.ushort = create_setnumber(2, "S")

private.short = create_setnumber(2, "s")

private.float = create_setnumber(4, "f")

private.double = create_setnumber(8, "d")

private.void = function (state)
end

private.string = function (state, s, tp)
assert( type(s) == 'string', 'expected string, got '..type(s)..' for '..tp._type )
  private.ulong(state, string.len(s)+1)
  private.put(state, s..'\0')
end

private.enum = function (state, v, tp)
  v = tonumber(v) or tp.name2val[v]
  if not v then
	for i,u in pairs( tp.name2val ) do print( i,u ) end
    error("ilegal enum value: "..tostring(v))
  end
  private.ulong(state, v)
end

private.sequence = function (state, sq, tp)
  local entrytype = tp.elementtype
  if type(sq) == "string" and (entrytype._type == 'octet' or entrytype._type == 'char') then
    private.ulong(state, string.len(sq))
    private.put(state, sq)
  else
    local n = table.getn(sq)
verb( 8, 'sequence with '..n..' elements:' )
    private.ulong(state, n)
    for i=1,n do
verb( 9, i..'th sequence element:' )
--pr( sq[i], '', 5, { 'aaa_super', '_cache' } )
      CDR.set(state, sq[i], entrytype) 
    end
  end
end

private.array = function (state, a, tp)
  local entrytype = tp.elementtype
  if type(a) == "string" and (entrytype._type == 'octet' or entrytype._type == 'char') then
    assert(string.len(a) == tp.length, "wrong array length")
    private.put(state, a)
  else
    assert(table.getn(a) == tp.length, "wrong array length")
    for i=1,tp.length do
      CDR.set(state, a[i], entrytype) 
    end
  end
end

private.struct = function (state, sct, tp)
verb( 9, '/\/\/\/\/\/\ in struct with '..table.getn(tp)..' fields:')
if VERB_LEVEL >= 9 then pr( tp ) end
--if sct == nil then return end
assert( sct, 'meant struct, got nil' )
  for i=1,table.getn(tp) do
    local t = tp[i]
    local val = sct[t.name]
    if not val and t.type ~= IDL.boolean then
      error("struct has no "..t.name.." member")
    end

verb( 9, '/\/\/\/\/\/\ processing member ',t.name,t.type,type(val))
    
    CDR.set(state, val, t.type)
  end
end

private.union = function (state, val, tp)
  CDR.set(state, val.switch, tp.switch)
  CDR.set(state, val[1], tp.options[val.switch].type)
end

private.any = function (state, val)
  local t, v
  if type(val) == 'number' then
    v = val
    t = IDL.double
  elseif type(val) == 'string' then
    v = val
    t = IDL.string
  else
    if type(val) == 'table' then
verb( 10, 'any is a table:')
for i,v in pairs(val) do verb(10, i,v) end
		local mt = getmetatable( val )
verb( 7, '--> mt', tostring( mt ))
if(mt) then for i,v in pairs(mt) do verb(7, i,v) end end
if VERB_LEVEL >= 7 then pr( mt ) end
verb( 7, '--> mt', tostring( mt ))
		if mt.type then
			verb( 9, 'using metatable for type definition:' )
			val = { type=mt.type; val }
		end
    end
    if type(val) == 'table' and val.val == nil and val[1] == nil then
    	pr(val)
    end
    assert(type(val) == 'table' and (val.val or val[1]) and val.type, "bad `any' value: "..tostring(type(val)))
    v = val.val or val[1]
    t = val.type
  end
  writetypecode(state, t)
  CDR.set(state, v, t)
end

-- TODO: THIS MUST BE CHECKED
private.TypeCode = function (state, val)
  verb( 9, 'writing typecode ' )
  if VERB_LEVEL >= 9 then pr(val) end
  writetypecode(state, val)
end


private.Object = function (state, ob)

verb( 10, 'Checking for .ior in object', ob )
  if ob and rawget( ob, 'ior' ) then
verb( 9, 'I found an IOR, and I\'m not afraid to use it:' )
  	ob = ob.ior 
end

  private.struct(state, ob, IOR)
end

private.alias = function (state, val, tp)
  CDR.set(state, val, tp.type)
end


CDR.set = function (state, value, tp)
  assert( type(state) == 'table', 'state should be a table, got '..tostring(state) )
  assert( type(tp) == 'table', 'tp should be a table, got '..tostring(tp) )
  local f = private[tp._type]
  if not f then error("invalid type (or not implemented) "..tp._type) end

  -- marshalling added to set... everybody needs a good marshalling now and
  -- then
  if tp._type == "Object" and type(value) == 'string' then
  verb(6, 'value string: ', value )
  end
  if tp._type == 'Object' and (value == nil or value.type_id == '') then
  --if tp._type == 'Object' and (value == nil ) then
	verb( 8, 'got nil value for', tp.type_id )
	value = { type_id='', profiles = { {tag=0,profile_data=''} },_iiop='', exc_handlers={}}
	--value = IDL.Object''
	--value = lo_createservant( {}, '' )
  elseif tp._type == "Object" and value and not value.type_id then -- think of nil
	  --if tp.type_id == '' then print'tp:' pr( tp ) print'value:' pr( value ) end
	  --assert(tp.type_id ~= '', 'empty type_id' )
verb(8, 'creating servant for marshalling, type_id ['..tostring(tp.type_id)..']', value )
verb_pr( 9, value ) 
     assert(tp.type_id, 'nil type_id' )
		value = lo_createservant(value,tp.type_id).ior
verb(7, 'marshalling servant ior: ', value )
verb_pr(7, value )
--table.foreach( value, print )
  else
	--if type(value) == 'table' and value.ior then value = value.ior end
  end 
--[[--
  if tp._type == 'Object' and type(value) == 'table' and
     value.type_id and value.ior then
verb( 6, 'got an ior here' )
  	value = value.ior
  end
--]]--
  f(state, value, tp)
end


CDR.setulong = private.ulong

CDR.writebuffer = function (e)
  e = e or ""
  if e == 1 then e = "\0" end    -- mark endianess, if asked for  (ENDIAN)
  return {s=e}
end

CDR.finalwrite = function (state)
  return state.s
end

function CDR.marshaling (v, t, e, alg)
  local state = CDR.writebuffer(e)
  CDR.set(state, v, t)
  return state.s
end

end

--}-------------------------------------------------------------
