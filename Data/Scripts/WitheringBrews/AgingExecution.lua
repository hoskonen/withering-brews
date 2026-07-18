-- Withering Brews: guarded aging transaction orchestration
--
-- Patch 4, increment 3:
--   * capture and validate the complete player state;
--   * construct authoritative expected states;
--   * provide verified inventory add/remove primitives;
--   * provide a guarded inventory round-trip diagnostic;
--   * perform no aging transaction or LuaDB writes.

WitheringBrews = WitheringBrews or {}

local WB = WitheringBrews

WB.AgingExecution = WB.AgingExecution or {}

local E = WB.AgingExecution

local function txLog(message)
    System.LogAlways(
        "[WitheringBrews/AgingTx] "
        .. tostring(message)
    )
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPositiveInteger(value)
    return isFiniteNumber(value)
        and value >= 1
        and math.floor(value) == value
end

local function isBootstrapSource(value)
    return type(value) == "string"
        and value:sub(1, 10) == "bootstrap:"
end

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
        if not valuesEqual(
            value,
            right[key]
        ) then
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

local function addExactCohort(
    list,
    incoming
)
    for _, row in ipairs(list) do
        if row.created_at == incoming.created_at
            and row.source == incoming.source
        then
            row.qty = row.qty + incoming.qty

            return "merged"
        end
    end

    table.insert(
        list,
        copyValue(incoming)
    )

    return "appended"
end

local function getInventory(entity)
    if not entity then
        return nil
    end

    if entity.inventory then
        return entity.inventory
    end

    if type(entity.GetInventory) == "function" then
        local ok, inventory =
            pcall(
                entity.GetInventory,
                entity
            )

        if ok then
            return inventory
        end
    end

    return nil
end

local function getInventoryCount(inventory, classId)
    if not inventory then
        return false, nil,
            "inventory unavailable"
    end

    if type(inventory.GetCountOfClass)
        ~= "function"
    then
        return false, nil,
            "GetCountOfClass unavailable"
    end

    local ok, value =
        pcall(
            inventory.GetCountOfClass,
            inventory,
            tostring(classId)
        )

    if not ok then
        return false, nil,
            "GetCountOfClass failed: "
            .. tostring(value)
    end

    value = tonumber(value)

    if not isFiniteNumber(value)
        or value < 0
        or math.floor(value) ~= value
    then
        return false, nil,
            "GetCountOfClass returned invalid count: "
            .. tostring(value)
    end

    return true, value, nil
end

local function inspectCohortList(
    list,
    currentTime
)
    if type(list) ~= "table" then
        return false, 0, 0,
            "cohort value is not a table"
    end

    local rowCount = 0
    local maximumIndex = 0

    for key in pairs(list) do
        if type(key) ~= "number"
            or key < 1
            or math.floor(key) ~= key
        then
            return false, rowCount, 0,
                "cohort list has an invalid array key"
        end

        rowCount = rowCount + 1
        maximumIndex =
            math.max(
                maximumIndex,
                key
            )
    end

    if maximumIndex ~= rowCount then
        return false, rowCount, 0,
            "cohort list is sparse"
    end

    local totalQty = 0

    for index, row in ipairs(list) do
        if type(row) ~= "table" then
            return false, rowCount, totalQty,
                ("row %d is not a table")
                    :format(index)
        end

        local qty = row.qty
        local createdAt = row.created_at
        local source = row.source

        if not isPositiveInteger(qty) then
            return false, rowCount, totalQty,
                ("row %d has invalid qty")
                    :format(index)
        end

        if not isFiniteNumber(createdAt) then
            return false, rowCount, totalQty,
                ("row %d has invalid created_at")
                    :format(index)
        end

        if createdAt < 0
            and not isBootstrapSource(source)
        then
            return false, rowCount, totalQty,
                ("row %d has negative non-bootstrap timestamp")
                    :format(index)
        end

        if createdAt > currentTime then
            return false, rowCount, totalQty,
                ("row %d is dated in the future")
                    :format(index)
        end

        if type(source) ~= "string"
            or source == ""
        then
            return false, rowCount, totalQty,
                ("row %d has invalid source")
                    :format(index)
        end

        totalQty = totalQty + qty
    end

    return true, rowCount, totalQty, nil
end

local function newTransaction()
    return {
        valid = false,
        blockedReasons = {},

        currentTime = nil,

        inventoryBefore = {},
        inventoryExpected = {},

        cohortListsBefore = {},
        cohortListsExpected = {},

        removalsByClassId = {},
        additionsByClassId = {},
        netInventoryDeltaByClassId = {},

        configuredClassIds = {},
        activeClassIds = {},
        affectedClassIds = {},

        rowPlans = {},

        summary = {
            configuredIds = 0,
            activeIds = 0,
            affectedIds = 0,
            sourceRows = 0,
            stableRows = 0,
            downgradeRows = 0,
            terminalRows = 0,
            removals = 0,
            additions = 0,
            cohortWrites = 0,
            inventoryWrites = 0,
        },
    }
end

local function blockTransaction(transaction, reason)
    transaction.blockedReasons[
        #transaction.blockedReasons + 1
    ] = tostring(reason)
end

