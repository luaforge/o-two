--| Concorrência de corotinas/sockets
--b Pedro Miller Rabinovitch <miller@inf.puc-rio.br>
--$Id: concur.lua,v 1.1 2004-07-21 03:15:55 rmello Exp $

LUA_PATH="?;?.lua;../lua/?"
require'util.lua'

--& Concurrency status
Concur = {}

if false then
	-- avoid using Concur
	Concur.receive = function( self, ... ) return receive( unpack( arg )) end 
	Concur.select = function( self, ... ) return select( unpack( arg )) end 
	Concur.accept = function( self, ... ) return accept( unpack( arg )) end 
	Concur.spawn = function( self, f, ... ) return true, f( unpack( arg )) end
	Concur.pcall = function( self, ... ) return pcall( unpack( arg )) end 
	return
end

--. current (thread)  Current thread
Concur.current = nil 

--. sockets (table) List of sockets
Concur.sockets = {}

--. socket_map (table) Maps sockets to threads
Concur.socket_map = {}

--. threads (table) List of threads
Concur.threads = {}

--. buffers (table) data read buffers
Concur.buffers = {}

local _my_unused_verbose_select = function(...) 
	print('+!+ IN SELECT +!+')
	arg.n = nil
	arg[1].n = nil
	for i, v in arg do
		print( i, v )
		for j, u in v do
			print( i, j, u )
		end
	end
	return select( unpack(arg) )
end
local I = {}

local TIMEOUT = 0

--% Run the selection loop until finished or got one of our sockets
--@ wait_for (table) list *indexed* by sockets handled by caller.
--- Returns if this is selected. Can be nil, implying waiting until
--- Concur.finished.
function I.SelectionLoop( self, wait_for )
	assert( self.sockets )
	if table.getn( self.sockets ) == 0 then
		verb( 1, "can't go into wait for no sockets" )
		return
	end
	verb( 6, 'into SelectionLoop, waiting for', wait_for )
	verb_do( 8, function() table.foreach(wait_for, print) end )
	
	while not Concur.finished do
		verb( 7, 'selecting on '..table.getn( self.sockets )..' sockets' )
		verb_do( 8, function() for i,s in ipairs(self.sockets) do verb(7, i, s) end end )
		-- perform select()
		local rdy, msg = select( self.sockets, nil )
		if rdy == nil then
			verb( 2, 'error in SelectionLoop: ', msg )
			return
		end

		if rdy[1] then
			if wait_for[rdy[1]] then
				-- got what the caller needs. hand it over
				verb( 7, 'got what we were after' )
				--self.current = nil
				return rdy[1]
			else
				-- this young piggy needs to be resumed
				verb( 7, 'let\'s resume this', rdy[1] )
				verb_do( 9, function() table.foreach(rdy[1],print) end)
				local ok = I.ResumeOperation( self, rdy[1] )
				if not ok then
					I.ForgetRoutine( rdy[1] )
				end
			end
		end
	end
end

--% Resume operation on the socket-owning coroutine
--@ target (socket) the lucky socket or coroutine
function I.ResumeOperation( self, target, ... )
	assert( self.sockets )
	assert( target, "can't resume on nil target" )
	local oc = self.current
	if type(target) ~= 'thread' then
		-- it's not a thread -- must be a socket
		assert( type(target) == 'table' )
		table.insert( arg, 1, target )
		target = self.socket_map[target]
		assert( type(target) == 'thread', 'invalid thread in map: '..tostring( target ) )
	end

	self.current = target
	local ret = { coroutine.resume( target, unpack(arg) ) }
	local ok, msg = ret[1], ret[2]

	if not ok then
		verb( 2, 'error running coroutine:', msg )
	else
		verb( 7, 'returned from coroutine:', ok, msg )
	end
	self.current = oc

	return unpack(ret)
end

--% Add a socket or list of sockets to the waiting queue
--@ socket_list (table) list of sockets to add
--@ routine (thread) coroutine associated with it (default: current)
function I.AddSockets( self, socket_list, routine )
	assert( self.sockets )
	routine = routine or self.current or 'main thread'
	assert( type(socket_list) == 'table' )

	for _, sock in socket_list do
		verb( 8, 'adding socket '..tostring(sock)..' ('..tostring(routine)..')' )
		-- even if the socket is already mapped, it's routine might
		-- have changed
		if not self.socket_map[ sock ] then
			table.insert( self.sockets, sock )
		end
		self.socket_map[ sock ] = routine
	end
end

