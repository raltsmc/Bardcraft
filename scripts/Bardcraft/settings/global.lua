local I = require('openmw.interfaces')

-- Settings page
I.Settings.registerGroup {
    key = 'Settings/Bardcraft/3_Options',
    page = 'Bardcraft',
    l10n = 'Bardcraft',
    name = 'ConfigCategoryOptions',
    permanentStorage = true,
    settings = {
        {
            key = 'silenceAmbientMusic',
            renderer = 'checkbox',
            name = 'ConfigAmbientMusic',
            description = 'ConfigAmbientMusicDesc',
            default = true,
        },
        {
            key = 'nearbyNpcsDance',
            renderer = 'checkbox',
            name = 'ConfigNearbyNpcsDance',
            description = 'ConfigNearbyNpcsDanceDesc',
            default = true,
        },
        {
            key = 'danceTimingVariation',
            renderer = 'checkbox',
            name = 'ConfigDanceTimingVariation',
            description = 'ConfigDanceTimingVariationDesc',
            default = true,
        },
    },
}

I.Settings.registerGroup {
    key = 'Settings/Bardcraft/4_Technical',
    page = 'Bardcraft',
    l10n = 'Bardcraft',
    name = 'ConfigCategoryTechnical',
    description = 'ConfigCategoryTechnicalDesc',
    permanentStorage = true,
    settings = {
        {
            key = 'silenceAmbientMusicInterval',
            renderer = 'number',
            name = 'ConfigSilenceAmbientMusicInterval',
            description = 'ConfigSilenceAmbientMusicIntervalDesc',
            default = 30,
            min = 1,
            max = 60,
        },
        {
            key = 'npcDanceDistance',
            renderer = 'number',
            name = 'ConfigNpcDanceDistance',
            description = 'ConfigNpcDanceDistanceDesc',
            default = 1500,
            min = 0,
            max = 10000,
        },
    },
}

return {
    eventHandlers = {
        UpdateGlobalSettingArg = function(data)
            I.Settings.updateRendererArgument(data.groupKey, data.settingKey, data.args)
        end
    }
}