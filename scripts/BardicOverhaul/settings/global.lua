local I = require('openmw.interfaces')

-- Settings page
I.Settings.registerGroup {
    key = 'Settings/BardicOverhaul/3_Options',
    page = 'BardicOverhaul',
    l10n = 'BardicOverhaul',
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
    key = 'Settings/BardicOverhaul/4_Technical',
    page = 'BardicOverhaul',
    l10n = 'BardicOverhaul',
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