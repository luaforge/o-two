-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "address.lua"
require "giop.lua"
require "IR_idl.lua"


IR.sigs = {}
-- weakmode(IR.sigs, 'v')

-- hand-made signatures for access to repository

local op_getinterface = IDL.operation {
  result = IDL.Object( 'IDL:omg.orb/CORBA/InterfaceDef:1.0' ),
  parameters = {
  }
}

local op_lookupname = IDL.operation {
  result = IDL.sequence{IDL.Object()},
  parameters = {
    {name = "search_name", type = IR.Identifier},
    {name = "levels_to_search", type = IDL.long},
    {name = "limit_type", type = IR.DefinitionKind},
    {name = "exclude_inherited", type = IDL.boolean},
  }
}

local op_describe = IDL.operation {
  result = IDL.struct{
    {name="kind", type=IR.DefinitionKind},
    {name="value", type=IDL.any},
  },
  parameters = {
  }
}

local op_lookup_id = IDL.operation{
  result = IDL.Object(),
  parameters = {
    {name='id', type=IDL.string},
  },
}

IR.getsig = function (obj, method)

  if not obj.type_id or obj.type_id == "" then
    error ("object has no type id!!!")
  end

  local idesc = IR.sigs[obj.type_id]
--print('getsig', obj.type_id, method, idesc)
  if not idesc then
verb( 4, "Generating get_interface request for type_id "..obj.type_id)
    idesc = {_meths={},_interface = GIOP.call (obj, "_interface", {}, op_getinterface)}
    IR.sigs[obj.type_id] = idesc
  end

  local attrname, action
  _, _, action, attrname = string.find(method, "^_([gs]et)_(.+)$")
  if attrname then
    -- it's an attribute
    method = attrname
  end
  
  if not idesc[method] then
verb( 4, "Generating lookup_name request for type_id "..obj.type_id..", method "..method)  
	local op
    if idesc._interface then 
		op = GIOP.call (idesc._interface, "lookup_name", {method, -1, "dk_Operation", false}, op_lookupname)
	else
		-- local call
		verb( 6, 'local call' )
		verb_pr( 6, idesc )
		op = idesc:lookup_name( method, -1, 'dk_Operation', false )
	end
--table.foreach(op, print)
    if not op[1] then 
--print("...and again, dk_all this time:")
--[[-new-crap
  if not idesc._meths then idesc._meths = {} end
  if not idesc._meths[method] then
verb( 6, "Generating lookup_name request for type_id "..obj.type_id..", method "..method)  
    --HERE
    local op
    if not idesc._interface then
      op = idesc:lookup_name( method, -1, "dk_Operation", false )
      if op[1] then 
        local desc = op[1]:describe()
        if desc then
          if desc.kind == 'dk_Operation' then
	    if VERB_LEVEL >= 8 then
		    verb( 8, 'desc.value', obj.type_id, method )
		    pr( desc.value )
		    verb( 8, 'desc.value', obj.type_id, method )
	    end
            idesc._meths[method] = IDL.operation(desc.value)
            return idesc._meths[method]
          end
        end
      end
    end

    local op = GIOP.call (idesc._interface, "lookup_name", {method, -1, "dk_Operation", false}, op_lookupname)
--pr(op)
    if table.getn( op ) > 0 then 
    else
verb( 6, "...and again, dk_all this time:")
--]]--new-crap

      op = GIOP.call (idesc._interface, "lookup_name", {method, -1, "dk_all", false}, op_lookupname)
--pr(op)
    end
    if op[1] then
      local desc = GIOP.call (op[1], "describe", {}, op_describe)
--print("desc of "..method..":")
--pr(desc)
      if desc.kind == 'dk_Operation' then
        idesc[method] = IDL.operation(desc.value)
        --new-crap- idesc._meths[method] = IDL.operation(desc.value)
      else	
        desc.value.action = action
        desc.value.kind = desc.kind
        desc.value.parameters = {}
        if action == 'set' then
          table.insert( desc.value.parameters, {type=desc.value.type} )
          desc.value.result = IDL.void
        elseif action == 'get' then
          desc.value.result = desc.value.type
        end
        local ret = IDL.operation(desc.value)
        ret.kind = 'dk_Attribute'
        return ret
        --idesc[method] = IDL.operation(desc.value)
        --idesc[method].kind = 'dk_Attribute'
      end	
    end
  end

  return idesc[method]

end

function IR.getinterface (type_id)
verb( 6, 'IR.getinterface: '..tostring(type_id))
  if not IR.sigs[type_id]  then
verb( 5, 'IR.getinterface is going out to fetch '..tostring(type_id))
--print("** IR.getinterface is going out for "..type_id)
    assert(_irep, "Interface not found and no Repository available")
    verb( 5, 'still going out' )
    IR.sigs[type_id] = {}
    IR.sigs[type_id]._interface = GIOP.call(_irep, "lookup_id", {type_id}, op_lookup_id)
  else
	print("** IR.getinterface found "..type_id.." locally ("..type(IR.sigs[type_id]._interface)..")")
  end
 --pr(IR.sigs[type_id])
  return IR.sigs[type_id]._interface
end

function hcall (obj, method, args)

  -- determine method's signature
  local sig = IR.getsig(obj).by_opkey[method]  

  -- effectively call
  return GIOP.call (obj, method, args, sig)

end

CorbaObject.__index = function (obj, method)
--print("|| in __index",method,rawget(obj,method))
  local sig = IR.getsig(obj, method)  
  local f
  if not sig then return nil end
  if sig.kind == 'dk_Operation' then
     local s = IDL.operation(sig)
--print('making stub of '..method..':')
--pr(s)
      f = function (o, ...)
--                 print('inside stub function, calling method '..method)
                 return GIOP.call(o, method, arg, s)
               end
      obj[method] = f      
--print("it's an operation", type(f))  
   elseif sig.kind == 'dk_Attribute' then
      sig.result = sig.type
      sig.parameters = {}
      f = GIOP.call(obj, '_get_'..method, {}, IDL.operation(sig))
   else      
      error("unknown kind: "..( sig.kind or 'nil' ))
   end
   return f
end

CorbaObject.__newindex = function (obj, idx, value)
--print("|| in __newindex",idx,value)
  if __CO_IN_NEWINDEX then
    return rawset(obj, idx,value)
  else
    __CO_IN_NEWINDEX = true
  end
  local sig = IR.getsig(obj, idx)  
  local f
  if not sig then return nil end
  if sig.kind == 'dk_Operation' then
     local s = IDL.operation(sig)
      f = function (o, ...)
--                 print('inside stub function, calling method '..method)
                 return GIOP.call(o, idx, arg, s)
               end
      rawset(obj, idx, f)      
--print("it's an operation", type(f))  
   elseif sig.kind == 'dk_Attribute' then
    sig.result = IDL.void
    sig.parameters = { { type=sig.type, mode = "IN" } }
    sig = IDL.operation(sig)
--print('ready for _set:')
--pr(sig)
    f = GIOP.call(obj, '_set_'..idx, { value }, sig)
  else      
    error("unknown kind: "..( sig.kind or 'nil' ))
  end
  __CO_IN_NEWINDEX = false
  return f
end