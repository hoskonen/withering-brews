-- [scripts/WitheringBrews/ModMenu.lua]
WitheringBrews         = WitheringBrews or {}
WitheringBrews.Config  = WitheringBrews.Config or {}
WitheringBrews.ModMenu = WitheringBrews.ModMenu or {}

local WB = WitheringBrews
local MM = WB.ModMenu

local MOD_ID = "witheringbrews"
local MOD_NAME = "Withering Brews"

local function log(message)
    System.LogAlways(
        "[WitheringBrews/ModMenu] "
        .. tostring(message)
    )
end

function MM.BuildSettings()
    MCM.AddMod(
        MOD_ID,
        MOD_NAME
    )

    MCM.AddCategory(
        MOD_ID,
        "General",
        "General Withering Brews settings."
    )

    MCM.AddToggle(
        MOD_ID,
        "enabled",
        "Enable Mod",
        "MCM integration test only. Gameplay behavior is not disabled yet.",
        WB.Config.Enabled and 1 or 0
    )
end

function MM.OnValueChanged(settingId, value)
    if settingId ~= "enabled" then
        return
    end

    local numericValue = tonumber(value)

    if numericValue == nil then
        log(
            "ignored invalid enabled value: "
            .. tostring(value)
        )

        return
    end

    WB.Config.Enabled =
        numericValue ~= 0

    log(
        "Config.Enabled="
        .. tostring(WB.Config.Enabled)
    )
end

-- Keep stable closures across Script.ReloadScript calls. The closures
-- dispatch through MM, so the functions above may still be updated.
MM._buildListener =
    MM._buildListener
    or function()
        MM.BuildSettings()
    end

MM._valueListener =
    MM._valueListener
    or function(settingId, value)
        MM.OnValueChanged(
            settingId,
            value
        )
    end

if MCM == nil then
    log(
        "MCM global unavailable; menu integration disabled"
    )

    return
end

if not MM._registered then
    MCM.RegisterBuildSettingsListener(
        MM._buildListener
    )

    MCM.RegisterValueChangeListener(
        MOD_ID,
        MM._valueListener
    )

    MM._registered = true

    log("listeners registered")
end