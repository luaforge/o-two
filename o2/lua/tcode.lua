-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "idl.lua"

--{-------------------------------------------------------------------------
-- uncoding typecodes
----------------------------------------------------------------------------

local parsetypedesc = {}

local tcinfo = {
  [0] = 
  {name = "null",
   unhandled = 1,
   type = "empty",               
   idl = IDL.null,
  }, 
  [1] = 
  {name = "void",
   --unhandled = 1,
   type = "empty",   
   idl = IDL.void,
  }, 
  [2] = 
  {name = "short",
   type = "empty",  
   idl = IDL.short,
  },
  [3] = 
  {name = "long",
   type = "empty", 
   idl = IDL.long,
  },
  [4] = 
  {name = "ushort",
   type = "empty",
   idl = IDL.ushort,
  },
  [5] = 
  {name = "ulong",
   type = "empty",
   idl = IDL.ulong,
  },
  [6] = 
  {name = "float",
   type = "empty",    
   idl = IDL.float,
  },
  [7] = 
   {name="double",
    type = "empty",   
    idl = IDL.double,
  },
  [8] = 
  {name="boolean",
   type = "empty",  
   idl = IDL.boolean,
  },
  [9] = 
  {name="char",
   type = "empty", 
   idl = IDL.char,
  },
  [10] = 
  {name="octet",
   type = "empty",
   idl = IDL.octet,
  },
  [11] = 
  {name="any",
   type = "empty",
   idl = IDL.any,
  },
  [12] = 
  {name="TypeCode",
   type = "empty",
   idl = IDL.TypeCode,
  },
  [13] = 
  {name="Principal",
   type = "empty",
   unhandled = 1,
   idl = IDL.Principal
  },
  [14] = 
  {name = "Object",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
   }
  },
  [15] = 
  {name = "struct",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
     {name = "fields", type = IDL.sequence
                               {IDL.struct{
                                 {name = "name", type = IDL.string},
                                 {name = "type", type = IDL.TypeCode}}
                               }}
   }
  },
  [16] = 
  {name = "union",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
     {name = "switch", type = IDL.TypeCode},
     {name = "default", type = IDL.long},
     -- unmarshalling of next fields depend on field switch
     --{name = "options", type = IDL.sequence
     --                          {IDL.struct{
     --                            {name = "label", type = <discriminanttype>},
     --                            {name = "name", type = IDL.string},
     --                            {name = "type", type = IDL.TypeCode}}
     --                          }}
   }
  },
  [17] = 
  {name = "enum",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
     {name = "enumvalues", type = IDL.sequence{IDL.string}}
   }
  },
  [18] = 
  {name = "string",
   type = "simple",  
   idl = IDL.string,
   parameters = {
     {name="maxlength", type=IDL.ulong}
   },
  },
  [19] = 
  {name = "sequence",
   type = "complex",
   parameters = IDL.struct{
     {name = "elementtype", type = IDL.TypeCode},
     {name = "maxlength", type = IDL.ulong}}
  },
  [20] = 
  {name = "array",
   type = "complex",
   parameters = IDL.struct{
     {name = "elementtype", type = IDL.TypeCode},
     {name = "length", type = IDL.ulong}}
  },
  [21] = 
  {name = "alias",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
     {name = "type", type = IDL.TypeCode},
   },
  },
  [22] =  
  {name = "except",
   type = "complex",
   parameters = IDL.struct{
     {name = "repID", type = IDL.string},
     {name = "name", type = IDL.string},
     {name = "members", type = IDL.sequence
                               {IDL.struct{
                                 {name = "name", type = IDL.string},
                                 {name = "type", type = IDL.TypeCode}}
                               }},
    },
  },
  [23] = 
  {name = "longlong",
   unhandled = 1,
   type = "empty"}, 
  [24] = 
  {name = "ulonglong",
   unhandled = 1,
   type = "empty"},
  [25] = 
  {name = "longdouble",
   unhandled = 1,
   type = "empty"},
  [26] = 
  {name = "wchar",
   unhandled = 1,
   type = "empty"},
  [27] = 
  {name = "wstring",
   type = "simple",
   parameters = {
     {name="maxlength", type=IDL.ulong}
   },
   unhandled = 1,
   kind = "wstring",
  },
  [28] = 
  {name = "fixed",
   type = "simple",
   parameters = {
     {name="digits", type=IDL.ushort},
     {name="scale", type=IDL.short}
   },
   unhandled = 1,
   kind = "fixed",
  },
  [29] = 
  {name = "value",
   unhandled = 1,
   type = "complex"},
  [30] = 
  {name = "value_box",
   unhandled = 1,
   type = "complex"},
  [31] = 
  {name = "native",
   unhandled = 1,
   type = "complex"},
  [32] = 
  {name = "abstract_interface",
   type = "complex"},
  -- [0xffffffff] = {name="none", type = "simple"},
}