--% Forget about a socket (i.e., don't pay anymore attention to it)
--@ sock (socket) unlucky socket
function I.ForgetSocket( self, sock )
	assert( self.sockets )
	assert( sock )
	verb( 7, 'Removing socket '..tostring(sock)..' from list.' )
	self.socket_map[sock] = nil
	for i, v in self.sockets do
		if v == sock then
			table.remove( self.sockets, i )
			return
		end
	end
end

--% Forget about a routine (i.e., drop its sockets)
--@ routine (thread) unlucky routine
function I.ForgetRoutine( self, routine )
	assert( self.socket_map )
	assert( type(routine) == 'thread' )

	for sock, rout in self.socket_map do
		if rout == routine then
			I.ForgetSocket( self, sock )
		end
	end
end

--% Serve the prepared sockets until finished
--
function Concur:serve()
	return I.SelectionLoop( self )
end

--% Simulate a protected call. The parent routine is blocked until the
--- called function returns.
--@ func (function) Function to be executed
--@ ... (any) extra parameters for the function
--: (any) boolean indicating sucess or failure, the rest are the values
--- returned by the function itself.
function Concur:pcall( func, ... )
	verb( 5, 'executing pcall' )
        local c = coroutine.create( func )
	local should_yield = (self.current ~= nil)
	local res, last_res, ok

	res = arg
	table.insert( res, 1, true )

	repeat
		table.remove( res, 1 )
		last_res = res

		verb( 8, 'resuming coroutine' )
		res = { coroutine.resume( c, unpack( last_res )) }
		verb( 8, 'got ', unpack( res ))
	until res[1] == false -- some error ocurred
	-- we want 'cannot resume dead coroutine' error, which is a
	-- Good Thing(tm), meaning we tried once too many, so it's done.
	if res[2] == 'cannot resume dead coroutine' then
		res = { true, unpack( last_res )}
	end

        return unpack( res )
end

--% Go to the main loop, one way or the other. May yield or call.
--@ sock_list (table) List of sockets we should care about
--: (socket) Socket ready for reading that triggered the return 
function I.GoToMainLoop( self, sock_list )
	local wait_for = {}
	assert( self.sockets )
	if sock_list then
		if table.getn( sock_list ) == 0 then
			-- single socket
			wait_for[sock_list] = true
		else
			for _, sock in sock_list do
				wait_for[sock] = true
			end
		end
	end
	local res 
	if self.current then
		verb( 8, 'yielding to previous main loop' )
		res = coroutine.yield()
	else
		verb( 8, 'the loop is mine' )
		-- grab which socket got the calling
		-- this is useful so we don't select on dead sockets
		res = I.SelectionLoop( self, wait_for )
	end
	verb( 8, 'waiting for this? ', wait_for[res] )
	return res
end

--% Select-like. Waits for next socket ready to be read. Note that 
--- write-selection is not yet implemented.
--@ read_sockets (table) List of sockets we're waiting for.
--: (table) List of sockets which are ready to be read from
function Concur:select( read_sockets )
	local sock, sock_list
	verb( 7, 'select called' )
	assert( type( read_sockets ) == 'table' )

	-- convert the table of sockets to a proper list
	sock_list = {}
	for i,v in pairs( read_sockets ) do
		table.insert( sock_list, v )
	end

	-- pay attention to these
	I.AddSockets( self, sock_list )

	-- now go to main loop
	sock = I.GoToMainLoop( self, sock_list )

	-- forget about'im already
	I.ForgetSocket( self, sock )

	return { sock }, {}
end

--% Accept-like. Waits for next connection.
--@ master (socket) Socket we're listening at (already bound)
--: (socket) Socket for the new connection
function Concur:accept( master )
	local sock, msg 
	verb( 7, 'accept called', master )
	-- pay attention to this one
	I.AddSockets( self, { master } )

	-- now go to main loop
	sock = I.GoToMainLoop( self, master )
	assert( sock == master )
	I.ForgetSocket( self, master )

	-- it's go time
	sock, msg = accept( master )
	verb( 8, 'accept returning', sock, msg )

	return sock, msg
end

--% Receive-like. Waits for next packets.
--@ socket (socket) Socket we're listening at (already connected)
--@ size (number) Number of bytes to be read, nil for whatever's
--- available.
--: (string) Bytes received
function Concur:receive( sock, size )
	verb( 7, 'receive called', size, sock )
	local got = self.buffers[sock] or ''
	local res, errmsg
	size = size or 0

	if size == 0 then
		-- special case. We want either a) what's in our buffer; or
		-- b) what's in the network buffer.
		if string.len( got ) > 0 then
			-- grab what's available and run
			self.buffers[sock] = ''
			verb( 7, 'got it in our buffer', got )
			return got
		else
			-- look for what's available, grab it, and run
			verb( 7, 'going for internal loop', size, sock )
			I.AddSockets( self, { sock } )
			local gotsock = I.GoToMainLoop( self, sock )

			sock:timeout( TIMEOUT )
			local r, m = receive( sock, '*a' )
			if m == 'timeout' then
				-- this is exactly what we wanted, anyway
				m = nil
			end

			I.ForgetSocket( self, sock )
			verb( 7, 'receive returned, got', r, m )
			return r, m
		end
	end

	I.AddSockets( self, { sock } )
	while string.len( got ) < size and errmsg == nil do
		verb( 7, 'going for internal loop', size, sock )
		local gotsock = I.GoToMainLoop( self, sock )
		local vl = (sock == gotsock and 6) or 2
		verb( vl, 'expected ',sock,' got ',gotsock, (sock==gotsock) )

		verb( 7, 'receiving now', size, sock, string.len( got ) )
		sock:timeout( TIMEOUT )
		local r, m = receive( sock, '*a' )
		verb( 9, 'after receive(): ', r, 'm', m )
		if r and r ~= '' then 
			got = got .. r
		else
			-- some error ocurred -- after all, we select()ed
			-- before we receive()d...
			m = 'closed'
		end
		if m == 'closed' then -- error
			verb( 4, 'got error message in receive for ', sock, ':', m )
			errmsg = m
		end
		verb( 10, 'got this for now:', got )
	end
	if size == 0 then
		size = string.len( got )
	end
	self.buffers[sock] = string.sub( got, size + 1 ) 
	I.ForgetSocket( self, sock )
	verb( 7, 'got this:', to_hex(got) )
	return string.sub( got, 1, size ), errmsg
end

--% Create a new coroutine and start it
--@ handler (function) handler function
--@ ... (any) extra parameters for handler function
--TODO specify return value appropriately. for now, same as coroutine
function Concur:spawn( handler, ... )
	check_types( 'function', handler )
	local c = coroutine.create( handler )
	return I.ResumeOperation( self, c, unpack(arg) )
end


