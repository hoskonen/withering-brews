local WB = WitheringBrews
local function LOG(m) if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " ..
        m) end end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

local function K_Stacks(tpl) return "WB_Stacks:" .. tostring(tpl) end
local function now()
    if WB.Clock and type(WB.Clock.Now) == "function" then
        local value = WB.Clock.Now()

        if type(value) == "number" then
            return value
        end
    end

    return nil
end

function WB.CohortsGet(tpl)
    local db = ensureDB(); local list = db and db:Get(K_Stacks(tpl)); return list or {}
end

function WB.CohortsSet(tpl, list)
    local db = ensureDB(); if db then db:Set(K_Stacks(tpl), list) end
end

function WB.CohortsAdd(tpl, qty, created_at, source)
    qty = tonumber(qty) or 1

    local created = tonumber(created_at) or now()

    if type(created) ~= "number" then
        LOG(("CohortsAdd aborted: world clock unavailable tpl=%s")
            :format(tostring(tpl)))
        return false
    end

    local list = WB.CohortsGet(tpl)

    table.insert(list, {
        qty = qty,
        created_at = created,
        source = source or "unknown",
    })

    WB.CohortsSet(tpl, list)

    LOG(("CohortsAdd tpl=%s qty=%d created_at=%d source=%s")
        :format(
            tostring(tpl),
            qty,
            created,
            tostring(source)
        ))

    return true
end

function WB.CohortsTotalQty(tpl)
    local n = 0; for _, c in ipairs(WB.CohortsGet(tpl)) do n = n + (c.qty or 0) end; return n
end

-- Read-only player cohort validation -----------------------------------------

local function validationLog(message)
    System.LogAlways(
        "[WitheringBrews/Cohorts] " .. tostring(message)
    )
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isBootstrapSource(value)
    return type(value) == "string"
        and value:sub(1, 10) == "bootstrap:"
end