function E.RemoveVerified(
    inventory,
    classId,
    quantity
)
    local result = {
        operation = "remove",
        classId = classId,
        requested = quantity,

        before = nil,
        after = nil,
        actual = nil,

        engineResult = nil,
        reason = nil,

        inventoryWrites = 0,
    }

    if type(classId) ~= "string"
        or classId == ""
    then
        result.reason =
            "class ID is missing"

        return false, result
    end

    quantity = tonumber(quantity)

    if not isPositiveInteger(quantity) then
        result.reason =
            "quantity must be a positive integer"

        return false, result
    end

    result.requested = quantity

    if not inventory then
        result.reason =
            "inventory unavailable"

        return false, result
    end

    if type(inventory.DeleteItemOfClass)
        ~= "function"
    then
        result.reason =
            "DeleteItemOfClass unavailable"

        return false, result
    end

    local beforeOk,
        before,
        beforeReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not beforeOk then
        result.reason = beforeReason

        return false, result
    end

    result.before = before

    if before < quantity then
        result.after = before
        result.actual = 0

        result.reason =
            ("insufficient quantity: available=%d requested=%d")
                :format(
                    before,
                    quantity
                )

        return false, result
    end

    result.inventoryWrites = 1

    local callOk, engineResult =
        pcall(
            inventory.DeleteItemOfClass,
            inventory,
            tostring(classId),
            quantity
        )

    result.engineResult = engineResult

    local afterOk,
        after,
        afterReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not afterOk then
        result.reason =
            "post-remove count failed: "
            .. tostring(afterReason)

        if not callOk then
            result.reason =
                result.reason
                .. "; engine error: "
                .. tostring(engineResult)
        end

        return false, result
    end

    result.after = after
    result.actual = before - after

    if not callOk then
        result.reason =
            "DeleteItemOfClass failed: "
            .. tostring(engineResult)

        return false, result
    end

    if result.actual ~= quantity then
        result.reason =
            ("remove quantity mismatch: requested=%d actual=%d")
                :format(
                    quantity,
                    result.actual
                )

        return false, result
    end

    return true, result
end

function E.AddVerified(inventory, classId, quantity, health)
    local result = {
        operation = "add",
        classId = classId,
        requested = quantity,

        before = nil,
        after = nil,
        actual = nil,

        health = health,
        engineResult = nil,
        reason = nil,

        inventoryWrites = 0,
    }

    if type(classId) ~= "string"
        or classId == ""
    then
        result.reason =
            "class ID is missing"

        return false, result
    end

    quantity = tonumber(quantity)

    if not isPositiveInteger(quantity) then
        result.reason =
            "quantity must be a positive integer"

        return false, result
    end

    result.requested = quantity

    health = tonumber(health)

    if health == nil then
        health = 1.0
    end

    if not isFiniteNumber(health)
        or health <= 0
    then
        result.reason =
            "health must be a positive number"

        return false, result
    end

    result.health = health

    if not inventory then
        result.reason =
            "inventory unavailable"

        return false, result
    end

    if type(inventory.CreateItem)
        ~= "function"
    then
        result.reason =
            "CreateItem unavailable"

        return false, result
    end

    local beforeOk,
        before,
        beforeReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not beforeOk then
        result.reason = beforeReason

        return false, result
    end

    result.before = before
    result.inventoryWrites = 1

    local callOk, engineResult =
        pcall(
            inventory.CreateItem,
            inventory,
            tostring(classId),
            health,
            quantity
        )

    result.engineResult = engineResult

    local afterOk,
        after,
        afterReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not afterOk then
        result.reason =
            "post-add count failed: "
            .. tostring(afterReason)

        if not callOk then
            result.reason =
                result.reason
                .. "; engine error: "
                .. tostring(engineResult)
        end

        return false, result
    end

    result.after = after
    result.actual = after - before

    if not callOk then
        result.reason =
            "CreateItem failed: "
            .. tostring(engineResult)

        return false, result
    end

    if result.actual ~= quantity then
        result.reason =
            ("add quantity mismatch: requested=%d actual=%d")
                :format(
                    quantity,
                    result.actual
                )

        return false, result
    end

    return true, result
end

function E.WriteCohortListVerified(classId, expectedList)
    local result = {
        operation = "cohort-write",
        classId = classId,

        expectedRows = nil,
        expectedQty = nil,

        beforeList = nil,
        afterList = nil,

        reason = nil,
        cohortWrites = 0,
    }

    if type(classId) ~= "string"
        or classId == ""
    then
        result.reason =
            "class ID is missing"

        return false, result
    end

    if type(expectedList) ~= "table" then
        result.reason =
            "expected cohort list is not a table"

        return false, result
    end

    if type(WB.CohortsGet) ~= "function"
        or type(WB.CohortsSet) ~= "function"
    then
        result.reason =
            "cohort storage unavailable"

        return false, result
    end

    local currentTime =
        WB.Clock
        and type(WB.Clock.Now) == "function"
        and WB.Clock.Now()
        or nil

    if not isFiniteNumber(currentTime) then
        result.reason =
            "world clock unavailable"

        return false, result
    end

    local validExpected,
        expectedRows,
        expectedQty,
        expectedReason =
        inspectCohortList(
            expectedList,
            currentTime
        )

    if not validExpected then
        result.reason =
            "expected cohort list is invalid: "
            .. tostring(expectedReason)

        return false, result
    end

    result.expectedRows = expectedRows
    result.expectedQty = expectedQty

    local beforeOk, beforeList =
        pcall(
            WB.CohortsGet,
            classId
        )

    if not beforeOk then
        result.reason =
            "cohort read before write failed: "
            .. tostring(beforeList)

        return false, result
    end

    if type(beforeList) ~= "table" then
        result.reason =
            "stored cohort value before write is not a table"

        return false, result
    end

    result.beforeList =
        copyValue(beforeList)

    result.cohortWrites = 1

    local writeOk, writeError =
        pcall(
            WB.CohortsSet,
            classId,
            copyValue(expectedList)
        )

    local readOk, afterList =
        pcall(
            WB.CohortsGet,
            classId
        )

    if not readOk then
        result.reason =
            "cohort read-back failed: "
            .. tostring(afterList)

        if not writeOk then
            result.reason =
                result.reason
                .. "; write error: "
                .. tostring(writeError)
        end

        return false, result
    end

    result.afterList =
        copyValue(afterList)

    if not writeOk then
        result.reason =
            "cohort write failed: "
            .. tostring(writeError)

        return false, result
    end

    if not valuesEqual(
        afterList,
        expectedList
    ) then
        result.reason =
            "cohort read-back differs from expected list"

        return false, result
    end

    return true, result
