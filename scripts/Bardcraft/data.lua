local INSTRUMENT_ITEMS = {
    Lute = {
        misc_de_lute_01 = true, -- Vanilla
        misc_de_lute_01_phat = true,
        t_imp_lute_01 = true, -- Tamriel Data
        t_com_lute_01 = true,
        t_de_uni_renaldlute = true,
        t_imp_uni_goldenlute = true,
        t_de_music_adun = true,
        t_de_music_shiratar = true,
        ab_mus_delutethin = true, -- OOAB Data
    },
    Drum = {
        misc_de_drum_01 = true, -- Vanilla
        misc_de_drum_02 = true,
        t_imp_drum_01 = true, -- Tamriel Data
        t_imp_drum_02 = true,
        t_imp_drum_03 = true,
        t_imp_drum_04 = true,
        t_nor_deerskin_drum_01 = true,
        t_orc_drum_01 = true,
        t_rga_drum_01 = true,
    },
    Ocarina = {
        _rlts_bc_ocarina = true, -- Bardcraft
    },
    BassFlute = {
        _rlts_bc_bassflute = true, -- Bardcraft
    },
    PanFlute = {
        t_de_music_panflute_01 = true,
        ab_misc_6thflute = true,
        ab_misc_ashlflute = true,
        ab_mus_6thflute = true,
        ab_mus_ashlflute = true,
    },
    Harp = {
        t_de_music_sudahk = true,
        ab_mus_deharp = true,
    },
    Lyre = {
        t_de_music_lyre_01 = true,
        t_de_music_takuratum = true,
        ab_mus_delyre = true,
        ab_mus_ashllyre = true,
    },
}

local PUBLICAN_CLASSES = {
    publican = true,
    t_sky_publican = true,
    t_cyr_publican = true,
    t_glb_publican = true,
}

return {
    InstrumentItems = INSTRUMENT_ITEMS,
    PublicanClasses = PUBLICAN_CLASSES,
}