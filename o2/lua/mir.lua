-----------
-- mir.lua
-- $Id: mir.lua,v 1.1 2004-07-21 03:15:58 rmello Exp $
--   Pedro Miller Rabinovitch, DI, PUC-Rio
--
--   Mini-IR Implementation. Caches interface requests directed towards
--   servers and repositories. Works for both servers (as a cache for real
--   IRs) and for clients (as a cache for IRs and object servers).
-----------

if MIR then return end
MIR = {}

require 'proxy.lua'
require 'util.lua'
require 'orbconfig.lua'
require 'address.lua'
require 'giop.lua'
require 'IR_idl.lua'


-- Interfaces
local AttributeDef = {}
local OperationDef = {}
local InterfaceDef = {}
local ModuleDef = {}
local Contained = {}
local Container = {}
local Repository = {}
local IDLType = {}
local IRObject = {}

MIR.IRObject = IRObject
MIR.IDLType = IDLType
MIR.AttributeDef = AttributeDef
MIR.OperationDef = OperationDef
MIR.InterfaceDef = InterfaceDef
MIR.ModuleDef = ModuleDef
MIR.Contained = Contained
MIR.Container = Container
MIR.Repository = Repository

function throw(...)
	local s = tostring(arg[1])
	for i = 2, table.getn(arg) do
		s = s..'\t'..tostring(arg[i])
	end

	error( s, 3 )
end

-- singleton repository
local IDLType_Cache = {}
local IRObject_Cache = {}

function IDLType:_new( tp )
	assert( tp )
	if type(tp) == 'table' then return tp end
	local t = IDLType_Cache[tp]
	if t == nil then 
		t = IRObject:_new( 'dk_none' )
		t._type = 'Object'
		t.type = tp
		t.type_id = tp
		t.repID = tp
		--IRObject_Cache[tp] = t
	end   
	return t
end

function IRObject:_new( kind )   
	assert( type(kind) == 'string', _TRACEBACK('should be string') )
	local t = IRObject_Cache[kind]
	if 1 or t == nil then --cache destivado por enquanto
		t = Object:_new()
		t.def_kind = kind
		IRObject_Cache[kind] = t
	end   
	return t
end

local I = {}
MIR.interfaces = {}

-- check for interface repository
if ORB_CONFIG.EXTERNAL_IR_REF then
	verb( 4, "Using interface repository reference..." )
	MIR.external_ir = IOR.normalform( ORB_CONFIG.EXTERNAL_IR_REF )
	--io.close()
	verb( 4, "Done." )
end

local op_getinterface = IDL.operation {
  result = IDL.Object(),
  parameters = {
  }
}