end

local function logCohortWriteResult(
    label,
    success,
    result
)
    txLog(
        ("%s success=%s id=%s expectedRows=%s expectedQty=%s writes=%d reason=%s")
            :format(
                tostring(label),
                tostring(success),
                tostring(result.classId),
                tostring(result.expectedRows),
                tostring(result.expectedQty),
                tonumber(
                    result.cohortWrites
                ) or 0,
                tostring(result.reason)
            )
    )
end

function E.TestCohortRoundTrip(classId, confirmation)
    if confirmation ~= "TEST" then
        txLog(
            "Cohort round-trip aborted: explicit TEST confirmation required"
        )

        return false
    end

    if not (
        WB.Config
        and WB.Config.DryRun == false
    ) then
        txLog(
            "Cohort round-trip aborted: DryRun must be false"
        )

        return false
    end

    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local potion =
        type(WB.GetTrackedPotion) == "function"
        and WB.GetTrackedPotion(classId)
        or nil

    if not potion then
        txLog(
            "Cohort round-trip aborted: class ID is not a tracked potion"
        )

        return false
    end

    local readOk, originalList =
        pcall(
            WB.CohortsGet,
            classId
        )

    if not readOk then
        txLog(
            "Cohort round-trip aborted: initial read failed: "
            .. tostring(originalList)
        )

        return false
    end

    if type(originalList) ~= "table" then
        txLog(
            "Cohort round-trip aborted: stored value is not a table"
        )

        return false
    end

    originalList =
        copyValue(originalList)

    txLog(
        ("Cohort round-trip BEGIN family=%s tier=%s id=%s rows=%d")
            :format(
                tostring(potion.family),
                tostring(
                    potion.label
                    or potion.tier
                    or "?"
                ),
                tostring(classId),
                #originalList
            )
    )

    local writeOk, writeResult =
        E.WriteCohortListVerified(
            classId,
            originalList
        )

    logCohortWriteResult(
        "COHORT WRITE",
        writeOk,
        writeResult
    )

    if not writeOk then
        local compensationOk,
            compensationResult =
            E.WriteCohortListVerified(
                classId,
                originalList
            )

        logCohortWriteResult(
            "COHORT COMPENSATE",
            compensationOk,
            compensationResult
        )

        if not compensationOk then
            txLog(
                "CRITICAL: cohort round-trip compensation failed"
            )
        end

        return false
    end

    local finalReadOk, finalList =
        pcall(
            WB.CohortsGet,
            classId
        )

    if not finalReadOk
        or not valuesEqual(
            finalList,
            originalList
        )
    then
        local compensationOk,
            compensationResult =
            E.WriteCohortListVerified(
                classId,
                originalList
            )

        logCohortWriteResult(
            "COHORT COMPENSATE",
            compensationOk,
            compensationResult
        )

        if not compensationOk then
            txLog(
                "CRITICAL: cohort round-trip compensation failed"
            )
        end

        txLog(
            "Cohort round-trip FAILED final verification"
        )

        return false
    end

    txLog(
        ("Cohort round-trip OK id=%s rows=%d cohortWrites=1 inventoryWrites=0")
            :format(
                tostring(classId),
                #originalList
            )
    )

    return true
end

local function logMutationResult(
    label,
    success,
    result
)
    txLog(
        ("%s success=%s id=%s requested=%s before=%s after=%s actual=%s writes=%d engineResult=%s reason=%s")
            :format(
                tostring(label),
                tostring(success),
                tostring(result.classId),
                tostring(result.requested),
                tostring(result.before),
                tostring(result.after),
                tostring(result.actual),
                tonumber(
                    result.inventoryWrites
                ) or 0,
                tostring(result.engineResult),
                tostring(result.reason)
            )
    )
end

local function restoreClassCount(
    inventory,
    classId,
    targetCount
)
    local countOk,
        currentCount,
        countReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not countOk then
        return false, nil, countReason
    end

    if currentCount == targetCount then
        return true, nil, nil
    end

    local mutationOk
    local mutationResult

    if currentCount < targetCount then
        mutationOk, mutationResult =
            E.AddVerified(
                inventory,
                classId,
                targetCount - currentCount,
                1.0
            )
    else
        mutationOk, mutationResult =
            E.RemoveVerified(
                inventory,
                classId,
                currentCount - targetCount
            )
    end

    local finalOk,
        finalCount,
        finalReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not finalOk then
        return false,
            mutationResult,
            finalReason
    end

    if finalCount ~= targetCount then
        return false,
            mutationResult,
            ("compensation mismatch: target=%d final=%d helperSuccess=%s")
                :format(
                    targetCount,
                    finalCount,
                    tostring(mutationOk)
                )
    end

    return true, mutationResult, nil
end

