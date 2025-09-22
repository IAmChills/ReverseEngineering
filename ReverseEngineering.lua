local function debugPrint(...)
    if debug then
        print(...)
    end
end

-- Function to locate index of all parent items
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

-- Function to recursively build a raw materials list using WoW API
local function calculateRawMaterials(itemName, tradeSkillRecipeId)
    local rawMaterials = {}
    local ownedItems = {}
    local processedItems = {}
    local debug = false

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
    return rawMaterials, ownedItems, tradeSkillRecipeId
end

-- Needs testing
local function adjustScrollFrame(baseHeight, scrollChild, content)
    -- Calculate total content height
    local contentHeight = content:GetStringHeight()
    local numReagents = GetTradeSkillNumReagents(GetTradeSkillSelectionIndex())
    local reagentHeight = 95 + (math.ceil(numReagents / 2) - 1) * 45
    
    -- Set scroll child height to accommodate all content
    local totalHeight = reagentHeight + contentHeight + 20 -- 20px padding
    scrollChild:SetHeight(totalHeight)
end

-- Function to display the rawMaterials list in the TradeSkillDetailScrollFrame
local function displayRawMaterialsList(itemName, rawMaterials, ownedItems)
    local parentFrame = _G["TradeSkillDetailScrollFrame"]
    if not parentFrame then return end

    local scrollChild = parentFrame:GetScrollChild()
    if not scrollChild then return end

    local rawMaterialsListFrame = _G["TradeSkillDetailScrollFramerawMaterialsList"]
    if not rawMaterialsListFrame then
        rawMaterialsListFrame = CreateFrame("Frame", "TradeSkillDetailScrollFramerawMaterialsList", scrollChild)
    end

    -- Clear any existing font strings
    if rawMaterialsListFrame.fontStrings then
        for _, fs in ipairs(rawMaterialsListFrame.fontStrings) do
            fs:Hide()
            fs:SetParent(nil)
        end
    end
    rawMaterialsListFrame.fontStrings = {}

    -- Get last reagent frame for positioning
    local numReagents = GetTradeSkillNumReagents(GetTradeSkillSelectionIndex())

    -- Get left column position
    local leftPositionFrame
    if numReagents > 0 then
        if numReagents % 2 == 0 then
            -- Even number of reagents, get second to last reagent (bottom left)
            leftPositionFrame = _G["TradeSkillReagent" .. (numReagents - 1)]
        else
            -- Odd number, get last reagent (already in left column)
            leftPositionFrame = _G["TradeSkillReagent" .. numReagents]
        end
    else
        leftPositionFrame = TradeSkillReagentLabel or TradeSkillDescription
    end

    rawMaterialsListFrame:SetPoint("TOPLEFT", leftPositionFrame, "BOTTOMLEFT", -5, -10)
    rawMaterialsListFrame:SetWidth(parentFrame:GetWidth())

    -- Create header
    local header = rawMaterialsListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", rawMaterialsListFrame, "TOPLEFT", 5, -5)
    header:SetWidth(rawMaterialsListFrame:GetWidth() - 10)
    header:SetJustifyH("LEFT")
    header:SetText("\n|cffffd100Raw Materials Needed for " .. itemName .. ":|r\n")
    table.insert(rawMaterialsListFrame.fontStrings, header)

    local yOffset = -header:GetStringHeight() - 10
    local lineHeight = 14 -- Approximate height per line, adjust as needed
    local index = 1

    -- Iterate through raw materials
    for material, data in pairs(rawMaterials) do
        local directCount = GetItemCount(material, true) or 0
        local parentMaterials = {}
        local totalCount = directCount

        -- Find the item link for the material
        local itemLink
        for i = 1, GetNumTradeSkills() do
            local skillName = GetTradeSkillInfo(i)
            if skillName == material then
                itemLink = GetTradeSkillItemLink(i)
                break
            else
                local numReagents = GetTradeSkillNumReagents(i)
                for j = 1, numReagents do
                    local reagentName = GetTradeSkillReagentInfo(i, j)
                    if reagentName == material then
                        local reagentLink = GetTradeSkillReagentItemLink(i, j)
                        if reagentLink then
                            itemLink = reagentLink
                            break
                        end
                    end
                end
            end
            if itemLink then break end
        end

        -- Calculate total count from parent items
        if data.parents then
            local processedParents = {}
            for _, parentItem in ipairs(data.parents) do
                if ownedItems[parentItem] and data.craftedParents[parentItem] and not processedParents[parentItem] then
                    processedParents[parentItem] = true
                    local parentCount = GetItemCount(parentItem, true) or 0
                    if parentCount > 0 then
                        local matPerParent = 0
                        local parentRecipeId = findRecipeIdByName(parentItem)
                        if parentRecipeId then
                            for i = 1, GetTradeSkillNumReagents(parentRecipeId) do
                                local reagentName, _, reagentCount = GetTradeSkillReagentInfo(parentRecipeId, i)
                                if reagentName == material then
                                    matPerParent = reagentCount
                                    break
                                end
                            end
                        end
                        totalCount = totalCount + (parentCount * matPerParent)
                        table.insert(parentMaterials, parentCount .. " " .. parentItem)
                    end
                end
            end
        end

        local colorCode = totalCount >= data.quantity and "|cff00ff00" or "|cffffffff"
        local colorCode2 = totalCount >= data.quantity and "|cff00ff00" or "|cffffd100"

        -- Use the item link if available, otherwise fall back to material name
        local materialText = itemLink or material
        local lineText = colorCode .. materialText .. ": |r" .. colorCode2 .. totalCount .. "/" .. data.quantity .. "|r"
        if #parentMaterials > 0 then
            if directCount == 0 then
                lineText = lineText .. " |cff4974ba[" .. table.concat(parentMaterials, " + ") .. "]|r"
            else
                lineText = lineText .. " |cff4974ba[" .. directCount .. " + " .. table.concat(parentMaterials, " + ") .. "]|r"
            end
        end

        -- Create a new font string for each material
        local line = rawMaterialsListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line:SetPoint("TOPLEFT", rawMaterialsListFrame, "TOPLEFT", 5, yOffset)
        line:SetWidth(rawMaterialsListFrame:GetWidth() - 10)
        line:SetJustifyH("LEFT")
        line:SetText(lineText)
        table.insert(rawMaterialsListFrame.fontStrings, line)

        -- Store the item link in the font string for use in scripts
        line.itemLink = itemLink

        -- Add tooltip functionality
        line:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        line:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        -- Add click functionality for shift-clicking
        line:EnableMouse(true)
        line:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and IsShiftKeyDown() and self.itemLink then
                if ChatEdit_InsertLink(self.itemLink) then
                    return
                end
            end
        end)

        -- Calculate actual height of the font string (accounts for wrapping)
        local lineHeight = line:GetStringHeight() + 2 -- Add small padding between lines
        yOffset = yOffset - lineHeight
        index = index + 1
    end

    -- Adjust frame height (include header height)
    local headerHeight = header:GetStringHeight() + 10 -- Include padding after header
    rawMaterialsListFrame:SetHeight(headerHeight - yOffset) -- yOffset is negative, so subtract to get positive height

    -- Adjust scroll frame
    local contentHeight = headerHeight - yOffset
    local numReagents = GetTradeSkillNumReagents(GetTradeSkillSelectionIndex())
    local reagentHeight = 95 + (math.ceil(numReagents / 2) - 1) * 45
    local totalHeight = reagentHeight + contentHeight + 20 -- 20px padding
    scrollChild:SetHeight(totalHeight)

    rawMaterialsListFrame:Show()
