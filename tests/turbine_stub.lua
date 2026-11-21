--=================================================================================================
--= Just enough Turbine to load and drive the real Sinew source under a desktop Lua 5.1.
--=
--= This is NOT loaded by the game. Nothing imports it from Main.lua, so tests/ is inert in the
--= client. It cannot test drawing - it tests the arithmetic, the event plumbing, the dirty flags
--= and the savefile round trip, which is where the bugs actually are.
--=================================================================================================

local stub = {}

stub.clock = 0
stub.lines = {}
stub.store = {}       -- [scope][key] = data, the fake PluginData disk
stub.setCounts = {}   -- [control][setter] = times called, for dirty-flag assertions

---------------------------------------------------------------------------------------------------
-- a control
---------------------------------------------------------------------------------------------------

local function count( control, setter )
	stub.setCounts[ control ] = stub.setCounts[ control ] or {}
	stub.setCounts[ control ][ setter ] = ( stub.setCounts[ control ][ setter ] or 0 ) + 1
end

local function NewControl( kind )

	local c = {
		_kind    = kind,
		_items   = {},
		_left    = 0,
		_top     = 0,
		_width   = 0,
		_height  = 0,
		_visible = true,
		_mouse   = true,
		_opacity = 1,
		_zorder  = 0,
		_text    = "",
	}

	-- children are tracked so layout can be checked off-screen: "does any control stick out of the
	-- row that owns it" is a real bug class, and the options panel is hand-placed co-ordinates all
	-- the way down
	function c:SetParent( p )

		if self._parent ~= nil and self._parent._children ~= nil then
			for i = 1, #self._parent._children do
				if self._parent._children[i] == self then
					table.remove( self._parent._children, i )
					break
				end
			end
		end

		self._parent = p

		if p ~= nil then
			p._children = p._children or {}
			table.insert( p._children, self )
		end

	end

	function c:GetParent()             return self._parent end
	function c:GetChildren()           return self._children or {} end

	function c:SetPosition( l, t )     count( self, "SetPosition" ); self._left, self._top = l, t end
	function c:GetPosition()           return self._left, self._top end
	function c:SetLeft( l )            self._left = l end
	function c:GetLeft()               return self._left end
	function c:SetTop( t )             self._top = t end
	function c:GetTop()                return self._top end

	function c:SetSize( w, h )         count( self, "SetSize" ); self._width, self._height = w, h end
	function c:GetSize()               return self._width, self._height end
	function c:SetWidth( w )           count( self, "SetWidth" ); self._width = w end
	function c:GetWidth()              return self._width end
	function c:SetHeight( h )          self._height = h end
	function c:GetHeight()             return self._height end

	function c:SetVisible( v )         self._visible = v and true or false end
	function c:IsVisible()             return self._visible end
	function c:SetMouseVisible( v )    self._mouse = v and true or false end
	function c:IsMouseVisible()        return self._mouse end

	function c:SetBackColor( x )       count( self, "SetBackColor" ); self._backColor = x end
	function c:GetBackColor()          return self._backColor end
	function c:SetForeColor( x )       self._foreColor = x end
	function c:GetForeColor()          return self._foreColor end

	function c:SetOpacity( o )         self._opacity = o end
	function c:GetOpacity()            return self._opacity end
	function c:SetZOrder( z )          self._zorder = z end
	function c:GetZOrder()             return self._zorder end

	function c:SetText( t )            count( self, "SetText" ); self._text = tostring( t ) end
	function c:GetText()               return self._text end

	-- recorded rather than ignored: which end of its box a label draws at is a real, testable
	-- layout decision even though the stub cannot draw it
	function c:SetTextAlignment( a ) self._alignment = a end
	function c:GetTextAlignment()    return self._alignment end

	-- accepted and ignored: they have no observable effect off-screen
	-- recorded: the outline is what keeps a readout legible over a bar, and "it has an outline but
	-- the engine chose its colour" looks identical to "it has none"
	function c:SetOutlineColor( x ) self._outlineColor = x end
	function c:GetOutlineColor()    return self._outlineColor end

	function c:SetFont() end
	function c:SetFontStyle( s ) self._fontStyle = s end
	function c:GetFontStyle()    return self._fontStyle end
	function c:SetMultiline() end
	function c:SetMarkupEnabled() end
	function c:SetBackground() end
	function c:SetStretchMode() end
	function c:SetBackColorBlendMode() end
	function c:SetBlendMode() end
	function c:SetWantsKeyEvents() end
	function c:Focus() end

	function c:SetWantsUpdates( w )    self._wantsUpdates = w and true or false end
	function c:WantsUpdates()          return self._wantsUpdates and true or false end

	function c:SetChecked( v )         self._checked = v and true or false end
	function c:IsChecked()             return self._checked end

	-- EntityControl. Undocumented in the published API but real -- Potato and Gibberish3 both bind
	-- one this way -- so the stub carries it to keep the test honest about what is bound to what.
	function c:SetEntity( e )          self._entity = e end
	function c:GetEntity()             return self._entity end

	function c:AddItem( item )         table.insert( self._items, item ) end
	function c:GetItemCount()          return #self._items end
	function c:RemoveItem() end
	function c:Sort() end
	function c:SetMaxItemsPerLine() end

	-- scrolling. The stub cannot clip, so these only have to be recordable: the assertion worth
	-- making is that the options panel attached a scrollbar at all, since without one the rows past
	-- the viewport are simply unreachable in the client.
	function c:SetOrientation( o )          self._orientation = o end
	function c:GetOrientation()             return self._orientation end
	function c:SetVerticalScrollBar( bar )  self._vScroll = bar end
	function c:GetVerticalScrollBar()       return self._vScroll end
	function c:SetHorizontalScrollBar( bar ) self._hScroll = bar end

	return c