function E.TestInventoryRoundTrip(classId, quantity, confirmation)
    if confirmation ~= "TEST" then
        txLog(
            "Inventory round-trip aborted: explicit TEST confirmation required"
        )

        return false
    end

    if not (
        WB.Config
        and WB.Config.DryRun == false
    ) then
        txLog(
            "Inventory round-trip aborted: DryRun must be false"
        )

        return false
    end

    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local potion =
        type(WB.GetTrackedPotion) == "function"
        and WB.GetTrackedPotion(classId)
        or nil

    if not potion then
        txLog(
            "Inventory round-trip aborted: class ID is not a tracked potion"
        )

        return false
    end

    quantity = tonumber(quantity)

    if not isPositiveInteger(quantity) then
        txLog(
            "Inventory round-trip aborted: quantity must be a positive integer"
        )

        return false
    end

    local U = WB.Util

    local playerEntity =
        U
        and type(U.Player) == "function"
        and U.Player()
        or nil

    local inventory =
        getInventory(playerEntity)

    if not inventory then
        txLog(
            "Inventory round-trip aborted: player inventory unavailable"
        )

        return false
    end

    local initialOk,
        initialCount,
        initialReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not initialOk then
        txLog(
            "Inventory round-trip aborted: "
            .. tostring(initialReason)
        )

        return false
    end

    txLog(
        ("Inventory round-trip BEGIN family=%s tier=%s id=%s quantity=%d initial=%d")
            :format(
                tostring(potion.family),
                tostring(
                    potion.label
                    or potion.tier
                    or "?"
                ),
                tostring(classId),
                quantity,
                initialCount
            )
    )

    local removeOk, removeResult =
        E.RemoveVerified(
            inventory,
            classId,
            quantity
        )

    logMutationResult(
        "REMOVE",
        removeOk,
        removeResult
    )

    if not removeOk then
        local restored,
            compensationResult,
            compensationReason =
            restoreClassCount(
                inventory,
                classId,
                initialCount
            )

        if compensationResult then
            logMutationResult(
                "COMPENSATE",
                restored,
                compensationResult
            )
        end

        txLog(
            ("Inventory round-trip FAILED during remove compensation=%s reason=%s")
                :format(
                    tostring(restored),
                    tostring(
                        compensationReason
                        or removeResult.reason
                    )
                )
        )

        return false
    end

    local addOk, addResult =
        E.AddVerified(
            inventory,
            classId,
            quantity,
            1.0
        )

    logMutationResult(
        "ADD",
        addOk,
        addResult
    )

    if not addOk then
        local restored,
            compensationResult,
            compensationReason =
            restoreClassCount(
                inventory,
                classId,
                initialCount
            )

        if compensationResult then
            logMutationResult(
                "COMPENSATE",
                restored,
                compensationResult
            )
        end

        txLog(
            ("Inventory round-trip FAILED during add compensation=%s reason=%s")
                :format(
                    tostring(restored),
                    tostring(
                        compensationReason
                        or addResult.reason
                    )
                )
        )

        return false
    end

    local finalOk,
        finalCount,
        finalReason =
        getInventoryCount(
            inventory,
            classId
        )

    if not finalOk
        or finalCount ~= initialCount
    then
        local restored,
            compensationResult,
            compensationReason =
            restoreClassCount(
                inventory,
                classId,
                initialCount
            )

        if compensationResult then
            logMutationResult(
                "COMPENSATE",
                restored,
                compensationResult
            )
        end

        txLog(
            ("Inventory round-trip FAILED final verification initial=%d final=%s compensation=%s reason=%s")
                :format(
                    initialCount,
                    tostring(finalCount),
                    tostring(restored),
                    tostring(
                        compensationReason
                        or finalReason
                    )
                )
        )

        return false
    end

    txLog(
        ("Inventory round-trip OK id=%s initial=%d final=%d inventoryWrites=2 cohortWrites=0")
            :format(
                tostring(classId),
                initialCount,
                finalCount
            )
    )

    return true
end

function E.RecheckPreconditions(transaction)
    local result = {
        valid = false,
        reasons = {},

        checkedIds = 0,
        inventoryChecks = 0,
        cohortChecks = 0,

        currentTime = nil,
        writes = 0,
    }

    local function block(reason)
        result.reasons[
            #result.reasons + 1
        ] = tostring(reason)
    end

    if type(transaction) ~= "table" then
        block(
            "transaction is not a table"
        )

        return false, result
    end

    if transaction.valid ~= true then
        block(
            "transaction is not valid"
        )

        return false, result
    end

    if type(transaction.configuredClassIds)
        ~= "table"
    then
        block(
            "configured class IDs unavailable"
        )

        return false, result
    end

    local U = WB.Util

    local playerEntity =
        U
        and type(U.Player) == "function"
        and U.Player()
        or nil

    local inventory =
        getInventory(playerEntity)

    if not inventory then
        block(
            "player inventory unavailable"
        )

        return false, result
    end

    local currentTime =
        WB.Clock
        and type(WB.Clock.Now) == "function"
        and WB.Clock.Now()
        or nil

    if not isFiniteNumber(currentTime) then
        block(
            "world clock unavailable"
        )

        return false, result
    end

    result.currentTime = currentTime

    if not isFiniteNumber(
        transaction.currentTime
    ) then
        block(
            "transaction time is invalid"
        )
    elseif currentTime
        < transaction.currentTime
    then
        block(
            ("world clock moved backward: planned=%s live=%s")
                :format(
                    tostring(
                        transaction.currentTime
                    ),
                    tostring(currentTime)
                )
        )
    end

    for _, classId in ipairs(
        transaction.configuredClassIds
    ) do
        result.checkedIds =
            result.checkedIds + 1

        local countOk,
            liveCount,
            countReason =
            getInventoryCount(
                inventory,
                classId
            )

        if not countOk then
            block(
                ("id=%s inventory recheck failed: %s")
                    :format(
                        tostring(classId),
                        tostring(countReason)
                    )
            )
        else
            result.inventoryChecks =
                result.inventoryChecks + 1

            local plannedCount =
                transaction.inventoryBefore[
                    classId
                ]

            if liveCount ~= plannedCount then
                block(
                    ("id=%s inventory changed: planned=%s live=%s")
                        :format(
                            tostring(classId),
                            tostring(plannedCount),
                            tostring(liveCount)
                        )
                )
            end
        end

        local readOk, liveList =
            pcall(
                WB.CohortsGet,
                classId
            )

        if not readOk then
            block(
                ("id=%s cohort recheck failed: %s")
                    :format(
                        tostring(classId),
                        tostring(liveList)
                    )
            )
        else
            result.cohortChecks =
                result.cohortChecks + 1

            local plannedList =
                transaction.cohortListsBefore[
                    classId
                ]

            if not valuesEqual(
                liveList,
                plannedList
            ) then
                block(
                    ("id=%s cohort list changed after planning")
                        :format(
                            tostring(classId)
                        )
                )
            end
        end
    end

    if #result.reasons == 0 then
        result.valid = true
    end

    return result.valid, result
