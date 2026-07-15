-- [scripts/WitheringBrews/Events.lua]

WitheringBrews.Events = WitheringBrews.Events or {}

local EV, WB = WitheringBrews.Events, WitheringBrews

local function log(message)
    System.LogAlways(
        "[WitheringBrews/Events] " .. message
    )
end

-- Bind a movie event using ElementListener at root (-1).
local function bind_el(movie, eventName, fnName)
    if not (
        UIAction
        and UIAction.RegisterElementListener
    ) then
        log(
            ("RegisterElementListener missing (wanted %s.%s → %s)")
                :format(movie, eventName, fnName)
        )

        return false
    end

    local ok, err = pcall(
        UIAction.RegisterElementListener,
        WB,
        movie,
        -1,
        eventName,
        fnName
    )

    if ok then
        log(
            ("ElementListener bound: %s.%s → %s")
                :format(movie, eventName, fnName)
        )
    else
        log(
            ("ElementListener FAILED: %s.%s → %s :: %s")
                :format(
                    movie,
                    eventName,
                    fnName,
                    tostring(err)
                )
        )
    end

    return ok
end

local function bind_system(eventName, fnName)
    if not (
        UIAction
        and UIAction.RegisterEventSystemListener
    ) then
        log(
            ("RegisterEventSystemListener missing (wanted System.%s → %s)")
                :format(eventName, fnName)
        )

        return false
    end

    local ok, err = pcall(
        UIAction.RegisterEventSystemListener,
        WB,
        "System",
        eventName,
        fnName
    )

    if ok then
        log(
            ("System listener bound: %s → %s")
                :format(eventName, fnName)
        )
    else
        log(
            ("System listener FAILED: %s → %s :: %s")
                :format(
                    eventName,
                    fnName,
                    tostring(err)
                )
        )
    end

    return ok
end

function EV.BindAll()
    if EV._bound then
        log("BindAll skipped: listeners already bound")
        return true
    end

    local systemBound = bind_system(
        "OnGameplayStarted",
        "OnGameplayStarted"
    )

    local openedBound = bind_el(
        "ItemTransfer",
        "OnOpened",
        "OnItemTransferOpened"
    )

    local closedBound = bind_el(
        "ItemTransfer",
        "OnClosed",
        "OnItemTransferClosed"
    )

    if not (
        systemBound
        and openedBound
        and closedBound
    ) then
        log("BindAll incomplete: retry remains allowed")
        return false
    end

    EV._bound = true
    EV._bindAllCalls =
        (EV._bindAllCalls or 0) + 1

    log("BindAll complete")

    return true
end