function WB.CohortsValidatePlayer()
    local db = ensureDB()

    if not db then
        validationLog("Validation aborted: LuaDB unavailable")
        return false
    end

    local U = WB.Util

    if not (
        U
        and type(U.Player) == "function"
        and type(U.InventorySnapshot) == "function"
    ) then
        validationLog("Validation aborted: inventory utilities unavailable")
        return false
    end

    local playerEntity = U.Player()

    if not playerEntity then
        validationLog("Validation aborted: player unavailable")
        return false
    end

    local currentTime = now()

    if not isFiniteNumber(currentTime) then
        validationLog("Validation aborted: world clock unavailable")
        return false
    end

    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local snapshot = U.InventorySnapshot(playerEntity)

    if type(snapshot) ~= "table" then
        validationLog("Validation aborted: inventory snapshot failed")
        return false
    end

    local entries = {}
    local configuredIds = 0

    for classId in pairs(WB._PotionIndex or {}) do
        configuredIds = configuredIds + 1

        local potion =
            type(WB.GetTrackedPotion) == "function"
            and WB.GetTrackedPotion(classId)
            or nil

        if potion then
            entries[#entries + 1] = {
                classId = classId,
                potion = potion,
            }
        end
    end

    table.sort(entries, function(a, b)
        local familyA = tostring(a.potion.family or "")
        local familyB = tostring(b.potion.family or "")

        if familyA ~= familyB then
            return familyA < familyB
        end

        local tierA = tonumber(a.potion.tier) or 0
        local tierB = tonumber(b.potion.tier) or 0

        if tierA ~= tierB then
            return tierA < tierB
        end

        return a.classId < b.classId
    end)

    local summary = {
        configuredIds = configuredIds,
        trackedIds = #entries,
        activeIds = 0,
        inventoryQty = 0,
        validCohortQty = 0,
        rows = 0,
        missingQty = 0,
        excessQty = 0,
        invalidRows = 0,
        invalidLists = 0,
        futureRows = 0,
        preEpochRows = 0,
    }

    for _, item in ipairs(entries) do
        local classId = item.classId
        local potion = item.potion

        local inventoryQty =
            math.max(
                0,
                math.floor(tonumber(snapshot[classId]) or 0)
            )

        local validCohortQty = 0
        local rowCount = 0
        local invalidRows = 0
        local futureRows = 0
        local preEpochRows = 0
        local invalidList = false
        local problems = {}

        local readOk, rawList = pcall(
            db.Get,
            db,
            K_Stacks(classId)
        )

        if not readOk then
            invalidList = true

            problems[#problems + 1] =
                "INVALID cohort list: DB read failed: "
                .. tostring(rawList)
        elseif rawList ~= nil and type(rawList) ~= "table" then
            invalidList = true

            problems[#problems + 1] =
                "INVALID cohort list: expected table, got "
                .. type(rawList)
        elseif type(rawList) == "table" then
            for rowKey, row in pairs(rawList) do
                rowCount = rowCount + 1

                local reasons = {}
                local isFuture = false
                local isPreEpoch = false

                if type(rowKey) ~= "number"
                    or rowKey < 1
                    or math.floor(rowKey) ~= rowKey
                then
                    reasons[#reasons + 1] =
                        "invalid array key"
                end

                if type(row) ~= "table" then
                    reasons[#reasons + 1] =
                        "row is not a table"
                else
                    local qty = row.qty
                    local createdAt = row.created_at
                    local source = row.source

                    if not isFiniteNumber(qty)
                        or qty < 1
                        or math.floor(qty) ~= qty
                    then
                        reasons[#reasons + 1] =
                            "qty must be a positive integer"
                    end

                    if not isFiniteNumber(createdAt) then
                        reasons[#reasons + 1] =
                            "created_at must be numeric"
                    elseif createdAt < 0 then
                        if isBootstrapSource(source) then
                            isPreEpoch = true
                        else
                            reasons[#reasons + 1] =
                                "created_at is negative for non-bootstrap source"
                        end
                    elseif createdAt > currentTime then
                        reasons[#reasons + 1] =
                            "created_at is in the future"

                        isFuture = true
                    end

                    if type(source) ~= "string"
                        or source == ""
                    then
                        reasons[#reasons + 1] =
                            "source is missing"
                    end

                    if #reasons == 0 then
                        validCohortQty =
                            validCohortQty + qty

                        if isPreEpoch then
                            preEpochRows =
                                preEpochRows + 1
                        end
                    end
                end

                if #reasons > 0 then
                    invalidRows = invalidRows + 1

                    if isFuture then
                        futureRows = futureRows + 1
                    end

                    problems[#problems + 1] =
                        ("INVALID row %s: %s")
                            :format(
                                tostring(rowKey),
                                table.concat(reasons, ", ")
                            )
                end
            end
        end

        local missingQty =
            math.max(0, inventoryQty - validCohortQty)

        local excessQty =
            math.max(0, validCohortQty - inventoryQty)

        local active =
            inventoryQty > 0
            or rowCount > 0
            or invalidList

        if active then
            summary.activeIds = summary.activeIds + 1

            validationLog(
                ("%s tier=%s id=%s")
                    :format(
                        tostring(potion.family or "?"),
                        tostring(potion.label or potion.tier or "?"),
                        classId
                    )
            )

            validationLog(
                ("  inventory=%d cohorts=%d rows=%d missing=%d excess=%d invalidRows=%d futureRows=%d preEpochRows=%d")
                    :format(
                        inventoryQty,
                        validCohortQty,
                        rowCount,
                        missingQty,
                        excessQty,
                        invalidRows,
                        futureRows,
                        preEpochRows
                    )
            )

            for _, problem in ipairs(problems) do
                validationLog("  " .. problem)
            end
        end

        summary.inventoryQty =
            summary.inventoryQty + inventoryQty

        summary.validCohortQty =
            summary.validCohortQty + validCohortQty

        summary.rows =
            summary.rows + rowCount

        summary.missingQty =
            summary.missingQty + missingQty

        summary.excessQty =
            summary.excessQty + excessQty

        summary.invalidRows =
            summary.invalidRows + invalidRows

        summary.futureRows =
            summary.futureRows + futureRows
        
        summary.preEpochRows =
            summary.preEpochRows + preEpochRows

        if invalidList then
            summary.invalidLists =
                summary.invalidLists + 1
        end
    end

    validationLog(
        ("Validation summary: configuredIds=%d trackedIds=%d activeIds=%d inventoryQty=%d validCohortQty=%d rows=%d missingQty=%d excessQty=%d invalidRows=%d invalidLists=%d futureRows=%d preEpochRows=%d writes=0")
            :format(
                summary.configuredIds,
                summary.trackedIds,
                summary.activeIds,
                summary.inventoryQty,
                summary.validCohortQty,
                summary.rows,
                summary.missingQty,
                summary.excessQty,
                summary.invalidRows,
                summary.invalidLists,
                summary.futureRows,
                summary.preEpochRows
            )
    )

    return true, summary
end

-- '#' console helpers
function WB_CohAdd(tpl, qty, ageDays)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohAdd(\"<tpl>\", <qty>, <ageDays_optional>)"); return
    end
    local created = now()

    if type(created) ~= "number" then
        System.LogAlways(
            "[WitheringBrews] WB_CohAdd aborted: world clock unavailable"
        )
        return
    end

    if ageDays then
        created = created -
            math.floor((tonumber(ageDays) or 0) * 86400)
    end

    local added = WB.CohortsAdd(
        tpl,
        tonumber(qty) or 1,
        created,
        "console#"
    )

    if not added then
        return
    end

    System.LogAlways(
        ("[WitheringBrews] WB_CohAdd OK → tpl=%s total=%d")
            :format(tpl, WB.CohortsTotalQty(tpl))
    )
end

function WB_CohList(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohList(\"<tpl>\")"); return
    end
    local list = WB.CohortsGet(tpl)

    System.LogAlways(
        ("[WitheringBrews] WB_CohList tpl=%s count=%d")
            :format(tpl, #list)
    )

    local t = now()

    if type(t) ~= "number" then
        System.LogAlways(
            "[WitheringBrews] WB_CohList aborted: world clock unavailable"
        )
        return
    end

    for i, c in ipairs(list) do
        local created = tonumber(c.created_at)

        if created then
            local ageDays = (t - created) / 86400

            System.LogAlways(
                ("[WitheringBrews]   [%02d] qty=%d created_at=%d age=%.1f d src=%s")
                    :format(
                        i,
                        c.qty or 0,
                        created,
                        ageDays,
                        tostring(c.source or "?")
                    )
            )
        else
            System.LogAlways(
                ("[WitheringBrews]   [%02d] INVALID: missing created_at")
                    :format(i)
            )
        end
    end
end

function WB_CohClear(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohClear(\"<tpl>\")"); return
    end
    WB.CohortsSet(tpl, {}); System.LogAlways(("[WitheringBrews] WB_CohClear tpl=%s"):format(tpl))
end