end

---------------------------------------------------------------------------------------------------
-- an actor: anything with vitals, used for the local player and for targets
---------------------------------------------------------------------------------------------------

function stub.NewActor( options )

	options = options or {}

	local a = {
		morale     = options.morale     or 1000,
		maxMorale  = options.maxMorale  or 1000,
		temp       = options.temp       or 0,
		maxTemp    = options.maxTemp    or 0,
		power      = options.power      or 500,
		maxPower   = options.maxPower   or 500,
		inCombat   = false,
		name       = options.name       or "Dummy",
		target     = nil,
	}

	function a:GetMorale()               return self.morale end
	function a:GetMaxMorale()            return self.maxMorale end
	function a:GetBaseMaxMorale()        return self.maxMorale end
	function a:GetTemporaryMorale()      return self.temp end
	function a:GetMaxTemporaryMorale()   return self.maxTemp end

	function a:GetPower()                return self.power end
	function a:GetMaxPower()             return self.maxPower end
	function a:GetBaseMaxPower()         return self.maxPower end
	function a:GetTemporaryPower()       return 0 end
	function a:GetMaxTemporaryPower()    return 0 end

	function a:GetName()                 return self.name end
	function a:IsInCombat()              return self.inCombat end
	function a:GetTarget()               return self.target end
	function a:GetParty()                return nil end

	-- present on players and monsters, absent on objects; Sinew duck-types on these
	if options.kind ~= "object" then
		function a:GetLevel() return options.level or 100 end
	end

	if options.kind == "player" then
		function a:GetAlignment() return 1 end
	end

	---------------------------------------------------------------------------------------------------
	-- fire an event the way the engine does, handling both a single handler and the table of
	-- handlers that SINEW.AddCallback builds. If this ever stops matching the real dispatcher the
	-- additive-callback scheme is broken, so it is deliberately exercised by every test.
	---------------------------------------------------------------------------------------------------
	function a:Fire( name )

		local handler = self[ name ]

		if type( handler ) == "function" then
			handler( self, {} )
		elseif type( handler ) == "table" then
			-- copied first: a handler is allowed to detach itself
			local copy = {}
			for i = 1, #handler do copy[i] = handler[i] end
			for i = 1, #copy do copy[i]( self, {} ) end
		end

	end

	function a:SetMorale( value )
		self.morale = value
		self:Fire( "MoraleChanged" )
	end

	function a:SetMaxMorale( value )
		self.maxMorale = value
		self:Fire( "MaxMoraleChanged" )
	end

	function a:SetBubble( temp, maxTemp )
		self.temp, self.maxTemp = temp, maxTemp
		self:Fire( "TemporaryMoraleChanged" )
	end

	function a:SetPowerValue( value )
		self.power = value
		self:Fire( "PowerChanged" )
	end

	function a:SetCombat( value )
		self.inCombat = value and true or false
		self:Fire( "InCombatChanged" )
	end

	function a:SetTarget( entity )
		self.target = entity
		self:Fire( "TargetChanged" )
	end

	return a

end

---------------------------------------------------------------------------------------------------
-- install the global Turbine table
---------------------------------------------------------------------------------------------------

