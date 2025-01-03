-- Function to recursively build a raw materials list using WoW API
local function calculateRawMaterials(itemName, tradeSkillRecipeId)
    local rawMaterials = {}
    local ownedItems = {}
    local processedItems = {}
    local debug = false

    local function debugPrint(...)
        if debug then
            print(...)
        end
    end

    local function addMaterial(name, quantity, parentItem, craftedParent)
        if not rawMaterials[name] then
            rawMaterials[name] = {
                quantity = quantity,
                parents = {},
                craftedParents = {},
                ownedThroughParent = false,
                processed = false
            }
        else
            rawMaterials[name].quantity = rawMaterials[name].quantity + quantity
        end
        if parentItem then
            table.insert(rawMaterials[name].parents, parentItem)
            if craftedParent then
                rawMaterials[name].craftedParents[parentItem] = true
            end
        end
    end

    local function findRecipeIdByName(targetName)
        local numTradeSkills = GetNumTradeSkills()
        for index = 1, numTradeSkills do
            local skillName = GetTradeSkillInfo(index)
            if skillName == targetName then
                return index
            end
        end
        return nil
    end

    local function isItemOwned(checkItemName)
        -- Never consider the final item as owned since we're trying to craft it
        if checkItemName == itemName then
            return false
        end
        
        -- Check direct ownership
        if ownedItems[checkItemName] then
            debugPrint(checkItemName .. " is directly owned")
            return true
        end
        
        -- Check ownership through crafted parents
        if rawMaterials[checkItemName] and rawMaterials[checkItemName].parents then
            for _, parentItem in ipairs(rawMaterials[checkItemName].parents) do
                -- Skip ownership check through the final item
                if parentItem ~= itemName and ownedItems[parentItem] and rawMaterials[checkItemName].craftedParents[parentItem] then
                    debugPrint(checkItemName .. " is owned through crafted parent " .. parentItem)
                    return true
                end
            end
        end
        
        return false
    end

    local function markMaterialsAsOwned(craftedItem)
        -- Don't mark materials as owned if they're part of the final item
        if craftedItem == itemName then
            return
        end
        
        for material, data in pairs(rawMaterials) do
            if data.parents then
                for _, parent in ipairs(data.parents) do
                    if parent == craftedItem then
                        debugPrint("Marking " .. material .. " as owned through " .. craftedItem)
                        data.ownedThroughParent = true
                        markMaterialsAsOwned(material)
                    end
                end
            end
        end
    end

    local function processItem(recipeId, quantity, parentItem, depth)
        depth = depth or 0
        if not quantity or not recipeId or recipeId <= 0 then return end
        
        local numReagents = GetTradeSkillNumReagents(recipeId)
        if not numReagents or numReagents <= 0 then return end

        local minMade, maxMade = GetTradeSkillNumMade(recipeId)
        minMade = minMade or 1
        local adjustedQuantity = math.ceil(quantity / minMade)

        local itemLink = GetTradeSkillItemLink(recipeId)
        local currentItemName = GetItemInfo(itemLink)
        
        if processedItems[currentItemName] then
            return
        end
        processedItems[currentItemName] = true

        local isCraftable = findRecipeIdByName(currentItemName) ~= nil
        local isOwned = isItemOwned(currentItemName)
        
        debugPrint(string.rep("  ", depth) .. "Processing " .. currentItemName)
        debugPrint(string.rep("  ", depth) .. "Owned: " .. tostring(isOwned))
        debugPrint(string.rep("  ", depth) .. "Craftable: " .. tostring(isCraftable))

        if isOwned and isCraftable then
            markMaterialsAsOwned(currentItemName)
        end

        for reagentId = 1, numReagents do
            local reagentName, _, reagentCount = GetTradeSkillReagentInfo(recipeId, reagentId)
            if reagentName and reagentCount then
                local requiredCount = reagentCount * adjustedQuantity
                local subRecipeId = findRecipeIdByName(reagentName)
                
                if subRecipeId then
                    processItem(subRecipeId, requiredCount, currentItemName, depth + 1)
                    if isOwned then
                        markMaterialsAsOwned(reagentName)
                    end
                else
                    addMaterial(reagentName, requiredCount, currentItemName, isCraftable)
                    if isOwned then
                        debugPrint(string.rep("  ", depth) .. "Marking " .. reagentName .. " as owned through " .. currentItemName)
                        rawMaterials[reagentName].ownedThroughParent = true
                    end
                end
            end
        end
        
        processedItems[currentItemName] = false
    end

    -- Initialize owned items, explicitly excluding the final item
    for i = 1, GetNumTradeSkills() do
        local itemLink = GetTradeSkillItemLink(i)
        if itemLink then
            local name = GetItemInfo(itemLink)
            if name ~= itemName then  -- Never consider the final item as owned
                ownedItems[name] = GetItemCount(itemLink, true) > 0
                if ownedItems[name] then
                    debugPrint("Found owned item: " .. name)
                end
            end
        end
    end

    processItem(tradeSkillRecipeId, 1)
    return rawMaterials, ownedItems
