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

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function WB.CohortsGet(tpl)
    local db = ensureDB(); local list = db and db:Get(K_Stacks(tpl)); return list or {}
end

function WB.CohortsSet(tpl, list)
    local db = ensureDB(); if db then db:Set(K_Stacks(tpl), list) end
end

function WB.CohortsAdd(tpl, qty, created_at, source)
    local normalizedQty = tonumber(qty)

    if normalizedQty == nil then
        normalizedQty = 1
    end

    if not isFiniteNumber(normalizedQty)
        or normalizedQty < 1
        or math.floor(normalizedQty) ~= normalizedQty
    then
        LOG(
            ("CohortsAdd aborted: qty must be a positive integer tpl=%s qty=%s")
                :format(
                    tostring(tpl),
                    tostring(qty)
                )
        )

        return false
    end

    local created

    if created_at == nil then
        created = now()
    else
        created = tonumber(created_at)
    end

    if not isFiniteNumber(created) then
        LOG(
            ("CohortsAdd aborted: invalid or unavailable timestamp tpl=%s created_at=%s")
                :format(
                    tostring(tpl),
                    tostring(created_at)
                )
        )

        return false
    end

    local normalizedSource = source

    if type(normalizedSource) ~= "string"
        or normalizedSource == ""
    then
        normalizedSource = "unknown"
    end

    local list = WB.CohortsGet(tpl)

    if type(list) ~= "table" then
        LOG(
            ("CohortsAdd aborted: stored cohort list is not a table tpl=%s")
                :format(tostring(tpl))
        )

        return false
    end

    local matchingIndexes = {}
    local mergedQty = normalizedQty

    for index, row in ipairs(list) do
        if type(row) == "table" then
            local rowQty = tonumber(row.qty)
            local rowCreated = row.created_at
            local rowSource = row.source

            local validRowQty =
                isFiniteNumber(rowQty)
                and rowQty >= 1
                and math.floor(rowQty) == rowQty

            local exactMatch =
                validRowQty
                and isFiniteNumber(rowCreated)
                and type(rowSource) == "string"
                and rowSource ~= ""
                and rowCreated == created
                and rowSource == normalizedSource

            if exactMatch then
                matchingIndexes[#matchingIndexes + 1] =
                    index

                mergedQty =
                    mergedQty + rowQty
            end
        end
    end

    if #matchingIndexes > 0 then
        local primaryIndex =
            matchingIndexes[1]

        list[primaryIndex].qty =
            mergedQty

        -- Remove additional pre-existing exact duplicates.
        -- Iterate backwards so earlier indexes do not shift.
        for index = #matchingIndexes, 2, -1 do
            table.remove(
                list,
                matchingIndexes[index]
            )
        end

        WB.CohortsSet(tpl, list)

        LOG(
            ("CohortsAdd merged tpl=%s addedQty=%d rowQty=%d created_at=%s source=%s compactedRows=%d")
                :format(
                    tostring(tpl),
                    normalizedQty,
                    mergedQty,
                    tostring(created),
                    normalizedSource,
                    #matchingIndexes - 1
                )
        )

        return true
    end

    table.insert(list, {
        qty = normalizedQty,
        created_at = created,
        source = normalizedSource,
    })

    WB.CohortsSet(tpl, list)

    LOG(
        ("CohortsAdd appended tpl=%s qty=%d created_at=%s source=%s")
            :format(
                tostring(tpl),
                normalizedQty,
                tostring(created),
                normalizedSource
            )
    )

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

-- Read-only player reconciliation preview -----------------------------------

local function reconciliationLog(message)
    System.LogAlways(
        "[WitheringBrews/Reconcile] "
        .. tostring(message)
    )
end

function WB.CohortsPreviewPlayerReconciliation()
    local db = ensureDB()

    if not db then
        reconciliationLog(
            "Preview aborted: LuaDB unavailable"
        )
        return false
    end

    local U = WB.Util

    if not (
        U
        and type(U.Player) == "function"
        and type(U.InventorySnapshot) == "function"
    ) then
        reconciliationLog(
            "Preview aborted: inventory utilities unavailable"
        )
        return false
    end

    local playerEntity = U.Player()

    if not playerEntity then
        reconciliationLog(
            "Preview aborted: player unavailable"
        )
        return false
    end

    local currentTime = now()

    if not isFiniteNumber(currentTime) then
        reconciliationLog(
            "Preview aborted: world clock unavailable"
        )
        return false
    end

    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local snapshot =
        U.InventorySnapshot(playerEntity)

    if type(snapshot) ~= "table" then
        reconciliationLog(
            "Preview aborted: inventory snapshot failed"
        )
        return false
    end

    local entries = {}

    for classId in pairs(WB._PotionIndex or {}) do
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
        local familyA =
            tostring(a.potion.family or "")

        local familyB =
            tostring(b.potion.family or "")

        if familyA ~= familyB then
            return familyA < familyB
        end

        local tierA =
            tonumber(a.potion.tier) or 0

        local tierB =
            tonumber(b.potion.tier) or 0

        if tierA ~= tierB then
            return tierA < tierB
        end

        return a.classId < b.classId
    end)

    local summary = {
        trackedIds = #entries,
        mismatchedIds = 0,
        blockedIds = 0,
        missingQty = 0,
        excessQty = 0,
        additionRows = 0,
        removalActions = 0,
    }

    local plans = {}

    for _, item in ipairs(entries) do
        local classId = item.classId
        local potion = item.potion

        local inventoryQty =
            math.max(
                0,
                math.floor(
                    tonumber(snapshot[classId]) or 0
                )
            )

        local rowCount = 0
        local cohortQty = 0
        local validRows = {}
        local blockedReasons = {}

        local readOk, rawList = pcall(
            db.Get,
            db,
            K_Stacks(classId)
        )

        if not readOk then
            blockedReasons[#blockedReasons + 1] =
                "DB read failed: "
                .. tostring(rawList)
        elseif rawList ~= nil
            and type(rawList) ~= "table"
        then
            blockedReasons[#blockedReasons + 1] =
                "cohort list is "
                .. type(rawList)
                .. ", expected table"
        elseif type(rawList) == "table" then
            for rowKey, row in pairs(rawList) do
                rowCount = rowCount + 1

                local reasons = {}

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
                    local createdAt =
                        row.created_at

                    local source =
                        row.source

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
                    elseif createdAt < 0
                        and not isBootstrapSource(source)
                    then
                        reasons[#reasons + 1] =
                            "negative created_at "
                            .. "requires bootstrap source"
                    elseif createdAt > currentTime then
                        reasons[#reasons + 1] =
                            "created_at is in the future"
                    end

                    if type(source) ~= "string"
                        or source == ""
                    then
                        reasons[#reasons + 1] =
                            "source is missing"
                    end

                    if #reasons == 0 then
                        cohortQty =
                            cohortQty + qty

                        validRows[#validRows + 1] = {
                            index = rowKey,
                            qty = qty,
                            created_at = createdAt,
                            source = source,
                        }
                    end
                end

                if #reasons > 0 then
                    blockedReasons[#blockedReasons + 1] =
                        ("row %s: %s")
                            :format(
                                tostring(rowKey),
                                table.concat(
                                    reasons,
                                    ", "
                                )
                            )
                end
            end
        end

        local active =
            inventoryQty > 0
            or rowCount > 0

        if #blockedReasons > 0 then
            summary.blockedIds =
                summary.blockedIds + 1

            reconciliationLog(
                ("%s tier=%s id=%s BLOCKED")
                    :format(
                        tostring(
                            potion.family or "?"
                        ),
                        tostring(
                            potion.label
                            or potion.tier
                            or "?"
                        ),
                        classId
                    )
            )

            reconciliationLog(
                ("  inventory=%d validCohorts=%d rows=%d")
                    :format(
                        inventoryQty,
                        cohortQty,
                        rowCount
                    )
            )

            for _, reason in ipairs(blockedReasons) do
                reconciliationLog(
                    "  " .. reason
                )
            end
        elseif active then
            local missingQty =
                math.max(
                    0,
                    inventoryQty - cohortQty
                )

            local excessQty =
                math.max(
                    0,
                    cohortQty - inventoryQty
                )

            if missingQty > 0
                or excessQty > 0
            then
                summary.mismatchedIds =
                    summary.mismatchedIds + 1

                summary.missingQty =
                    summary.missingQty + missingQty

                summary.excessQty =
                    summary.excessQty + excessQty

                local plan = {
                    classId = classId,
                    family = potion.family,
                    tier = potion.tier,
                    inventoryQty = inventoryQty,
                    cohortQty = cohortQty,
                    addition = nil,
                    removals = {},
                }

                reconciliationLog(
                    ("%s tier=%s id=%s")
                        :format(
                            tostring(
                                potion.family or "?"
                            ),
                            tostring(
                                potion.label
                                or potion.tier
                                or "?"
                            ),
                            classId
                        )
                )

                reconciliationLog(
                    ("  inventory=%d cohorts=%d missing=%d excess=%d")
                        :format(
                            inventoryQty,
                            cohortQty,
                            missingQty,
                            excessQty
                        )
                )

                if missingQty > 0 then
                    plan.addition = {
                        qty = missingQty,
                        created_at = currentTime,
                        source = "reconcile:player",
                    }

                    summary.additionRows =
                        summary.additionRows + 1

                    reconciliationLog(
                        ("  WOULD ADD qty=%d created_at=%d source=reconcile:player")
                            :format(
                                missingQty,
                                currentTime
                            )
                    )
                end

                if excessQty > 0 then
                    table.sort(
                        validRows,
                        function(a, b)
                            if a.created_at
                                ~= b.created_at
                            then
                                return a.created_at
                                    < b.created_at
                            end

                            return a.index < b.index
                        end
                    )

                    local remaining =
                        excessQty

                    for _, row in ipairs(validRows) do
                        if remaining <= 0 then
                            break
                        end

                        local removeQty =
                            math.min(
                                row.qty,
                                remaining
                            )

                        local keepQty =
                            row.qty - removeQty

                        local ageDays =
                            (
                                currentTime
                                - row.created_at
                            ) / 86400

                        plan.removals[
                            #plan.removals + 1
                        ] = {
                            index = row.index,
                            removeQty = removeQty,
                            originalQty = row.qty,
                            remainingQty = keepQty,
                            created_at =
                                row.created_at,
                            source = row.source,
                        }

                        summary.removalActions =
                            summary.removalActions + 1

                        reconciliationLog(
                            ("  WOULD REMOVE row=%s qty=%d fromRowQty=%d keep=%d created_at=%s age=%.1fd source=%s")
                                :format(
                                    tostring(row.index),
                                    removeQty,
                                    row.qty,
                                    keepQty,
                                    tostring(
                                        row.created_at
                                    ),
                                    ageDays,
                                    tostring(row.source)
                                )
                        )

                        remaining =
                            remaining - removeQty
                    end

                    if remaining > 0 then
                        reconciliationLog(
                            ("  INTERNAL ERROR: unable to plan remaining excess qty=%d")
                                :format(
                                    remaining
                                )
                        )
                    end
                end

                plans[#plans + 1] =
                    plan
            end
        end
    end

    reconciliationLog(
        ("Preview summary: trackedIds=%d mismatchedIds=%d blockedIds=%d missingQty=%d excessQty=%d additionRows=%d removalActions=%d writes=0")
            :format(
                summary.trackedIds,
                summary.mismatchedIds,
                summary.blockedIds,
                summary.missingQty,
                summary.excessQty,
                summary.additionRows,
                summary.removalActions
            )
    )

    return true, summary, plans
end

-- Guarded player reconciliation writes --------------------------------------

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}

    for key, child in pairs(value) do
        result[key] = copyValue(child)
    end

    return result
end

local function valuesEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not valuesEqual(value, right[key]) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

local function isDenseArray(list)
    if type(list) ~= "table" then
        return false
    end

    local count = 0
    local maximumIndex = 0

    for key in pairs(list) do
        if type(key) ~= "number"
            or key < 1
            or math.floor(key) ~= key
        then
            return false
        end

        count = count + 1
        maximumIndex = math.max(
            maximumIndex,
            key
        )
    end

    return maximumIndex == count
end

local function validateStoredCohortList(list, currentTime)
    if not isDenseArray(list) then
        return false, 0, "cohort list is not a dense array"
    end

    local totalQty = 0

    for index, row in ipairs(list) do
        if type(row) ~= "table" then
            return false,
                totalQty,
                ("row %d is not a table")
                    :format(index)
        end

        local qty = row.qty
        local createdAt = row.created_at
        local source = row.source

        if not isFiniteNumber(qty)
            or qty < 1
            or math.floor(qty) ~= qty
        then
            return false,
                totalQty,
                ("row %d has invalid qty")
                    :format(index)
        end

        if not isFiniteNumber(createdAt) then
            return false,
                totalQty,
                ("row %d has invalid created_at")
                    :format(index)
        end

        if createdAt < 0
            and not isBootstrapSource(source)
        then
            return false,
                totalQty,
                ("row %d has negative non-bootstrap timestamp")
                    :format(index)
        end

        if createdAt > currentTime then
            return false,
                totalQty,
                ("row %d is dated in the future")
                    :format(index)
        end

        if type(source) ~= "string"
            or source == ""
        then
            return false,
                totalQty,
                ("row %d has invalid source")
                    :format(index)
        end

        totalQty = totalQty + qty
    end

    return true, totalQty, nil
end

local function addExactCohortToList(list, addition)
    for _, row in ipairs(list) do
        if row.created_at == addition.created_at
            and row.source == addition.source
        then
            row.qty = row.qty + addition.qty
            return "merged"
        end
    end

    table.insert(
        list,
        copyValue(addition)
    )

    return "appended"
end

local function restoreCohortList(
    db,
    key,
    originalList
)
    local writeOk, writeError = pcall(
        db.Set,
        db,
        key,
        copyValue(originalList)
    )

    if not writeOk then
        return false,
            "rollback write failed: "
            .. tostring(writeError)
    end

    local readOk, restoredList = pcall(
        db.Get,
        db,
        key
    )

    if not readOk then
        return false,
            "rollback read failed: "
            .. tostring(restoredList)
    end

    if restoredList == nil then
        restoredList = {}
    end

    if not valuesEqual(
        restoredList,
        originalList
    ) then
        return false,
            "rollback read-back did not match original"
    end

    return true
end

function WB.CohortsApplyPlayerReconciliation(
    confirmation
)
    if confirmation ~= "APPLY" then
        reconciliationLog(
            "Apply aborted: explicit confirmation required"
        )

        reconciliationLog(
            'Use: # WB_CohReconcileApply("APPLY")'
        )

        return false
    end

    if not (
        WB.Config
        and WB.Config.DryRun == false
    ) then
        reconciliationLog(
            "Apply aborted: DryRun must be false"
        )

        return false
    end

    local previewOk, previewSummary, plans =
        WB.CohortsPreviewPlayerReconciliation()

    if not previewOk then
        reconciliationLog(
            "Apply aborted: preview failed"
        )

        return false
    end

    local db = ensureDB()

    if not db then
        reconciliationLog(
            "Apply aborted: LuaDB unavailable"
        )

        return false
    end

    local currentTime = now()

    if not isFiniteNumber(currentTime) then
        reconciliationLog(
            "Apply aborted: world clock unavailable"
        )

        return false
    end

    local U = WB.Util
    local playerEntity =
        U
        and U.Player
        and U.Player()
        or nil

    if not playerEntity then
        reconciliationLog(
            "Apply aborted: player unavailable"
        )

        return false
    end

    -- Take a second inventory snapshot after planning.
    -- A changed quantity invalidates that potion's plan.
    local liveSnapshot =
        U.InventorySnapshot(playerEntity)

    if type(liveSnapshot) ~= "table" then
        reconciliationLog(
            "Apply aborted: live inventory snapshot failed"
        )

        return false
    end

    local summary = {
        plannedIds = #plans,
        appliedIds = 0,
        skippedIds = 0,
        failedIds = 0,
        blockedIds =
            previewSummary.blockedIds or 0,
        dbWrites = 0,
        rollbacks = 0,
        rollbackFailures = 0,
    }

    for _, plan in ipairs(plans) do
        local classId = plan.classId
        local key = K_Stacks(classId)

        local liveInventoryQty =
            math.max(
                0,
                math.floor(
                    tonumber(
                        liveSnapshot[classId]
                    ) or 0
                )
            )

        local skipReason = nil

        if liveInventoryQty
            ~= plan.inventoryQty
        then
            skipReason =
                ("inventory changed after preview: planned=%d live=%d")
                    :format(
                        plan.inventoryQty,
                        liveInventoryQty
                    )
        end

        local readOk, currentList

        if not skipReason then
            readOk, currentList = pcall(
                db.Get,
                db,
                key
            )

            if not readOk then
                skipReason =
                    "DB read failed: "
                    .. tostring(currentList)
            elseif currentList == nil then
                currentList = {}
            elseif type(currentList) ~= "table" then
                skipReason =
                    "stored cohort value is not a table"
            end
        end

        local currentTotal = nil

        if not skipReason then
            local validList, totalQty, reason =
                validateStoredCohortList(
                    currentList,
                    currentTime
                )

            if not validList then
                skipReason =
                    "stored cohorts changed or became invalid: "
                    .. tostring(reason)
            elseif totalQty ~= plan.cohortQty then
                skipReason =
                    ("cohort total changed after preview: planned=%d live=%d")
                        :format(
                            plan.cohortQty,
                            totalQty
                        )
            else
                currentTotal = totalQty
            end
        end

        if skipReason then
            summary.skippedIds =
                summary.skippedIds + 1

            reconciliationLog(
                ("SKIPPED id=%s reason=%s")
                    :format(
                        tostring(classId),
                        skipReason
                    )
            )
        else
            local originalList =
                copyValue(currentList)

            local workingList =
                copyValue(currentList)

            local applyError = nil

            if plan.addition then
                addExactCohortToList(
                    workingList,
                    plan.addition
                )
            end

            local indexesToRemove = {}

            for _, removal in ipairs(
                plan.removals or {}
            ) do
                local row =
                    workingList[removal.index]

                if type(row) ~= "table" then
                    applyError =
                        ("planned row %s no longer exists")
                            :format(
                                tostring(
                                    removal.index
                                )
                            )

                    break
                end

                if row.qty
                    ~= removal.originalQty
                    or row.created_at
                    ~= removal.created_at
                    or row.source
                    ~= removal.source
                then
                    applyError =
                        ("planned row %s changed before apply")
                            :format(
                                tostring(
                                    removal.index
                                )
                            )

                    break
                end

                if removal.remainingQty > 0 then
                    row.qty =
                        removal.remainingQty
                else
                    indexesToRemove[
                        #indexesToRemove + 1
                    ] = removal.index
                end
            end

            if not applyError then
                table.sort(
                    indexesToRemove,
                    function(left, right)
                        return left > right
                    end
                )

                for _, index in ipairs(
                    indexesToRemove
                ) do
                    table.remove(
                        workingList,
                        index
                    )
                end

                local validAfter,
                    totalAfter,
                    validationError =
                    validateStoredCohortList(
                        workingList,
                        currentTime
                    )

                if not validAfter then
                    applyError =
                        "planned result is invalid: "
                        .. tostring(
                            validationError
                        )
                elseif totalAfter
                    ~= liveInventoryQty
                then
                    applyError =
                        ("planned result does not match inventory: result=%d inventory=%d")
                            :format(
                                totalAfter,
                                liveInventoryQty
                            )
                end
            end

            if applyError then
                summary.skippedIds =
                    summary.skippedIds + 1

                reconciliationLog(
                    ("SKIPPED id=%s reason=%s")
                        :format(
                            tostring(classId),
                            applyError
                        )
                )
            else
                local writeOk, writeError =
                    pcall(
                        db.Set,
                        db,
                        key,
                        workingList
                    )

                if writeOk then
                    summary.dbWrites =
                        summary.dbWrites + 1
                end

                local verifyOk = false
                local verifyReason = nil

                if not writeOk then
                    verifyReason =
                        "DB write failed: "
                        .. tostring(writeError)
                else
                    local readBackOk,
                        storedList =
                        pcall(
                            db.Get,
                            db,
                            key
                        )

                    if not readBackOk then
                        verifyReason =
                            "DB verification read failed: "
                            .. tostring(
                                storedList
                            )
                    else
                        if storedList == nil then
                            storedList = {}
                        end

                        local validStored,
                            storedTotal,
                            storedError =
                            validateStoredCohortList(
                                storedList,
                                currentTime
                            )

                        if not validStored then
                            verifyReason =
                                "stored result is invalid: "
                                .. tostring(
                                    storedError
                                )
                        elseif storedTotal
                            ~= liveInventoryQty
                        then
                            verifyReason =
                                ("stored total mismatch: stored=%d inventory=%d")
                                    :format(
                                        storedTotal,
                                        liveInventoryQty
                                    )
                        elseif not valuesEqual(
                            storedList,
                            workingList
                        ) then
                            verifyReason =
                                "stored rows differ from planned rows"
                        else
                            verifyOk = true
                        end
                    end
                end

                if verifyOk then
                    summary.appliedIds =
                        summary.appliedIds + 1

                    reconciliationLog(
                        ("APPLIED family=%s tier=%s id=%s before=%d after=%d rowsBefore=%d rowsAfter=%d")
                            :format(
                                tostring(
                                    plan.family
                                    or "?"
                                ),
                                tostring(
                                    plan.tier
                                    or "?"
                                ),
                                tostring(classId),
                                currentTotal or 0,
                                liveInventoryQty,
                                #originalList,
                                #workingList
                            )
                    )
                else
                    summary.failedIds =
                        summary.failedIds + 1

                    reconciliationLog(
                        ("FAILED id=%s reason=%s")
                            :format(
                                tostring(classId),
                                tostring(
                                    verifyReason
                                )
                            )
                    )

                    local rollbackOk,
                        rollbackError =
                        restoreCohortList(
                            db,
                            key,
                            originalList
                        )

                    if rollbackOk then
                        summary.rollbacks =
                            summary.rollbacks + 1

                        reconciliationLog(
                            ("ROLLBACK OK id=%s")
                                :format(
                                    tostring(classId)
                                )
                        )
                    else
                        summary.rollbackFailures =
                            summary.rollbackFailures
                            + 1

                        reconciliationLog(
                            ("CRITICAL: ROLLBACK FAILED id=%s reason=%s")
                                :format(
                                    tostring(classId),
                                    tostring(
                                        rollbackError
                                    )
                                )
                        )
                    end
                end
            end
        end
    end

    reconciliationLog(
        ("Apply summary: plannedIds=%d appliedIds=%d skippedIds=%d failedIds=%d blockedIds=%d dbWrites=%d rollbacks=%d rollbackFailures=%d inventoryWrites=0")
            :format(
                summary.plannedIds,
                summary.appliedIds,
                summary.skippedIds,
                summary.failedIds,
                summary.blockedIds,
                summary.dbWrites,
                summary.rollbacks,
                summary.rollbackFailures
            )
    )

    local successful =
        summary.failedIds == 0
        and summary.rollbackFailures == 0

    return successful, summary
end

-- '#' console helpers

function WB_CohReconcilePreview()
    return WB.CohortsPreviewPlayerReconciliation()
end

function WB_CohReconcileApply(confirmation)
    return WB.CohortsApplyPlayerReconciliation(
        confirmation
    )
end

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