end

-- Function to calculate and display the raw materials list
local function updateRawMaterialsList()
    local selectedIndex = GetTradeSkillSelectionIndex()
    if selectedIndex then
        local itemName = GetTradeSkillInfo(selectedIndex)
        if itemName then
            local rawMaterialsList, ownedItems = calculateRawMaterials(itemName, selectedIndex)
            displayRawMaterialsList(itemName, rawMaterialsList, ownedItems)
        else
            debugPrint("Invalid item name for selected index: " .. tostring(selectedIndex))
        end
    else
        debugPrint("No recipe selected.")
    end
end

local lastTradeSkillSelectionIndex = nil
local function monitorTradeSkillSelectionIndex()
    local currentSelectionIndex = GetTradeSkillSelectionIndex()
    if currentSelectionIndex ~= lastTradeSkillSelectionIndex then
        lastTradeSkillSelectionIndex = currentSelectionIndex
        updateRawMaterialsList()
    end
end

-- Create a frame to handle OnUpdate
local monitorFrame = CreateFrame("Frame")
monitorFrame:SetScript("OnUpdate", function(self, elapsed)
    monitorTradeSkillSelectionIndex()
end)

-- Enable/disable monitoring when the trade skill window is shown/hidden
local function onTradeSkillShow()
    updateRawMaterialsList()
    monitorFrame:Show()
end

local function onTradeSkillHide()
    monitorFrame:Hide()
end

-- Event handling for trade skill window visibility
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        onTradeSkillShow()
    elseif event == "TRADE_SKILL_CLOSE" then
        onTradeSkillHide()
    end
end)

-- Start with the monitor frame hidden
monitorFrame:Hide()
