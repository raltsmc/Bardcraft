local I = require('openmw.interfaces')

-- Settings page
I.Settings.registerGroup {
    key = 'Settings/Bardcraft/3_GlobalOptions',
    page = 'Bardcraft',
    l10n = 'Bardcraft',
    name = 'ConfigCategoryGlobalOptions',
    permanentStorage = true,
    settings = {
    },
}