parsetypedesc.Object = function (desc, state)
  return (IDL.Object(desc.repID))
end

parsetypedesc.struct = function (desc, state)
  return IDL.struct(desc.fields)
end

parsetypedesc.except = function (desc, state) 
  return IDL.except(desc.members)
end

local createfieldtype = function (udesc)
  return IDL.sequence{
           IDL.struct{
             {name = "label", type = udesc.switch},
             {name = "name", type = IDL.string},
             {name = "type", type = IDL.TypeCode}
           }
         }
end

parsetypedesc.union = function (desc, state)
  local options = CDR.get(state, createfieldtype(desc))
  desc.options = {}
  for i=1,table.getn(options) do
    if i ~= desc.default+1  then
      local option = options[i]
      desc.options[option.label] = option
    end
  end
  desc.seqoptions = options -- cache for future typecode marshalling
  return IDL.union(desc)
end

for _, n in {"sequence", "enum", "array", "alias"} do
  local name = n
  parsetypedesc[name] = function (desc, state)
    return IDL[name](desc)
  end
end

local ignore = function (state, parameters)
  for i=1, table.getn(parameters) do
    CDR.get (state, parameters[i].type)
  end
end

typecode = function (buff)

  local kind = CDR.getulong(buff)
verb( 11, 'typecode is '..tostring(kind) )
--io.read()
  if tcinfo[kind] == nil then 
    error("unknown type "..kind..".")
  end
  if tcinfo[kind].unhandled then
    error("type "..tcinfo[kind].name.." not supported")
  end

  if tcinfo[kind].type == "empty" then
    return tcinfo[kind].idl

  elseif tcinfo[kind].type == "simple" then
    -- type string is the only simple type being handled
    ignore(buff, tcinfo[kind].parameters)
    return tcinfo[kind].idl

  elseif tcinfo[kind].type == "complex" then
  
    -- read sequence of params
    local parameters = CDR.getsequence(buff, IDL.sequence{IDL.octet})
    
    local newbuf = CDR.createBuffer(parameters,1)
    local f = parsetypedesc[tcinfo[kind].name]
    return f(CDR.get(newbuf, tcinfo[kind].parameters), newbuf)
    
    
  end 

end

--}-------------------------------------------------------------------------



--{-------------------------------------------------------------------------
-- coding typecodes
----------------------------------------------------------------------------

local revtcode = {}
for k,v in tcinfo do revtcode[v.name] = k end

local codetypecode = {}

codetypecode.union = function (buff, t)
  local options 
  if not t.seqoptions then -- create sequence of options
    options = {}
    local i = 1
    for l, v in t.options do
      options[i] = t.options[l]
      options[i].label = l
      i = i+1
    end
    t.seqoptions = options -- cache it for next marshalling
  else
    options = t.seqoptions
  end
  CDR.set (buff, options, createfieldtype(t))
end

local default = {maxlength = 0, repID = "", name = "", }

local codeparams = function (buff, params, type)
  for i=1, table.getn(params) do
    local t = params[i]
    local val = type[t.name] or default[t.name]
    if not val then error("type has no "..t.name.." member") end
    CDR.set(buff, val, t.type)
  end
end

writetypecode = function (buff, t)
verb( 7, 'writing typecode for kind '..tostring(t._type) )
  local kind = revtcode[t._type]
  if not kind then error("invalid type:"..tostring(t._type)) end
verb( 11, 'typecode is '..tostring(kind) )
--io.read()
  CDR.setulong(buff, kind)
  local info = tcinfo[kind]
  if info.type == "simple" then
    codeparams(buff, info.parameters, t)
  elseif info.type == "complex" then
    local newbuff = CDR.writebuffer(1)
    codeparams(newbuff, info.parameters, t)
    if codetypecode[info.name] then codetypecode[info.name](newbuff, t) end
    CDR.set(buff, CDR.finalwrite(newbuff), IDL.sequence{IDL.octet})
  end
end

--}-------------------------------------------------------------------------