end

-- Function to display the rawMaterials list in the TradeSkillDetailScrollFrame
local function displayrawMaterialsList(itemName, rawMaterials, ownedItems)
    -- Ensure the TradeSkillDetailScrollFrame exists
    local parentFrame = _G["TradeSkillDetailScrollFrame"]
    if not parentFrame then
        --print("Error: TradeSkillDetailScrollFrame not found.")
        return
    end

    -- Find or create the rawMaterials list frame
    local rawMaterialsListFrame = _G["TradeSkillDetailScrollFramerawMaterialsList"] or CreateFrame("Frame", "TradeSkillDetailScrollFramerawMaterialsList", parentFrame)
    rawMaterialsListFrame:SetSize(parentFrame:GetWidth(), 100)
    rawMaterialsListFrame:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 0, 0)

    local content = rawMaterialsListFrame.content or rawMaterialsListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content:SetPoint("BOTTOMLEFT", rawMaterialsListFrame, "BOTTOMLEFT", 5, 5)
    content:SetWidth(rawMaterialsListFrame:GetWidth() - 10)
    content:SetJustifyH("LEFT")

    local rawMaterialsListText = "\n|cffffd100Raw Materials Needed for " .. itemName .. ":|r\n"
    for material, data in pairs(rawMaterials) do
        local playerCount = GetItemCount(material, true) or 0
        local requiredQuantity = data.quantity

        if data.ownedThroughParent then
            playerCount = math.max(playerCount, requiredQuantity)  -- Show the actual count or required if higher
        end

        local colorCode = playerCount >= requiredQuantity and "|cff00ff00" or "|cffffffff"
        local colorCode2 = playerCount >= requiredQuantity and "|cff00ff00" or "|cffffd100"
        rawMaterialsListText = rawMaterialsListText .. colorCode .. material .. ": |r" .. colorCode2 .. playerCount .. "/" .. requiredQuantity .. "|r\n"
    end
    content:SetText(rawMaterialsListText)
    rawMaterialsListFrame.content = content
    rawMaterialsListFrame:Show()
end

-- Function to calculate and display the raw materials list
local function updaterawMaterialsList()
    local selectedIndex = GetTradeSkillSelectionIndex()
    if selectedIndex then
        local itemName = GetTradeSkillInfo(selectedIndex)
        if itemName then
            local rawMaterialsList, ownedItems = calculateRawMaterials(itemName, selectedIndex)
            displayrawMaterialsList(itemName, rawMaterialsList, ownedItems)
        else
            debugPrint("Invalid item name for selected index: " .. tostring(selectedIndex))
        end
    else
        debugPrint("No recipe selected.")
    end
end

-- Create the frame to handle events
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        updaterawMaterialsList()
    end
end)

-- Register the relevant events
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
