-- *********************************************************************************
-- * Copyright 2002 Noemi Rodriquez & Roberto Ierusalimschy.  All rights reserved. *
-- *********************************************************************************

require "idl.lua"
require "cdr.lua"
require "proxy.lua"

--
-- auxiliary types for IOP
--
local ProfileId = IDL.alias{IDL.ulong}

local TaggedProfile = IDL.struct{
    {name="tag", type = ProfileId},
    {name="profile_data", type = IDL.sequence{elementtype=IDL.octet}}
  }


--
-- IOP
--
IOP = IDL.module{
  ProfileId = ProfileId,
  TAG_INTERNET_IOP = IDL.const{type=ProfileId, value = 0},
  TAG_MULTIPLE_COMPONENTS = IDL.const{type=ProfileId, value = 1},
  TaggedProfile = TaggedProfile,
  IOR = IDL.struct{
     {name="type_id", type=IDL.string},
     {name="profiles", type=IDL.sequence{TaggedProfile}}
  },
}


--
-- auxiliary types for IIOP
--
local Version = IDL.struct{{name="major",type=IDL.octet},
                           {name="minor",type=IDL.octet}}

--
-- IIOP
--
IIOP = IDL.module{
  Version = Version,
  ProfileBody_1_0 = IDL.struct{
    {name="iiop_version", type = Version},
    {name="host", type = IDL.string},
    {name="port", type = IDL.ushort},
    {name="object_key", type = IDL.sequence{IDL.octet}},
  },
}


IOR = {}

function IOR.code_interface(interface)
  interface = string.gsub(interface, '(.)', function (c)
    return string.format("%02x", string.byte(c))
  end)
  return interface
end

function IOR.string2byte(ior)
   local _, __, body = string.find(ior, "IOR:(.*)")
   if not body then
      return nil, "Invalid IOR"
   end
   ior = string.gsub(body, '(%x%x)', function (h)
     return string.char(tonumber(h, 16))
   end)
   return ior
end

function IOR.decode(ior_st)
  ior_st = IOR.string2byte(ior_st)
  if ior_st == nil then return nil end
  local buffer = CDR.createBuffer(ior_st, 1)
  local ior = CDR.get(buffer, IOP.IOR)   -- read IOR
  return ior
end

function IOR.openIIOP (ior)
	if ior == nil then return nil end
if rawget(ior,'ior') and not rawget(ior,'profiles') then ior = rawget(ior,'ior') end
  if ior._iiop and ior._iiop ~= "" then return ior._iiop end

  local p = nil

if not ior.profiles then
table.foreach( ior, print )
	verb( 6, 'no profiles found' )
	return nil 
end
  assert( ior.profiles, 'no profiles found' )
  assert( ior.profiles[1], 'empty profiles list' )
  for i=1,table.getn(ior.profiles) do   -- for each profile
    -- is it an Internet profile?
    if ior.profiles[i].tag == IOP.TAG_INTERNET_IOP.value then
      p = ior.profiles[i]   -- get it
      break
    end
  end

  assert(p, "no internet profile in ior")
    
  local buf = CDR.createBuffer(p.profile_data, 1)
  local profileiop = CDR.get(buf, IIOP.ProfileBody_1_0)
  profileiop.tag = p.tag
if VERB_LEVEL >= 4 then
print "got profile:"
pr( profileiop )
end
  local version = profileiop.iiop_version
  ior._iiop = profileiop
  return profileiop

end

function IOR.decode_file(file)
   readfrom(file)
   local ior = read()
   readfrom()
   return IOR.decode(ior)
end

function IOR.get_interface(ior)
   local descr
   if type(ior) == "string" then
      descr = IOR.decode(ior)
   elseif type(ior) == "table" then
      descr = ior
   else
      return nil
   end
   return descr.type_id
end

function IOR.normalform(ior)
  if type(ior) == "string" then
    ior = IOR.decode(ior)
  end
  if type(ior) ~= "table" then error("invalid ior") end
  return Proxy:new( ior )
  -- return IDL.newObject(ior)
end

