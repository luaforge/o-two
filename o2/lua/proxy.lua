
----------------
-- proxy.lua
--$Id: proxy.lua,v 1.1 2004-07-21 03:16:00 rmello Exp $
--
--| Call and attribute forwarding.
--| Responsible for creating client objects and directing access.
--b Pedro Miller Rabinovitch <miller@inf.puc-rio.br>
----------------

if Proxy then return end 
Proxy = {}

DONT_USE_PROXY  = true
-- This should be enabled. However, right now there's code in MIR's main
-- area, and that should be moved to an init() function of somesort.
--require 'mir.lua'

local I = {}

-- in construction time, the proxy will be created as a local or a remote
-- proxy.

local obj_meta = { Proxy = Proxy }
Proxy.obj_meta = obj_meta

-- Proxy data, indexed by objects
Proxy.data = {}
-- contains:
--   type_id : RepositoryId
--   url : Implementation reference (IOR, etc)
--   obj : object table (== index)

--% __index metamethod for proxy objects, called when clients try to
--% access remote functionality (methods or attributes, mainly)
--@ obj (table) the object being indexed
--@ idx (any) the index
--: (any) function (if method) or attribute value
function obj_meta.__index( obj, idx )
	local meta = getmetatable( obj )
	assert( meta )
	local Proxy = meta.Proxy
	assert( Proxy )
	-- Retrieve hidden data (contained in Proxy's internal table)
	local obj_data = Proxy.data[ obj ]
	assert( obj_data )
	verb( 7, '------------============ obj_data:' )
	verb_pr( 7, obj_data ) 

	-- check attribute tables
	local attr_fn = rawget( obj, '_get_'..idx )
	-- check for attribute proxy
	if type(attr_fn) == 'function' then
		return attr_fn()
	end
	-- request description from MIR

	verb( 5, string.format( 'got __index for %s["%s"]', tostring(obj), tostring(idx) ))
--assert( idx ~= 'profiles' and idx ~= 'type_id' and idx ~= '_iiop' )
	if idx == 'profiles' or idx == 'type_id' or idx == '_iiop' then
		return obj_data[idx]
	end
	-- looking for interfaces is MIR's job
	local desc = MIR:get_description( obj_data, idx )

	-- if method or attribute, make request
	if desc.kind == 'dk_Operation' then
		-- create method proxy
		local op = I.create_operation_proxy( obj, idx, desc )
		rawset( obj, idx, op )
		return op
	elseif desc.kind == 'dk_Attribute' then
		-- create attribute proxy
		attr = I.create_attribute_proxy( obj, idx, desc, 'get' )
		rawset( obj, '_get_'..idx, attr )

		return attr()
	else
		verb( 2, 'invalid index kind '..tostring( desc.kind ))
		error( 'invalid index kind '..tostring( desc.kind ))
	end
end

--% __newindex metamethod for proxy objects, called when clients try to
--% set remote attribute values
--@ obj (table) the object being indexed
--@ idx (any) the index
--@ val (any) the new value
--TODO complete
function obj_meta.__newindex( obj, idx, val )
	-- check attribute tables
	-- request description from MIR
	-- looking for interfaces is MIR's job
	local desc = MIR:get_description( obj, idx )
	-- if attribute, send request
end

--% Create a new proxy object
--@ address (string) URL to object
--@ type_id (string) IDL type identifier
--: (table) object proxy
function Proxy:new( URL, type_id )
	if DONT_USE_PROXY then return IDL.newObject( URL ) end 
	verb( 7, '88888888888888888888888888')
	-- for now, just IORs
	local obj = {}
	local ior = URL 
	if type(URL) == "string" then
		ior = IOR.decode(ior)
	end
	if type(ior) ~= "table" then error("invalid ior") end
	verb( 7, 'decoded', '--------------------------------' )
	if VERB_LEVEL >= 7 then
		pr( ior )
	end
	verb( 7, 'decoded', '--------------------------------' )
	ior.url = URL
	ior.obj = obj
	ior.type_id = type_id

	self.data[obj] = ior
	setmetatable( obj, self.obj_meta )

	return obj
end

function Proxy:get_interface_object()
end