-- options.euro makes Turbine.Shell.IsCommand("hilfe") answer true, which is how every plugin here
-- detects a German or French client. The whole suite is then run a second time through the
-- stringify-every-number savefile path.
function stub.Install( localPlayer, options )

	options = options or {}

	stub.euro = options.euro and true or false
	stub.localPlayer = localPlayer
	stub.updaters = {}

	local Color = {}

	local colorMeta = { __index = Color }

	local function NewColor( r, g, b, a )
		-- the engine's Color takes (r,g,b) or (a,r,g,b); Sinew only ever uses the three argument
		-- form, and the metatable is what makes the euro converter leave it alone
		local c = { R = r or 0, G = g or 0, B = b or 0, A = a or 1 }
		return setmetatable( c, colorMeta )
	end

	Turbine = {

		Engine = {
			GetGameTime = function() return stub.clock end,
		},

		Shell = {
			WriteLine   = function( text ) table.insert( stub.lines, tostring( text ) ) end,
			IsCommand   = function( name )
				-- "hilfe" is the German help command, "aide" the French one
				return stub.euro and ( name == "hilfe" or name == "aide" ) or false
			end,
			AddCommand  = function( name, command ) stub.command = command end,
			RemoveCommand = function() stub.command = nil end,
		},

		ShellCommand = function() return {} end,

		DataScope = { Character = "character", Account = "account" },

		PluginData = {
			Save = function( scope, key, data )
				stub.store[ scope ] = stub.store[ scope ] or {}
				stub.store[ scope ][ key ] = data
			end,
			Load = function( scope, key )
				return stub.store[ scope ] and stub.store[ scope ][ key ] or nil
			end,
		},

		Gameplay = {
			LocalPlayer = {
				GetInstance = function() return stub.localPlayer end,
			},
			Class = {},
		},

		UI = {

			Control = function() return NewControl( "Control" ) end,

			-- A Window is created HIDDEN by the engine, where a Control is created visible. The stub
			-- used to build both visible, which quietly hid a real bug for a long time: the morale
			-- bar's clipping window and its label window were never told to be visible, so in the
			-- client they were not, and nothing inside them was drawn -- a full-width green fill and
			-- a rendered readout, both invisible, inside a hidden parent. Modelling the engine's
			-- default is what makes that testable off-screen.
			Window  = function()
				local w = NewControl( "Window" )
				w._visible = false
				table.insert( stub.updaters, w )
				return w
			end,
			Label   = function() return NewControl( "Label" ) end,
			ListBox = function() return NewControl( "ListBox" ) end,

			-- the plain one, not Turbine.UI.Lotro.TextBox. It paints no background of its own, which
			-- is why the options panel puts a Control behind each one; that is the shape every
			-- working text field in this plugins folder uses.
			TextBox = function() return NewControl( "TextBox" ) end,

			Graphic = function() return {} end,

			Color = setmetatable( {
				White = NewColor( 1, 1, 1 ),
				Black = NewColor( 0, 0, 0 ),
				Orange = NewColor( 1, 0.5, 0 ),
			}, { __call = function( _, r, g, b, a ) return NewColor( r, g, b, a ) end } ),

			Display = { GetSize = function() return 1920, 1080 end },

			ContentAlignment = {
				MiddleLeft = 1, MiddleCenter = 2, MiddleRight = 3,
				TopLeft = 4, TopCenter = 5, TopRight = 6,
			},

			MouseButton = { Left = 1, Right = 2, Middle = 3 },

			Orientation = { Horizontal = 0, Vertical = 1 },

			FontStyle = { None = 0, Outline = 1, Shadow = 2 },

			BlendMode = { AlphaBlend = 1, Overlay = 2 },

			Lotro = {
				Font = setmetatable( {}, { __index = function( t, k ) return "font:" .. tostring( k ) end } ),
				CheckBox = function() return NewControl( "CheckBox" ) end,
				TextBox  = function() return NewControl( "TextBox" ) end,
				Button   = function() return NewControl( "Button" ) end,
				ScrollBar = function() return NewControl( "ScrollBar" ) end,
				EntityControl = function() return NewControl( "EntityControl" ) end,
				LotroUI = { SetEnabled = function() end },
				LotroUIElement = { Vitals = 268435465, Target = 268435467 },
				Action = {},
			},
		},
	}

	-- Turbine.UI.Display:GetSize() is called with a colon in Constants.lua
	Turbine.UI.Display.GetSize = function( self ) return 1920, 1080 end

	plugin = {}

	---------------------------------------------------------------------------------------------------
	-- import: in the client each package directory gets its own environment and files inside one
	-- directory share it. Sinew is a single flat directory, so the global environment is equivalent.
	---------------------------------------------------------------------------------------------------
	import = function( path )

		if string.sub( path, 1, 7 ) == "Turbine" then
			return
		end

		local file = string.gsub( path, "^Sinew%.", "" )
		file = string.gsub( file, "%.", "/" ) .. ".lua"

		local chunk, err = loadfile( file )

		if chunk == nil then
			error( "import failed for " .. path .. ": " .. tostring( err ), 0 )
		end

		chunk()

	end

end

---------------------------------------------------------------------------------------------------
-- drive the fade driver's Update, the way the client would
---------------------------------------------------------------------------------------------------
function stub.Tick( seconds )

	stub.clock = stub.clock + ( seconds or 0.034 )

	for i = 1, #stub.updaters do
		local w = stub.updaters[i]
		if w:WantsUpdates() and w.Update ~= nil then
			w:Update()
		end
	end

end

function stub.Counted( control, setter )
	return ( stub.setCounts[ control ] and stub.setCounts[ control ][ setter ] ) or 0
end

return stub
