---------------------------------------------------------------------------------------------------
-- Gristle - the name row above a bar
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
--                   Pushed inward past the icon while one is shown.
--     extra  Label  the other end. The level by default.
--
--   icon   Control  the class emblem, at the very end the name reads from. A sibling of the clip,
--                   not a child of it, and always drawn at its native size - see where it is built.
--                   Only there for a player; anything else has its name start at the edge.
--
-- There is deliberately no backdrop. The row has to read over whatever is behind the HUD, which is
-- what the outline font style in GRISTLE.Label is for; painting a plate behind it would make the HUD
-- a box instead of a bar. Both labels are mouse-invisible like everything else Gristle draws.
---------------------------------------------------------------------------------------------------

GRISTLE.NameRow = {}

---------------------------------------------------------------------------------------------------
-- options:
--   zBase       z-order band, so the row cannot interleave with the bars under it
--   alignRight  put the name at the right-hand end, the level at the left
--   formatKeys  { main, aside } settings keys naming this row's two templates
--   iconKey     settings key of the switch for the class icon
--   context     the owning window's render context, shared with its morale bar
---------------------------------------------------------------------------------------------------
function GRISTLE.NameRow.New( root, options )

	local row = {}

	row.root  = root
	row.zBase = options.zBase or 50

	-- held by reference and mutated in place by the window, so it is always current
	row.formatKeys = options.formatKeys or {}
	row.context    = options.context or {}

	row.iconKey = options.iconKey

	-- the art currently on the icon, and whether it is on screen. Both cached because the row is
	-- re-laid-out on every options change and re-told the class on every name event, and neither
	-- should cost a texture swap when nothing changed.
	row.iconImage = nil
	row.iconShown = false

	-- whether the row as a whole is switched on; the icon lives outside the clip, so hiding the clip
	-- does not hide it
	row.visible = true

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

	row.clip = GRISTLE.ClipWindow( root )

	-------------------------------------------------------------------------------------------------
	-- the class icon: native size, no stretch mode, no edge attachments
	-------------------------------------------------------------------------------------------------
	-- Drawn exactly the way LootLogs draws these emblems in its character list, which is the one way
	-- of showing them proven on this client. Scaling it to the row was tried and failed in game: the
	-- stretch sequence (picture, mode 2, mode 1, size) plus Gibberish3's edge attachments drew the
	-- emblem TILED in a three-by-three grid, and drew it straight through the clip window over the
	-- bar below. So the control is the picture's own 20x20, which leaves the engine nothing to scale
	-- or repeat, and the row is made at least that tall instead (GRISTLE.NameRowHeight).
	--
	-- Parented to the window rather than to the clip: it never needs clipping, being a fixed size at
	-- a fixed place, and keeping it out of the clip keeps it out of whatever went wrong there.
	--
	-- Alpha-blended as LootLogs does: the emblems are round, and without it the square around the
	-- circle is painted as well.
	-------------------------------------------------------------------------------------------------
	row.icon = GRISTLE.Rect( root )
	row.icon:SetBlendMode( Turbine.UI.BlendMode.AlphaBlend )
	row.icon:SetSize( GRISTLE.ClassIconSize, GRISTLE.ClassIconSize )
	row.icon:SetVisible( false )

	row.nameLabel  = GRISTLE.Label( row.clip, Turbine.UI.ContentAlignment.MiddleLeft )
	row.extraLabel = GRISTLE.Label( row.clip, Turbine.UI.ContentAlignment.MiddleRight )

	---------------------------------------------------------------------------------------------------

	function row:ApplyZOrder()

		GRISTLE.ForceZOrder( self.clip, self.zBase )

		GRISTLE.ForceZOrder( self.icon, self.zBase + 1 )

		GRISTLE.ForceZOrder( self.nameLabel,  1 )
		GRISTLE.ForceZOrder( self.extraLabel, 2 )

	end

	function row:ApplyColors()

		local color = GRISTLE.Color( GRISTLE.Settings.colorName )

		self.nameLabel:SetForeColor( color )
		self.extraLabel:SetForeColor( color )

	end

	function row:ApplyFonts()

		local font = GRISTLE.ResolveFont( GRISTLE.Settings.nameFontSize, false )

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

		local border = GRISTLE.Settings.showBorder and GRISTLE.Border or 0

		self.x, self.y = x, y
		self.width  = math.max( 1, math.floor( width ) )
		self.height = math.max( 1, math.floor( height ) )

		local inner = math.max( 1, self.width - 2 * GRISTLE.LabelPadding )

		self.clip:SetPosition( x + border + GRISTLE.LabelPadding, y )
		self.clip:SetSize( inner, self.height )

		self.inner = inner
		self.clipLeft = x + border + GRISTLE.LabelPadding

		self.extraLabel:SetPosition( 0, 0 )
		self.extraLabel:SetSize( inner, self.height )

		self:ApplyIcon()

		-- the labels were just resized, so the cached strings no longer describe what is on screen
		self._lastName  = nil
		self._lastExtra = nil

		self:ApplyZOrder()
		self:Render()

	end

	---------------------------------------------------------------------------------------------------
	-- the class icon
	---------------------------------------------------------------------------------------------------
	-- image is a resource ID from GRISTLE.ClassIcons, or nil for "no icon" - a monster, an object, or
	-- a class this table does not know.
	---------------------------------------------------------------------------------------------------
	function row:SetClassIcon( image )

		if image == self.wantedImage then return end

		self.wantedImage = image

		self:ApplyIcon()

	end

	-- shown, placed and the name label made room for, from what is wanted and what the setting says
	function row:ApplyIcon()

		local image = self.wantedImage

		local shown = image ~= nil
			and ( self.iconKey == nil or GRISTLE.Settings[ self.iconKey ] ~= false )

		local size = GRISTLE.ClassIconSize
		local inner = self.inner or self.width

		if shown and image ~= self.iconImage then

			-- In a pcall because the art lives in the client's dat files and Lua cannot see whether an
			-- ID is still there. A missing emblem is survivable; an error out of a target change is not.
			local ok = pcall( function()
				self.icon:SetBackground( image )
			end )

			if ok then
				self.iconImage = image
			else
				shown = false
			end

		end

		self.iconShown = shown
		self.icon:SetVisible( shown and self.visible )

		-- at the end the name reads from, in the window's co-ordinates: the clip is inset by the
		-- label padding, so the icon sits exactly where the first letter of the name would otherwise
		-- be. Centred down the row, which is never shorter than the icon while it is switched on.
		local clipLeft = self.clipLeft or 0
		local iconLeft = clipLeft + ( self.alignRight and ( inner - size ) or 0 )
		local iconTop  = self.y + math.max( 0, math.floor( ( self.height - size ) / 2 ) )
		self.icon:SetPosition( iconLeft, iconTop )

		local offset = shown and ( size + GRISTLE.ClassIconGap ) or 0
		local nameWidth = math.max( 1, inner - offset )

		self.nameLabel:SetPosition( self.alignRight and 0 or offset, 0 )
		self.nameLabel:SetSize( nameWidth, self.height )

	end

	function row:SetVisible( visible )
		self.visible = visible and true or false
		self.clip:SetVisible( self.visible )
		self.icon:SetVisible( self.iconShown and self.visible )
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

		local nameText = GRISTLE.Format.Render( GRISTLE.Settings[ self.formatKeys.main ], self.context )

		if nameText ~= self._lastName then
			self._lastName = nameText
			self.nameLabel:SetText( nameText )
		end

		local extraText = GRISTLE.Format.Render( GRISTLE.Settings[ self.formatKeys.aside ], self.context )

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

		self:SetClassIcon( nil )

	end

	---------------------------------------------------------------------------------------------------

	row:ApplyColors()
	row:ApplyFonts()
	row:ApplyAlignment()

	return row

end