end

function E.BuildPlayerTransaction()
    local transaction = newTransaction()

    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local U = WB.Util

    if not (
        U
        and type(U.Player) == "function"
        and type(U.InventorySnapshot) == "function"
    ) then
        blockTransaction(
            transaction,
            "inventory utilities unavailable"
        )

        return transaction
    end

    if type(WB.CohortsGet) ~= "function" then
        blockTransaction(
            transaction,
            "cohort storage unavailable"
        )

        return transaction
    end

    local playerEntity = U.Player()

    if not playerEntity then
        blockTransaction(
            transaction,
            "player unavailable"
        )

        return transaction
    end

    local inventory = getInventory(playerEntity)

    if not inventory then
        blockTransaction(
            transaction,
            "player inventory unavailable"
        )

        return transaction
    end

    -- Transaction verification requires authoritative class counts.
    if type(inventory.GetCountOfClass) ~= "function" then
        blockTransaction(
            transaction,
            "inventory.GetCountOfClass unavailable"
        )

        return transaction
    end

    if type(inventory.GetInventoryTable) ~= "function" then
        blockTransaction(
            transaction,
            "inventory.GetInventoryTable unavailable"
        )

        return transaction
    end

    local currentTime =
        WB.Clock
        and type(WB.Clock.Now) == "function"
        and WB.Clock.Now()
        or nil

    if not isFiniteNumber(currentTime) then
        blockTransaction(
            transaction,
            "world clock unavailable"
        )

        return transaction
    end

    transaction.currentTime = currentTime

    local snapshot =
        U.InventorySnapshot(playerEntity)

    if type(snapshot) ~= "table" then
        blockTransaction(
            transaction,
            "inventory snapshot failed"
        )

        return transaction
    end

    for classId in pairs(WB._PotionIndex or {}) do
        transaction.configuredClassIds[
            #transaction.configuredClassIds + 1
        ] = classId
    end

    table.sort(
        transaction.configuredClassIds
    )

    transaction.summary.configuredIds =
        #transaction.configuredClassIds

    for _, classId in ipairs(
        transaction.configuredClassIds
    ) do
        local inventoryQty =
            math.max(
                0,
                math.floor(
                    tonumber(snapshot[classId])
                    or 0
                )
            )

        transaction.inventoryBefore[classId] =
            inventoryQty

        -- Increment 1 expects no state changes.
        transaction.inventoryExpected[classId] =
            inventoryQty

        local readOk, cohortList =
            pcall(
                WB.CohortsGet,
                classId
            )

        if not readOk then
            local readError = cohortList

            cohortList = {}

            blockTransaction(
                transaction,
                ("id=%s cohort read failed: %s")
                    :format(
                        tostring(classId),
                        tostring(readError)
                    )
            )
        end

        transaction.cohortListsBefore[classId] =
            copyValue(cohortList)

        -- Increment 2 reconstructs the complete final lists
        -- from original cohort contributions.
        transaction.cohortListsExpected[classId] = {}

        local validList,
            rowCount,
            cohortQty,
            validationReason =
            inspectCohortList(
                cohortList,
                currentTime
            )

        local hasStoredCohorts =
            type(cohortList) == "table"
            and next(cohortList) ~= nil

        local active =
            inventoryQty > 0
            or hasStoredCohorts

        if active then
            transaction.activeClassIds[
                #transaction.activeClassIds + 1
            ] = classId

            transaction.summary.activeIds =
                transaction.summary.activeIds + 1
        end

        transaction.summary.sourceRows =
            transaction.summary.sourceRows
            + rowCount

        if not validList then
            blockTransaction(
                transaction,
                ("id=%s invalid cohort list: %s")
                    :format(
                        tostring(classId),
                        tostring(validationReason)
                    )
            )
        elseif cohortQty ~= inventoryQty then
            blockTransaction(
                transaction,
                ("id=%s inventory/cohort mismatch: inventory=%d cohorts=%d")
                    :format(
                        tostring(classId),
                        inventoryQty,
                        cohortQty
                    )
            )
        elseif active then
            local potion =
                type(WB.GetTrackedPotion) == "function"
                and WB.GetTrackedPotion(classId)
                or nil

            txLog(
                ("ACTIVE family=%s tier=%s id=%s inventory=%d cohorts=%d rows=%d")
                    :format(
                        tostring(
                            potion
                            and potion.family
                            or "?"
                        ),
                        tostring(
                            potion
                            and (
                                potion.label
                                or potion.tier
                            )
                            or "?"
                        ),
                        tostring(classId),
                        inventoryQty,
                        cohortQty,
                        rowCount
                    )
            )
        end
    end

    -- Do not plan against unreconciled or invalid source state.
    if #transaction.blockedReasons > 0 then
        return transaction
    end

    local A = WB.Aging

    if not (
        A
        and type(A.ResolveRules) == "function"
        and type(A.PlanCohort) == "function"
    ) then
        blockTransaction(
            transaction,
            "aging planner unavailable"
        )

        return transaction
    end

    local configuredSet = {}

    for _, classId in ipairs(
        transaction.configuredClassIds
    ) do
        configuredSet[classId] = true
    end

    -- Every original row produces exactly one emission.
    -- Unchanged emissions are copied first. Transformed
    -- emissions are added afterward with exact compaction.
    local unchangedEmissions = {}
    local transformedEmissions = {}

    for _, sourceClassId in ipairs(
        transaction.activeClassIds
    ) do
        local potion =
            type(WB.GetTrackedPotion) == "function"
            and WB.GetTrackedPotion(sourceClassId)
            or nil

        local familyData =
            potion
            and WB.Config
            and WB.Config.PotionFamilies
            and WB.Config.PotionFamilies[
                potion.family
            ]
            or nil

        if not potion then
            blockTransaction(
                transaction,
                ("id=%s tracked potion data unavailable")
                    :format(
                        tostring(sourceClassId)
                    )
            )
        elseif not familyData then
            blockTransaction(
                transaction,
                ("id=%s family data unavailable")
                    :format(
                        tostring(sourceClassId)
                    )
            )
        else
            local rulesOk, rulesOrReason =
                A.ResolveRules(
                    familyData,
                    {
                        durationMultiplier = 1,
                    }
                )

            if not rulesOk then
                blockTransaction(
                    transaction,
                    ("id=%s rules unavailable: %s")
                        :format(
                            tostring(sourceClassId),
                            tostring(rulesOrReason)
                        )
                )
            else
                local sourceList =
                    transaction.cohortListsBefore[
                        sourceClassId
                    ]

                for rowIndex, sourceRow in ipairs(
                    sourceList
                ) do
                    local plan =
                        A.PlanCohort(
                            potion.family,
                            familyData,
                            potion.tier,
                            sourceRow,
                            currentTime,
                            rulesOrReason
                        )

                    transaction.rowPlans[
                        #transaction.rowPlans + 1
                    ] = {
                        sourceClassId =
                            sourceClassId,

                        sourceRowIndex =
                            rowIndex,

                        plan =
                            copyValue(plan),
                    }

                    local planValid = true

                    local function blockPlan(reason)
                        planValid = false

                        blockTransaction(
                            transaction,
                            ("id=%s row=%d: %s")
                                :format(
                                    tostring(
                                        sourceClassId
                                    ),
                                    rowIndex,
                                    tostring(reason)
                                )
                        )
                    end

                    if type(plan) ~= "table" then
                        blockPlan(
                            "planner result is not a table"
                        )
                    elseif plan.status == "blocked" then
                        blockPlan(
                            "planner blocked: "
                            .. tostring(plan.reason)
                        )
                    else
                        if not isPositiveInteger(
                            plan.qty
                        ) then
                            blockPlan(
                                "planned qty is invalid"
                            )
                        elseif plan.qty
                            ~= sourceRow.qty
                        then
                            blockPlan(
                                ("planned qty changed: source=%d planned=%s")
                                    :format(
                                        sourceRow.qty,
                                        tostring(
                                            plan.qty
                                        )
                                    )
                            )
                        end

                        if plan.sourceClassId
                            ~= sourceClassId
                        then
                            blockPlan(
                                "planned source class ID does not match source list"
                            )
                        elseif not configuredSet[
                            plan.sourceClassId
                        ] then
                            blockPlan(
                                "planned source class ID is not configured"
                            )
                        end

                        if type(plan.targetClassId)
                            ~= "string"
                            or plan.targetClassId == ""
                        then
                            blockPlan(
                                "planned target class ID is missing"
                            )
                        elseif not configuredSet[
                            plan.targetClassId
                        ] then
                            blockPlan(
                                "planned target class ID is not configured"
                            )
                        else
                            local targetPotion =
                                type(
                                    WB.GetTrackedPotion
                                ) == "function"
                                and WB.GetTrackedPotion(
                                    plan.targetClassId
                                )
                                or nil

                            if not targetPotion then
                                blockPlan(
                                    "planned target potion data is unavailable"
                                )
                            elseif targetPotion.family
                                ~= potion.family
                            then
                                blockPlan(
                                    ("planned target belongs to another family: source=%s target=%s")
                                        :format(
                                            tostring(
                                                potion.family
                                            ),
                                            tostring(
                                                targetPotion.family
                                            )
                                        )
                                )
                            end
                        end

                        if not isFiniteNumber(
                            plan.targetCreatedAt
                        ) then
                            blockPlan(
                                "planned targetCreatedAt is invalid"
                            )
                        elseif plan.targetCreatedAt
                            > currentTime
                        then
                            blockPlan(
                                "planned targetCreatedAt is in the future"
                            )
                        end

                        if plan.originalSource
                            ~= sourceRow.source
                        then
                            blockPlan(
                                "planned source metadata changed"
                            )
                        end

                        if plan.family
                            ~= potion.family
                        then
                            blockPlan(
                                "planned family does not match source family"
                            )
                        end
                    end

                    if planValid then
                        if plan.status == "stable" then
                            if plan.requiresReplacement then
                                blockPlan(
                                    "stable plan unexpectedly requires replacement"
                                )
                            elseif plan.targetClassId
                                ~= sourceClassId
                            then
                                blockPlan(
                                    "stable plan changed class ID"
                                )
                            else
                                transaction.summary.stableRows =
                                    transaction.summary.stableRows
                                    + 1

                                unchangedEmissions[
                                    #unchangedEmissions + 1
                                ] = {
                                    targetClassId =
                                        sourceClassId,

                                    row =
                                        copyValue(
                                            sourceRow
                                        ),
                                }
                            end
                        elseif plan.status
                            == "downgrade"
                        then
                            if not plan.requiresReplacement then
                                blockPlan(
                                    "downgrade plan does not require replacement"
                                )
                            elseif plan.targetClassId
                                == sourceClassId
                            then
                                blockPlan(
                                    "downgrade plan retained source class ID"
                                )
                            else
                                transaction.summary.downgradeRows =
                                    transaction.summary.downgradeRows
                                    + 1

                                transaction.removalsByClassId[
                                    sourceClassId
                                ] =
                                    (
                                        transaction.removalsByClassId[
                                            sourceClassId
                                        ]
                                        or 0
                                    )
                                    + plan.qty

                                transaction.additionsByClassId[
                                    plan.targetClassId
                                ] =
                                    (
                                        transaction.additionsByClassId[
                                            plan.targetClassId
                                        ]
                                        or 0
                                    )
                                    + plan.qty

                                transformedEmissions[
                                    #transformedEmissions + 1
                                ] = {
                                    targetClassId =
                                        plan.targetClassId,

                                    row = {
                                        qty = plan.qty,
                                        created_at =
                                            plan.targetCreatedAt,
                                        source =
                                            plan.originalSource,
                                    },
                                }
                            end
                        elseif plan.status
                            == "terminal"
                        then
                            transaction.summary.terminalRows =
                                transaction.summary.terminalRows
                                + 1

                            if plan.requiresReplacement then
                                if plan.sourceTier <= 1 then
                                    blockPlan(
                                        "terminal Quality I unexpectedly requires replacement"
                                    )
                                elseif plan.targetTier
                                    ~= 1
                                then
                                    blockPlan(
                                        "terminal replacement does not target Quality I"
                                    )
                                elseif plan.targetClassId
                                    == sourceClassId
                                then
                                    blockPlan(
                                        "terminal replacement retained source class ID"
                                    )
                                else
                                    transaction.removalsByClassId[
                                        sourceClassId
                                    ] =
                                        (
                                            transaction.removalsByClassId[
                                                sourceClassId
                                            ]
                                            or 0
                                        )
                                        + plan.qty

                                    transaction.additionsByClassId[
                                        plan.targetClassId
                                    ] =
                                        (
                                            transaction.additionsByClassId[
                                                plan.targetClassId
                                            ]
                                            or 0
                                        )
                                        + plan.qty

                                    transformedEmissions[
                                        #transformedEmissions + 1
                                    ] = {
                                        targetClassId =
                                            plan.targetClassId,

                                        row = {
                                            qty = plan.qty,
                                            created_at =
                                                plan.targetCreatedAt,
                                            source =
                                                plan.originalSource,
                                        },
                                    }
                                end
                            else
                                if plan.sourceTier ~= 1
                                    or plan.targetTier ~= 1
                                    or plan.targetClassId
                                        ~= sourceClassId
                                then
                                    blockPlan(
                                        "terminal keep plan is not a Quality I no-op"
                                    )
                                else
                                    -- Terminal Quality I with keep policy:
                                    -- preserve the original row exactly.
                                    unchangedEmissions[
                                        #unchangedEmissions + 1
                                    ] = {
                                        targetClassId =
                                            sourceClassId,

                                        row =
                                            copyValue(
                                                sourceRow
                                            ),
                                    }
                                end
                            end
                        else
                            blockPlan(
                                "unsupported planner status: "
                                .. tostring(
                                    plan.status
                                )
                            )
                        end
                    end
                end
            end
        end
    end

    if #transaction.blockedReasons > 0 then
        return transaction
    end

    -- Pass 1: preserve unchanged rows without compacting them.
    for _, emission in ipairs(
        unchangedEmissions
    ) do
        table.insert(
            transaction.cohortListsExpected[
                emission.targetClassId
            ],
            copyValue(emission.row)
        )
    end

    -- Pass 2: add transformed rows and compact only exact
    -- target timestamp/source matches.
    for _, emission in ipairs(
        transformedEmissions
    ) do
        addExactCohort(
            transaction.cohortListsExpected[
                emission.targetClassId
            ],
            emission.row
        )
    end

    local totalBefore = 0
    local totalRemovals = 0
    local totalAdditions = 0
    local totalExpected = 0

    for _, classId in ipairs(
        transaction.configuredClassIds
    ) do
        local beforeQty =
            transaction.inventoryBefore[
                classId
            ]
            or 0

        local removalQty =
            transaction.removalsByClassId[
                classId
            ]
            or 0

        local additionQty =
            transaction.additionsByClassId[
                classId
            ]
            or 0

        local netDelta =
            additionQty - removalQty

        local expectedQty =
            beforeQty + netDelta

        transaction.netInventoryDeltaByClassId[
            classId
        ] = netDelta

        transaction.inventoryExpected[
            classId
        ] = expectedQty

        totalBefore =
            totalBefore + beforeQty

        totalRemovals =
            totalRemovals + removalQty

        totalAdditions =
            totalAdditions + additionQty

        totalExpected =
            totalExpected + expectedQty

        if expectedQty < 0 then
            blockTransaction(
                transaction,
                ("id=%s expected inventory is negative: %d")
                    :format(
                        tostring(classId),
                        expectedQty
                    )
            )
        end

        local validExpected,
            expectedRows,
            expectedCohortQty,
            expectedReason =
            inspectCohortList(
                transaction.cohortListsExpected[
                    classId
                ],
                currentTime
            )

        if not validExpected then
            blockTransaction(
                transaction,
                ("id=%s expected cohort list is invalid: %s")
                    :format(
                        tostring(classId),
                        tostring(expectedReason)
                    )
            )
        elseif expectedCohortQty
            ~= expectedQty
        then
            blockTransaction(
                transaction,
                ("id=%s expected inventory/cohort mismatch: inventory=%d cohorts=%d")
                    :format(
                        tostring(classId),
                        expectedQty,
                        expectedCohortQty
                    )
            )
        end

        local cohortChanged =
            not valuesEqual(
                transaction.cohortListsBefore[
                    classId
                ],
                transaction.cohortListsExpected[
                    classId
                ]
            )

        local inventoryChanged =
            expectedQty ~= beforeQty

        if cohortChanged
            or inventoryChanged
        then
            transaction.affectedClassIds[
                #transaction.affectedClassIds + 1
            ] = classId
        end
    end

    transaction.summary.removals =
        totalRemovals

    transaction.summary.additions =
        totalAdditions

    transaction.summary.affectedIds =
        #transaction.affectedClassIds

    if totalBefore
        - totalRemovals
        + totalAdditions
        ~= totalExpected
    then
        blockTransaction(
            transaction,
            ("global inventory invariant failed: before=%d removals=%d additions=%d expected=%d")
                :format(
                    totalBefore,
                    totalRemovals,
                    totalAdditions,
                    totalExpected
                )
        )
    end

    if totalRemovals ~= totalAdditions then
        blockTransaction(
            transaction,
            ("replacement quantity invariant failed: removals=%d additions=%d")
                :format(
                    totalRemovals,
                    totalAdditions
                )
        )
    end

    if #transaction.blockedReasons == 0 then
        transaction.valid = true
    end

    return transaction