local op_lookup_id = IDL.operation{
  result = IDL.Object(),
  parameters = {
	{name='id', type=IDL.string},
  },
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

local op_get_attribute = IDL.operation {
  result = IDL.any,
  parameters = {},
}

function I.interface_lookup_name( proxy, search_name, levels_to_search, limit_type, exclude_inherited )
	local stuff = GIOP.call( proxy._interface, 'lookup_name',
		  { search_name, levels_to_search, limit_type, exclude_inherited },
		  op_lookupname )
	
	return stuff
end

function I:build_interface_proxy( obj_data )
	local proxy
	-- for now, just go for the light
	-- these GIOP.calls should be moved into methods. This way,
	-- the whole issue with 'knowing where we are' would become
	-- moot. Well, kind of, at least.

	--proxy = GIOP.call( self.external_ir, "lookup_id", 
		 --{ obj_id }, op_lookup_id )
	
	-- proxy = { _interface = obj._interface, _type_id = obj._type_id }
	-- proxy.lookup_name = I.interface_lookup_name

	proxy = Proxy:new( obj_data.IR_IOR, 'IDL:omg.org/CORBA/InterfaceDef:1.0' )
	-- gah. This function should never be called. We already build
	-- the interface proxy when we GIOP.call() _interface at
	-- get_interface.

	return proxy
end

function MIR:get_interface( obj_data )
	local obj_id = obj_data.type_id
	local iface 
	verb( 5, 'obj has _type_id ', obj_id )

	if not obj_id or not self.interfaces[ obj_id ] then
		verb( 5, 'object has no interface[] -- calling out' )
		iface = GIOP.call( obj_data, '_interface', {}, op_getinterface )
		verb( 6, 'got _interface ', iface )

		if not obj_id then
			verb( 6, 'calling out for _get_id' )
			obj_id = GIOP.call( Proxy.data[iface], '_get_id', {},
				IDL.operation{result=IDL.string,parameters={}}
			)
		end
		obj_data.type_id = obj_id
		verb( 6, 'got id: '..tostring( obj_data.type_id ))

		self.interfaces[ obj_id ] = iface
	end

	if self.interfaces[obj_id] == nil then
	-- WE SHOULD NEVER GET HERE IF WE'RE THE CLIENT!
	--error( 'shouldn\'t be here, i\'m the client...' )
		-- here we could go out for an external IR
		-- or request the interface from the object itself
		-- Basically, we don't want to do the second if we're local
		-- (i.e., it's our own object)

		-- for now, just go for the light
		verb( 5, 'MIR:get_interface requesting external assistance for '..obj_id )
		iface = I.build_interface_proxy( self, obj_data )

		if iface == nil then
			verb( 2, 'Error retrieving interface for '..obj_id..' from external IR.' )
			return nil, 'error retrieving interface from IR'
		end
		self.interfaces[obj_id] = iface
	end

	return self.interfaces[obj_id]
end

function MIR:get_description( obj_data, idx )
	local iface, err

	iface, err = self:get_interface( obj_data )
	if iface == nil then return nil, err end

	if iface[idx] == nil then
		verb( 6, 'Retrieving object field '..idx..' for '..obj_id..'.' )
	 	local stuff = iface:lookup_name( idx, 1, 'dk_all', 0 )
		if stuff == nil then
			verb( 2, 'Error retrieving object field '..idx..' for '..obj_id..'.' )
			return nil, 'error at lookup_name'
		end
		verb( 4, 'lookup_name for '..idx..' yielded '..table.getn( stuff )..' results.' )
		iface[idx] = stuff
	end

	return iface[idx]
end

-- create a new MIR
-- params:
--   no_cache = 1  -> don't cache entries, just forward requests
--   use_ir = <IORstr> -> forward requests we don't know about to external IR
function MIR:new( params )
	if params == nil then params = {} end
	assert( type(params) == 'table' )
	
	local t
	-- copy public methods
	t = shallow_copy( self )

	return t
end


-- Contained methods
local I = {}

-- Description describe ();
function Contained:describe()
	assert( type(self.kind) == 'string', self.kind )
	assert( type(self.description) == 'table' )

verb( 8, 'describe():')
verb( 9, self.kind, self.description, self.id, self )
	
	return { kind = self.kind, value = self.description }
end

-- Constructor. Receives { container, kind, id, name, version }
function Contained:_new( data )
	assert( type(data) == 'table' )
	assert( type(data.container) == 'table' )
	assert( type(data.kind) == 'string' )
	assert( type(data.name) == 'string' )
	assert( type(data.id) == 'string' )
	assert( type(data.version) == 'string' )

	local t = IRObject:_new( data.kind )
	for i,v in self do rawset( t, i, v ) end   
	
	for i,v in { 'kind', 'name', 'version', 'id' } do
		t[v] = data[v]
	end
	t.defined_in = data.container
	t.containing_repository = data.container.containing_repository 
	t.absolute_name = (data.container.absolute_name or '') .. '::' .. t.name
	--t.type_id = self.id
	t.description = {
		id = t.id,
		name = t.name,
		version = t.version,
		defined_in = t.defined_in.id,
	}
	--setmetatable( t.description, IR.AttributeDescription )

	return t
end

-- Module interface
function ModuleDef:_new( id, name, version, parent )
	assert( type(parent) == 'table' )
	assert( type(name) == 'string' )
	assert( type(id) == 'string' )
	assert( type(version) == 'string' )

	-- estabelece comportamento de herança
	local t = Object:_new()
	
	-- adiciona instâncias de superclasses
	-- ModuleDef é tanto um Contained...
	t:_add_super(
		Contained:_new{
			container = parent, name = name, 
			kind = 'dk_Module', id = id, version = version
		}
	)
	-- ...quanto um Container
	t:_add_super( Container:_new( nil, 'dk_Module' ) )
	
	-- define tipo da descrição
	setmetatable( t.description, {type=IR.ModuleDescription} )
	

	-- retorna o novo objeto
	return t
end

function AttributeDef:_new( data )
	assert( type(data) == 'table' )
	assert( data.type )
	assert( data.type_def )
	assert( data.mode )

	-- estabelece comportamento de herança
	local t = Object:_new()
	assert( type(t) == 'table' )
	
	-- adiciona instâncias de superclasses
	-- AttributeDef é um Contained.
	data.kind = 'dk_Attribute'     
	t:_add_super( Contained:_new( data ))

	-- atributos próprios 
	--t.type_id = self.id
	t.type = data.type
	t.type_def = data.type_def

	t.description.type = data.type
	t.description.mode = data.mode

	-- define tipo da descrição
	setmetatable( t.description, {type=IR.AttributeDescription} )
	
	return t
end

function OperationDef:_new( data, parent )
	assert( type(data) == 'table' )
	assert( data.exceptions )
	assert( data.contexts )
	assert( data.parameters )
	assert( data.result )
	assert( data.result_def )
	assert( data.mode )

	-- estabelece comportamento de herança
	local t = Object:_new()
	assert( type(t) == 'table' )
	
	-- adiciona instâncias de superclasses
	-- OperationDef é um Contained.
	data.kind = 'dk_Operation'	  
	t:_add_super( Contained:_new( data ))

	--	t.type_id = self.id
	
	t.result = data.result
	t.result_def = MIR.IDLType:_new( data.result )
	t.mode = data.mode   
	t.params = data.parameters
	t.exceptions = data.exceptions
	t.contexts = data.contexts
	t.description.result = data.result
	t.description.mode = data.mode
	t.description.parameters = data.parameters
	t.description.exceptions = data.exceptions
	t.description.contexts = data.contexts
	t.description.type = IR.OperationDescription

	setmetatable( t.description, { type=IR.OperationDescription } )

verb( 8, 'OperationDef created. ', t )
verb( 8, 'raw: ',rawget( t, description ))
verb( 8, 'normal: ',  t.description )
	
	return t
end

-- InterfaceDef interface

function Container:_check_id( id )
	assert( type(id) == 'string' )
	-- every Container that is not Repository is Contained
   local rep = self.containing_repository or self
	if rep:lookup_id( id ) then
		-- should throw BAD_PARAM with 2 as minor
		throw( 'BAD_PARAM', 2, 'an object with that id already exists in this repository', tostring(id) )
	else
		verb(7, 'new id:  ', id )
	end
end

function Container:_check_name( name )
	assert( type(name) == 'string' )

	if self:lookup( name ) then
		-- should throw BAD_PARAM with 3 as minor
		throw( 'BAD_PARAM', 3, 'an object with that name already exists in this context' )
	else
		verb(7, 'new name:', name )
	end
end

-- AttributeDef create_attribute ( in RepositoryId id, in Identifier name, in VersionSpec version, in IDLType type, in AttributeMode mode );
function InterfaceDef:create_attribute( id, name, version, tp, mode )
	assert( type(id) == 'string', 'invalid id' )
	assert( type(name) == 'string', 'invalid name' )
	assert( type(version) == 'string', 'invalid version' )
	assert( type(tp) == 'table', 'invalid type' )
	assert( type(mode) == 'string', 'invalid mode' )
		
	self:_check_id( id )
	self:_check_name( name )

	local t = AttributeDef:_new{ id=id, name=name, version=version,
		type=tp, type_def=MIR.IDLType:_new( tp ), mode=mode, container=self }
	self:_set( name, t )
   verb( 8, '--- created attribute'..name )
	return t
end

-- OperationDef create_operation( in RepositoryId id, in Identifier name, in VersionSpec version, in IDLType result, in OperationMode mode, in ParDescriptionSeq params, in ExceptionDefSeq exceptions, in ContextIdSeq contexts );
function InterfaceDef:create_operation( id, name, version,
	result, mode, params, exceptions, contexts )
	assert( type(id) == 'string', 'invalid id' )
	assert( type(name) == 'string', 'invalid name' )
	assert( type(version) == 'string', 'invalid version' )
	assert( type(result) == 'table', 'invalid result type' )
	assert( type(mode) == 'string', 'invalid mode' )
	assert( type(params) == 'table', 'invalid parameters type' )
	assert( type(exceptions) == 'table', 'invalid exceptions type' )
	assert( type(contexts) == 'table', 'invalid contexts type' )

	self:_check_id( id )
	self:_check_name( name )

	local t = OperationDef:_new{ 
		id = id, name = name, version = version,
		result = result, result_def = IDLType:_new( result ), 
		mode= mode, parameters = params,
		exceptions = exceptions, contexts = contexts, 
		container = self 
	}
	self:_set( name, t )

   verb( 6, '--- created operation '..name..' in '..tostring(self)..' ('..self.id..')' )

	return t
end

function InterfaceDef:_new( id, name, version, parent, base )
	assert( base == nil or type(base) == 'table' )
	assert( type(id) == 'string', _TRACEBACK(tostring(id)) )
	assert( type(name) == 'string' )
	assert( type(version) == 'string' )
	assert( type(parent) == 'table' )
	-- estabelece comportamento de herança
	local t = Object:_new()
	
	-- adiciona instâncias de superclasses
	-- InterfaceDef é tanto um Contained...
	t:_add_super(
		Contained:_new{
			container = parent, name = name, 
			kind = 'dk_Interface', id = id, version = version
		}
	)
	-- ...quanto um Container...
	t:_add_super( Container:_new( base, 'dk_Interface' ) )   
	-- ...quanto um IDLType.
	t:_add_super( IDLType:_new( IDL.Object() )) --TODO: substituir
	t.kind = 'dk_Interface'
	
	-- atributos próprios de InterfaceDef   
	setmetatable( t.description, { type = IR.InterfaceDescription } )
	t.description.type = IR.InterfaceDescription 

	local base_ids = {}
	if base then
		for i,v in ipairs( base ) do
			base_ids[i] = v.id
		end
	end
	t.description.base_interfaces = base_ids
	for i,v in self do
		rawset( t, i, v )
	end
	--t.type_id = self.id

	return t
end

-- Container methods
local I = {}

function Container:_new( base, dk )
	assert( base == nil or type(base) == 'table' )
	local t = IRObject:_new( dk or 'dk_none' )
	for i, v in self do rawset( t, i, v ) end
	
	local super = {}
	t.stuff = Object:_new()
	
	if type( base ) == 'table' then
		for i, v in ipairs( base ) do
			t.stuff:_add_super( v.stuff )
		end
	end
	
	return t
end

-- ContainedSeq contents ( in DefinitionKind limit_type, in boolean exclude_inherited );
function Container:contents( limit_type, exclude_inherited )
	verb( 8, 'contents called' )
	--print( shallow_copy )
	--TODO: process parameters
	-- for now, just return the whole bunch
	local t = {}
	for i, v in pairs( self.stuff ) do
		if i ~= '_super' then
			table.insert( t, v )
			t[i] = v
			--print(table.getn(t), i,v)
		end
	end
	return t
end

function Container:_set( name, val )
	self.stuff[name] = val
end

-- Contained lookup (in ScopedName search_name);
function Container:lookup( search_name )
verb( 6, 'in lookup: '..tostring( search_name ))
	--TODO: process absolute names
	local a, b, name, rest = string.find( search_name, '([^:]+)::(.*)' )
	if a == nil then 
		local s = self.stuff
		verb( 6, 'lookup '..search_name..' in '..tostring(s)..' ('..tostring(getmetatable(s))..')' )
		local r = s[search_name]
		verb( 6, 'lookup result: '..tostring(r) )

		return self.stuff[search_name]
	else
		-- scoped name
		local o = self.stuff[name]
		if o and o.lookup then
			return o:lookup( rest )
		else
			return nil
		end
	end
end

-- ContainedSeq lookup_name ( in Identifier search_name, in long levels_to_search, in DefinitionKind limit_type, in boolean exclude_inherited );
function Container:lookup_name( search_name, levels_to_search, limit_type, exclude_inherited )
verb( 6, 'in lookup_name: '..tostring( search_name )..', '..tostring(
levels_to_search ))
	--TODO: implement limit_type behavior
	if levels_to_search == 0 or levels_to_search < -1 then
		throw( 'BAD_PARAM', 501, 'invalid levels_to_search param' )
	end

	function same_kind( k1, k2 )
		if k1 == 'dk_all' or k2 == 'dk_all' then
			return true
		else
			return k1 == k2
		end
	end
	
	local t = { self:lookup( search_name ) }
	if t[1] and not same_kind( t[1].kind, limit_type ) then
		table.remove( t, 1 )
	end
	if levels_to_search == 1 then
		return t 
	else
		if levels_to_search > 0 then
			levels_to_search = levels_to_search - 1
		end
		for i,v in self.stuff do
verb( 6, 'lookup_name found '..i..', ['..tostring(v)..'] '..type(v) )
			if i ~= 'n' and i~='_super' and v.lookup_name then
				local res = v:lookup_name( search_name,
					levels_to_search, limit_type,
					exclude_inherited )
				for j, u in res do
					if j ~= 'n' then
						table.insert( t, u )
					end
				end
			end
		end
	if self.stuff._super and not exclude_inherited then 
		for i,v in self.stuff._super do
verb( 6, 'lookup_name found '..i..', ['..tostring(v)..'] '..type(v) )
		 if i ~= 'n' and i~='_super' and type(v.lookup_name) == 'function' then
			local res = v:lookup_name( search_name,
				levels_to_search, limit_type,
				exclude_inherited )
			for j, u in res do
				if j ~= 'n' then
					table.insert( t, u )
				end
			end
		 end
		end
		end
		return t
	end
	return t 
end

--ModuleDef create_module ( in RepositoryId id, in Identifier name, in VersionSpec version );
function Container:create_module( id, name, version )
	self:_check_id( id )
	self:_check_name( name )
	
	--pr( self:describe() )
   verb( 8, 'CREATING MODULE '..name)	
   verb( 8, 'SETTING CONTAINER TO '..tostring(self))
   
	local t = ModuleDef:_new( id, name, version, self )

	self:_set( name, t )

	verb( 7, 'module '..id..' created in '..tostring(self)..': ',tostring( t ))

	return t
end

--InterfaceDef create_interface ( in RepositoryId id, in Identifier name, in VersionSpec version, in InterfaceDefSeq base );
function Container:create_interface( id, name, version, base )
	if self:lookup( name ) then
		-- should throw BAD_PARAM with 3 as minor
		throw( 'BAD_PARAM', 3, 'an interface with that name already exists here' )
	end
	local t = InterfaceDef:_new( id, name, version, self, base )

	self:_set( name, t )

	return t
end

-- Repository methods
local I = {}

function I:create_cache()
	self.ids = {} -- id cache
end

function I:get_cache( search_id )
	return self.ids[search_id]
end

function I:set_cache( search_id, value )
	if not self.param.no_cache then
		self.ids[search_id] = value
	end
end

--[[--
-- fake describe() operation for Repository (for id purposes)
function Repository:describe()
assert( self.value )
	return { kind='dk_Repository', value=self.value }
end
--]]--

-- Contained lookup_id (in RepositoryId search_id);
function Repository:lookup_id( search_id )
--print('in MIR lookup_id ',search_id)
	if search_id == nil then return nil end
	local id = gsub( search_id, 'IDL:(.+):%d+\.%d+', '%1' )
	id = gsub( id, '/', '::' )
	id = gsub( id, '^::', '' )
verb( 7, 'searching for ',id)
	local res = self:lookup( id )
	if res then
		return res
	end
	
	res = I.get_cache( self, search_id )
	if res == nil then
		if not self.params.use_ir then
			return nil, "no match [not using external IR]"
		end
		-- use external ir
		res = self.external_ir:lookup_id( search_id )

		I.set_cache( self, search_id, res )
	end
	return res
end

-- returns IR Repository interface
function Repository:_new( params )
	if params == nil then params = {} end
	assert( type(params) == 'table' )
	
	local rep
	-- copy public methods
	rep = shallow_copy( self )
	-- create new superclass
	rep._super = { Container:_new() }
	-- set metatable
	set_object( rep )
	-- copy parameters
	rep.params = shallow_copy( params )
	if not params.no_cache then
		I.create_cache( rep )
	end

	if params.use_ir then
		-- create external_ir proxy
	end

	-- fake 'value' for fake 'describe()'
	rep.absolute_name = ''
	rep.id = ''
	rep.containing_repository = rep

	return rep
end

Repository.new = Repository._new
