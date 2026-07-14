-- [Scripts/WitheringBrews/Clock.lua]
WitheringBrews = WitheringBrews or {}
WitheringBrews.Clock = WitheringBrews.Clock or {}

local Clock = WitheringBrews.Clock

function Clock.Now()
    if KCDUtils
        and KCDUtils.Calendar
        and type(KCDUtils.Calendar.GetWorldTime) == "function"
    then
        local ok, value = pcall(KCDUtils.Calendar.GetWorldTime)

        if ok and type(value) == "number" then
            return math.floor(value), "KCDUtils.Calendar"
        end
    end

    if Calendar
        and type(Calendar.GetWorldTime) == "function"
    then
        local ok, value = pcall(Calendar.GetWorldTime)

        if ok and type(value) == "number" then
            return math.floor(value), "Calendar"
        end
    end

    return nil, "unavailable"
end