end

function E.PreviewPlayerTransaction()
    local transaction =
        E.BuildPlayerTransaction()

        if transaction.valid then
            local precheckOk, precheck =
                E.RecheckPreconditions(
                    transaction
                )

            txLog(
                ("Precondition recheck: valid=%s checkedIds=%d inventoryChecks=%d cohortChecks=%d writes=%d")
                    :format(
                        tostring(precheckOk),
                        precheck.checkedIds,
                        precheck.inventoryChecks,
                        precheck.cohortChecks,
                        precheck.writes
                    )
            )

            if not precheckOk then
                transaction.valid = false

                for _, reason in ipairs(
                    precheck.reasons
                ) do
                    blockTransaction(
                        transaction,
                        "precondition recheck: "
                        .. tostring(reason)
                    )
                end
            end
        end

    for _, rowPlan in ipairs(
    transaction.rowPlans
    ) do
        local plan = rowPlan.plan

        txLog(
            ("ROW sourceId=%s row=%d status=%s qty=%s sourceTier=%s targetTier=%s targetId=%s targetCreatedAt=%s replacement=%s")
                :format(
                    tostring(
                        rowPlan.sourceClassId
                    ),
                    tonumber(
                        rowPlan.sourceRowIndex
                    ) or 0,
                    tostring(
                        plan
                        and plan.status
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.qty
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.sourceTier
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.targetTier
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.targetClassId
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.targetCreatedAt
                        or "?"
                    ),
                    tostring(
                        plan
                        and plan.requiresReplacement
                        or false
                    )
                )
        )
    end

    for _, classId in ipairs(
        transaction.affectedClassIds
    ) do
        txLog(
            ("AFFECTED id=%s inventory=%d->%d remove=%d add=%d net=%d cohorts=%d->%d")
                :format(
                    tostring(classId),

                    transaction.inventoryBefore[
                        classId
                    ] or 0,

                    transaction.inventoryExpected[
                        classId
                    ] or 0,

                    transaction.removalsByClassId[
                        classId
                    ] or 0,

                    transaction.additionsByClassId[
                        classId
                    ] or 0,

                    transaction.netInventoryDeltaByClassId[
                        classId
                    ] or 0,

                    #(
                        transaction.cohortListsBefore[
                            classId
                        ] or {}
                    ),

                    #(
                        transaction.cohortListsExpected[
                            classId
                        ] or {}
                    )
                )
        )
    end    

    for _, reason in ipairs(
        transaction.blockedReasons
    ) do
        txLog(
            "BLOCKED " .. tostring(reason)
        )
    end

    local summary = transaction.summary

    txLog(
        ("Preview summary: valid=%s configuredIds=%d activeIds=%d affectedIds=%d sourceRows=%d stableRows=%d downgradeRows=%d terminalRows=%d removals=%d additions=%d cohortWrites=%d inventoryWrites=%d")
            :format(
                tostring(transaction.valid),
                summary.configuredIds,
                summary.activeIds,
                summary.affectedIds,
                summary.sourceRows,
                summary.stableRows,
                summary.downgradeRows,
                summary.terminalRows,
                summary.removals,
                summary.additions,
                summary.cohortWrites,
                summary.inventoryWrites
            )
    )

    return transaction.valid, transaction
end