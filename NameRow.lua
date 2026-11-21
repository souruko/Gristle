---------------------------------------------------------------------------------------------------
-- Sinew - the name row above a bar
---------------------------------------------------------------------------------------------------
-- One line of text sitting on top of the morale bar: by default who this window is describing at
-- one end and their level at the other, though both ends are templates and either can say anything
-- the window knows. The same widget serves the player window and the target window.
--
-- Structure, and why:
--
--   clip   Window   a Turbine.UI.Window clips its children, which is the whole point: a long
--                   monster name has to be cut off at the end of the bar rather than running out
--                   across the screen. Inset by LabelPadding so the name lines up with the number
--                   inside the bar below it rather than with the bar's border.
--     name   Label  the end the name reads from - left on the player frame, right on the target's.
--     extra  Label  the other end. The level by default.
--
-- There is deliberately no backdrop. The row has to read over whatever is behind the HUD, which is
-- what the outline font style in SINEW.Label is for; painting a plate behind it would make the HUD
-- a box instead of a bar. Both labels are mouse-invisible like everything else Sinew draws.
---------------------------------------------------------------------------------------------------

SINEW.NameRow = {}

---------------------------------------------------------------------------------------------------
-- options:
--   zBase       z-order band, so the row cannot interleave with the bars under it
--   alignRight  put the name at the right-hand end, the level at the left
--   formatKeys  { main, aside } settings keys naming this row's two templates
--   context     the owning window's render context, shared with its morale bar
---------------------------------------------------------------------------------------------------
function SINEW.NameRow.New( root, options )

	local row = {}

	row.root  = root
	row.zBase = options.zBase or 50

	-- held by reference and mutated in place by the window, so it is always current
	row.formatKeys = options.formatKeys or {}
	row.context    = options.context or {}

	-- fixed per frame rather than configurable. The player frame reads inward from the left and the
	-- target frame inward from the right, so the pair reads as a mirrored set with the two names at
	-- the outer edges - which is what the frames look like once the target is mirrored across the
	-- screen, and reads correctly even when it is not.
	row.alignRight = options.alignRight and true or false

	row.x, row.y, row.width, row.height = 0, 0, 1, 1

	-- the name and the level both change far less often than a vital, but a template on this row is
	-- allowed to name a vital, so the row re-renders whenever the bars do and the rendered strings
	-- are cached the same way they are
	row._lastName  = nil
	row._lastExtra = nil

	row.clip = SINEW.ClipWindow( root )

	row.nameLabel  = SINEW.Label( row.clip, Turbine.UI.ContentAlignment.MiddleLeft )
	row.extraLabel = SINEW.Label( row.clip, Turbine.UI.ContentAlignment.MiddleRight )

	---------------------------------------------------------------------------------------------------

	function row:ApplyZOrder()

		SINEW.ForceZOrder( self.clip, self.zBase )

		SINEW.ForceZOrder( self.nameLabel,  1 )
		SINEW.ForceZOrder( self.extraLabel, 2 )

	end

	function row:ApplyColors()

		local color = SINEW.Color( SINEW.Settings.colorName )

		self.nameLabel:SetForeColor( color )
		self.extraLabel:SetForeColor( color )

	end

	function row:ApplyFonts()

		local font = SINEW.ResolveFont( SINEW.Settings.nameFontSize, false )

		self.nameLabel:SetFont( font )
		self.extraLabel:SetFont( font )

	end

	---------------------------------------------------------------------------------------------------
	-- which end of the bar the name sits at, decided once by the frame that owns this row
	---------------------------------------------------------------------------------------------------
	-- The level always takes the other end. They share one clipping window, so putting both at the
	-- same end would have the longer one drawn straight through the shorter.
	---------------------------------------------------------------------------------------------------
	function row:ApplyAlignment()

		local alignment = Turbine.UI.ContentAlignment

		if self.alignRight then
			self.nameLabel:SetTextAlignment( alignment.MiddleRight )
			self.extraLabel:SetTextAlignment( alignment.MiddleLeft )
		else
			self.nameLabel:SetTextAlignment( alignment.MiddleLeft )
			self.extraLabel:SetTextAlignment( alignment.MiddleRight )
		end

	end

	---------------------------------------------------------------------------------------------------
	-- geometry
	--
	-- x / y / width are the owning bar's, not the row's: the row insets itself by the same border and
	-- padding the bar's own labels use, so the name sits directly over the morale number.
	---------------------------------------------------------------------------------------------------
	function row:Layout( x, y, width, height )

		local border = SINEW.Settings.showBorder and SINEW.Border or 0

		self.x, self.y = x, y
		self.width  = math.max( 1, math.floor( width ) )
		self.height = math.max( 1, math.floor( height ) )

		local inner = math.max( 1, self.width - 2 * SINEW.LabelPadding )

		self.clip:SetPosition( x + border + SINEW.LabelPadding, y )
		self.clip:SetSize( inner, self.height )

		self.nameLabel:SetPosition( 0, 0 )
		self.nameLabel:SetSize( inner, self.height )

		self.extraLabel:SetPosition( 0, 0 )
		self.extraLabel:SetSize( inner, self.height )

		-- the labels were just resized, so the cached strings no longer describe what is on screen
		self._lastName  = nil
		self._lastExtra = nil

		self:ApplyZOrder()
		self:Render()

	end

	function row:SetVisible( visible )
		self.clip:SetVisible( visible and true or false )
	end

	---------------------------------------------------------------------------------------------------
	-- data
	---------------------------------------------------------------------------------------------------
	-- Both ends come out of the window's context through a template, so this row holds no data of its
	-- own. Nothing here knows that the aside end usually carries a level: "Level [level]" is a
	-- default, and the word in front of the number is the player's to change - which is also how a
	-- German client gets "Stufe 150".
	---------------------------------------------------------------------------------------------------
	function row:Render()

		local nameText = SINEW.Format.Render( SINEW.Settings[ self.formatKeys.main ], self.context )

		if nameText ~= self._lastName then
			self._lastName = nameText
			self.nameLabel:SetText( nameText )
		end

		local extraText = SINEW.Format.Render( SINEW.Settings[ self.formatKeys.aside ], self.context )

		if extraText ~= self._lastExtra then
			self._lastExtra = extraText
			self.extraLabel:SetText( extraText )
		end

	end

	---------------------------------------------------------------------------------------------------
	-- called when the window starts describing a different entity, so the previous target's name
	-- cannot sit over the new one's bar for the frame before the data arrives
	---------------------------------------------------------------------------------------------------
	-- Emptied rather than re-rendered: the window clears the context in the same breath, but it is
	-- this that guarantees nothing of the old entity is left on screen even for a frame.
	---------------------------------------------------------------------------------------------------
	function row:Reset()

		self._lastName  = ""
		self._lastExtra = ""

		self.nameLabel:SetText( "" )
		self.extraLabel:SetText( "" )

	end

	---------------------------------------------------------------------------------------------------

	row:ApplyColors()
	row:ApplyFonts()
	row:ApplyAlignment()

	return row

end
