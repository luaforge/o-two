-----------
-- $Id: util.lua,v 1.1 2004-07-21 03:16:03 rmello Exp $
--   Pedro Miller Rabinovitch, DI, PUC-Rio
--
--   Funções utilitárias
-----------

Object = {}

VERB_LEVEL = 2
VERB_NAME = ''
function verb( level, ... )
	if level <= VERB_LEVEL then
		return print( VERB_NAME..os.date('%y.%m.%d %H:%M')..'['..level..']', unpack( arg ))
	end
end

function verb_do( level, cmd )
	if level <= VERB_LEVEL then
		local print = function(...) return verb( level, unpack(arg) ) end
		--local f = loadstring( cmd )
		local f = cmd
		return f()
	end
end

function verb_pr( level, ... )
	if level <= VERB_LEVEL then
		return pr( unpack( arg ))
	end
end

function pr (v, tab, lvls_left, ignore)
  ignore = ignore or {}
  for i,v in ignore do ignore[v] = true end
  lvls_left = lvls_left or 3
  tab = tab or ''
  if type(v) ~= 'table' then
    if type(v) == 'number' then io.write(v)
    elseif type(v) == 'string' then io.write(string.format("%q", v))
    else io.write(tostring(v))
    end
    io.write(',\n')
  else
    io.write(tostring(v)..' {\n')
    local newtab = tab.."  "
    for k,v in v do
      io.write(newtab, tostring(k), ' = ')
      if lvls_left > 0 and not ignore[k] then
	      pr(v, newtab, lvls_left - 1) 
      else
      	io.write(' <not shown>,\n')
      end
    end
    io.write(tab, '},\n')
  end
end

function shallow_copy( t )
	local c = {}
	if t then
		for i,v in t do c[i] = v end
	end
	return c
end

function read_all (filename, mode)
	mode = mode or 'rt'
	assert(type(filename) == 'string')
	local fin = io.open( filename, mode )
	if fin == nil then return end
	local data = fin:read"*a"
	fin:close()
	return data
end

local _USE_INDEX_CACHE = true

local objectMeta = {
   __index = function( self, idx )
      local super = rawget( self, '_super' )
      if type(super) == 'table' then
         verb( 15, '__INDEX ATT' )
         if _USE_INDEX_CACHE and 
            type(super._cache) == 'table' then
            local f = super._cache[idx]
            if f then
               verb( 15, '_CACHE HIT' )
               return f[idx], f 
            end
         end
         for i, parent in ipairs( super ) do
            local v, from = parent[idx]
            if v then
               -- found it. Set address in cache
               if not super._cache then
                  super._cache = {}
               end
               from = from or parent
               verb( 15, '_CACHE SET',idx,from )
               super._cache[idx] = from
               return v, from
            end
         end
         return nil -- not found
      end
   end,
   __newindex = function( self, idx, val )
      local super = rawget( self, '_super' )
      if type(super) == 'table' then
         for i, parent in ipairs( super ) do
            if parent[idx] then
               parent[idx] = val
               return 
            end			
         end
      end
      rawset( self, idx, val ) -- not found, set here
   end,
}

function set_object( obj )
   assert( type(obj) == 'table' )
   
   setmetatable( obj, objectMeta )
   return obj
end

-- Object Interface
function Object:_add_super( super )
   assert( type(self) == 'table' )
   assert( type(self._super) == 'table' )
   assert( type(super) == 'table' )
   
   table.insert( self._super, super )
end

function Object:_new()
   local t = { _super = { self } }
   --for i, v in self do t[i] = v end
   return set_object( t )
end   

function Object:_throw(...)
error( arg[1], 3 )
	local s = tostring(arg[1])
	for i = 2, table.getn(arg) do
		s = s..'\t'..tostring(arg[i])
	end

	error( s, 3 )
end

--% Assert parameter types are correct
--@ type_name (string) expected type name
--@ ... (any) values to be checked
function check_types( type_name, ... )
   for i, v in ipairs( arg ) do
      assert( type(v) == type_name )
   end               
end                     

--% Converts a string to its hexadecimal representation
--@ str (string) string to be converted
--: (string) converted string
function to_hex( str )
	return string.gsub( str, '(.)', function( c )
		return string.format( '%X', string.byte( c ))
	end)
end

function lazy_copy( t )
	if type(t) ~= 'table' then return t end
	local nt, meta = {}, {}
	local t = t
	setmetatable( nt, meta )
	function meta:__index( idx )
		local v=t[idx]
		rawset( self, idx, v )
		return v
	end
	return nt
end

function trim( str )
	if str == nil then return end
	local a, b, txt = string.find( str, '^[\n%s]-(%S.*)$' )
	if txt == nil then return end
	a, b, txt = string.find( txt, '^(.*%S)[\n%s]-$' )
	return txt
end


