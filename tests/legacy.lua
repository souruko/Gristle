--=================================================================================================
--= Gristle tests: settings saved while the plugin was still called Sinew
--=
--= A separate process from run.lua because it needs a savefile on the fake disk *before* Main.lua
--= loads, and run.lua's defaults checks need an empty one.
--=
--=     cd Gristle && lua tests/legacy.lua [euro]
--=================================================================================================

local passed, failed = 0, 0

local function check( name, got, want )
	if got == want then
		passed = passed + 1
	else
		failed = failed + 1
		print( string.format( "  FAIL  %s\n          got:  %s\n          want: %s",
			name, tostring( got ), tostring( want ) ) )
	end
end

local stub = dofile( "tests/turbine_stub.lua" )

local euro = ( ... ) == "euro" or arg ~= nil and arg[1] == "euro"

local player = stub.NewActor( { name = "Souru", morale = 1000, maxMorale = 1000,
                                power = 500, maxPower = 500, kind = "player", class = 24 } )

stub.Install( player, { euro = euro } )

-- what a Sinew 1.2.0 install left on disk: a character file and an account copy, under the old key
local function legacy( width )
	return { version = euro and "4" or 4, selfWidth = euro and tostring( width ) or width }
end

stub.store.character = { sinewSettings = legacy( 310 ) }
stub.store.account   = { sinewSettings = legacy( 280 ) }

local ok, err = pcall( function() import( "Gristle.Main" ) end )

check( "Main.lua loads with only a Sinew savefile on disk", ok, true )

if not ok then
	print( "          " .. tostring( err ) )
	os.exit( 1 )
end

check( "the character's Sinew settings are picked up", GRISTLE.Settings.selfWidth, 310 )
check( "the Sinew account copy counts as an account copy", GRISTLE.HasGlobalSettings(), true )

GRISTLE.Save()

check( "the next save goes under the new key", stub.store.character.gristleSettings ~= nil, true )
check( "the old character file is left alone",
	stub.store.character.sinewSettings.selfWidth, euro and "310" or 310 )
check( "an existing account copy is not overwritten by a character save",
	stub.store.account.gristleSettings, nil )

print( string.format( "%d passed, %d failed", passed, failed ) )

os.exit( failed == 0 and 0 or 1 )
