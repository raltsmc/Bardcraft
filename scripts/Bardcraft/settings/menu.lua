local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local I = require('openmw.interfaces')
local ui = require('openmw.ui')

local l10n = core.l10n('Bardcraft')

local versionString = require('scripts.Bardcraft.data').Version

-- inputKeySelection by Pharis
I.Settings.registerRenderer('Bardcraft/inputKeySelection', function(value, set)
	local name = 'No Key Set'
	if value then
		name = input.getKeyName(value)
	end
	return {
		template = I.MWUI.templates.box,
		content = ui.content {
			{
				template = I.MWUI.templates.padding,
				content = ui.content {
					{
						template = I.MWUI.templates.textEditLine,
						props = {
							text = name,
						},
						events = {
							keyPress = async:callback(function(e)
								if e.code == input.KEY.Escape then return end
								set(e.code)
							end),
						},
					},
				},
			},
		},
	}
end)

-- Settings page
I.Settings.registerPage {
    key = 'Bardcraft',
    l10n = 'Bardcraft',
    name = 'ConfigTitle',
    description = l10n('ConfigSummary'):gsub('%%{version}', versionString),
}
I.Settings.registerGroup {
    key = 'Settings/Bardcraft/1_Keybinds',
    page = 'Bardcraft',
    l10n = 'Bardcraft',
    name = 'ConfigCategoryKeybinds',
    permanentStorage = true,
    settings = {
        {
            key = 'kOpenInterface',
            renderer = 'Bardcraft/inputKeySelection',
            name = 'ConfigKeybindOpenInterface',
			description = 'ConfigKeybindOpenInterfaceDesc',
            default = input.KEY.B
        },
    },
}
I.Settings.registerGroup {
	key = 'Settings/Bardcraft/2_PlayerOptions',
	page = 'Bardcraft',
	l10n = 'Bardcraft',
	name = 'ConfigCategoryPlayerOptions',
	permanentStorage = true,
	settings = {
        {
            key = 'bSilenceAmbientMusic',
            renderer = 'checkbox',
            name = 'ConfigAmbientMusic',
            description = 'ConfigAmbientMusicDesc',
            default = true,
        },
		{
			key = 'bPrecacheSamples',
			renderer = 'checkbox',
			name = 'ConfigPrecacheSamples',
			description = 'ConfigPrecacheSamplesDesc',
			default = true,
		},
		{
			key = 'fUiScaleX',
			renderer = 'number',
			name = 'ConfigUiScaleX',
			default = 1.0,
			argument = {
				min = 0.01,
				max = 10.0,
			},
		},
		{
			key = 'fUiScaleY',
			renderer = 'number',
			name = 'ConfigUiScaleY',
			default = 1.0,
			argument = {
				min = 0.01,
				max = 10.0,
			},
		},
	},
}