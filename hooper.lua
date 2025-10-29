local Http = game:GetService("HttpService")
local TPS = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

-- WEBHOOK URLs from script 1
local WEBHOOK_URL_LOW = "https://discord.com/api/webhooks/1433203505740513401/87dI6dzUJJ8SX8P_INJAmhhuodKYAUWtTSMaRb4S_WUP-kx89bfnBtDNnlL6JroU4h3S"
local WEBHOOK_URL_HIGH = "https://discord.com/api/webhooks/1433203555631890552/OblORXzmJC0DhUSYlzn5mpTOcaDmUsiIyhrE9dVs9jFX87UDocrezJDHqaRyZ8OVVw4i"

while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer
local ALLOWED_PLACE_ID = 109983668079237
local RETRY_DELAY = 0.1
local SETTINGS_FILE = "ServerHopperSettings.json"
local GUI_STATE_FILE = "ServerHopperGUIState.json"
local API_STATE_FILE = "ServerHopperAPIState.json"

-- Track if we've already sent webhook for current server
local currentServerJobId = nil
local webhookSentForCurrentServer = false

local settings = {
    minGeneration = 1000000,
    targetNames = {},
    blacklistNames = {},
    targetRarity = "",
    targetMutation = "",
    minPlayers = 2,
    sortOrder = "Desc",
    autoStart = true,
    customSoundId = "rbxassetid://9167433166",
    hopCount = 0,
    recentVisited = {},
    notificationDuration = 4
}

local guiState = {
    isMinimized = false,
    position = {
        XScale = 0.5,
        XOffset = -125,
        YScale = 0.6,
        YOffset = -150
    }
}

local apiState = {
    mainApiUses = 0,
    cachedServers = {},
    lastCacheUpdate = 0,
    useCachedServers = false
}

local isRunning = false
local currentConnection = nil
local foundPodiumsData = {}
local monitoringConnection = nil
local autoHopping = false

local folderExists = game.Workspace:FindFirstChild("FolderHopperCheck") ~= nil
local alreadyHereFolderExists = game.Workspace:FindFirstChild("Sigmahopper") ~= nil

local mutationColors = {
    Gold = Color3.fromRGB(255, 215, 0),
    Diamond = Color3.fromRGB(0, 255, 255),
    Lava = Color3.fromRGB(255, 100, 0),
    Bloodrot = Color3.fromRGB(255, 0, 0),
    Candy = Color3.fromRGB(255, 182, 193),
    Normal = Color3.fromRGB(255, 255, 255),
    Default = Color3.fromRGB(255, 255, 255)
}

local cachedPlots = nil
local cachedPodiums = nil
local lastPodiumCheck = 0
local PODIUM_CACHE_DURATION = 1

-- Custom notification system
local notificationGui = nil
local currentNotification = nil

-- Extract money value from generation text (from script 1)
local function extractNumber(str)
    if not str then return 0 end
    local numberStr = str:match("%$(.-)/s")
    if not numberStr then return 0 end
    numberStr = numberStr:gsub("%s", "")
    local multiplier = 1
    if numberStr:lower():find("k") then
        multiplier = 1000
        numberStr = numberStr:gsub("[kK]", "")
    elseif numberStr:lower():find("m") then
        multiplier = 1000000
        numberStr = numberStr:gsub("[mM]", "")
    elseif numberStr:lower():find("b") then
        multiplier = 1000000000
        numberStr = numberStr:gsub("[bB]", "")
    end
    return (tonumber(numberStr) or 0) * multiplier
end

-- Get animal data from overhead (from script 1)
local function getAnimalData(overhead)
    if not overhead then return nil end
    
    local displayNameLabel = overhead:FindFirstChild("DisplayName")
    local genLabel = overhead:FindFirstChild("Generation")
    local rarityLabel = overhead:FindFirstChild("Rarity")
    
    if displayNameLabel and genLabel and rarityLabel then
        local genValue = extractNumber(genLabel.Text)
        return {
            DisplayName = displayNameLabel.Text,
            Value = genValue,
            Generation = genLabel.Text,
            Rarity = rarityLabel.Text
        }
    end
    return nil
end

-- Find all animals in the server (from script 1)
local function findAllAnimals()
    local animals = {}
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return animals end

    for _, plot in pairs(plotsFolder:GetDescendants()) do
        if plot.Name == "AnimalOverhead" and plot:IsA("BillboardGui") then
            local stolenLabel = plot:FindFirstChild("Stolen")
            local isStolen = stolenLabel and stolenLabel:IsA("TextLabel") and string.upper(stolenLabel.Text) == "FUSING"
            local displayNameLabel = plot:FindFirstChild("DisplayName")
            
            -- Skip Lucky Block animals
            if displayNameLabel and string.find(string.lower(displayNameLabel.Text), "lucky block") then
                continue
            end
            
            if displayNameLabel and not isStolen then
                local animalData = getAnimalData(plot)
                if animalData then
                    table.insert(animals, animalData)
                end
            end
        end
    end
    return animals
end

-- Send webhook for animals (from script 1) - with anti-spam protection
local function sendAnimalWebhooks()
    -- Check if we're in a new server
    if currentServerJobId ~= game.JobId then
        currentServerJobId = game.JobId
        webhookSentForCurrentServer = false
    end
    
    -- Don't send webhook if we already sent one for this server
    if webhookSentForCurrentServer then
        return false
    end
    
    local animals = findAllAnimals()
    if #animals == 0 then return false end
    
    local placeId = game.PlaceId
    local jobId = game.JobId
    local playersCount = #Players:GetPlayers()
    
    -- Find best animal for main webhook
    local bestAnimal = nil
    local bestValue = 0
    
    for _, animal in pairs(animals) do
        if animal.Value > bestValue then
            bestValue = animal.Value
            bestAnimal = animal
        end
    end
    
    if not bestAnimal then return false end
    
    -- Determine which webhook to use based on value
    local webhookUrl
    local valueCategory
    
    if bestAnimal.Value < 10000000 then -- 0-10M
        webhookUrl = WEBHOOK_URL_LOW
        valueCategory = "LOW"
    else -- 10M+
        webhookUrl = WEBHOOK_URL_HIGH
        valueCategory = "HIGH"
    end
    
    -- Format money value to match the image format (16.5M/s)
    local moneyPerSecFormatted
    if bestAnimal.Value >= 1000000000 then
        moneyPerSecFormatted = string.format("%.1fB/s", bestAnimal.Value / 1000000000)
    elseif bestAnimal.Value >= 1000000 then
        moneyPerSecFormatted = string.format("%.1fM/s", bestAnimal.Value / 1000000)
    elseif bestAnimal.Value >= 1000 then
        moneyPerSecFormatted = string.format("%.1fK/s", bestAnimal.Value / 1000)
    else
        moneyPerSecFormatted = string.format("%d/s", bestAnimal.Value)
    end

    -- Create embed matching the image format exactly
    local embed = {
        title = "# KLPN Hub Notifier API",
        description = "\n\n### Brainrot Notify | KLPN Hub",
        color = valueCategory == "HIGH" and 16711680 or 65280,
        fields = {
            {
                name = "**Name**",
                value = bestAnimal.DisplayName,
                inline = false
            },
            {
                name = "**Money per sec**",
                value = moneyPerSecFormatted,
                inline = false
            },
            {
                name = "**Players**",
                value = string.format("%d/%d", playersCount, Players.MaxPlayers),
                inline = false
            },
            {
                name = "**Job ID (Mobile)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Job ID (PC)**",
                value = "```" .. jobId .. "```",
                inline = false
            },
            {
                name = "**Join Link**",
                value = "[Click to Join](https://www.roblox.com/games/" .. placeId .. "?jobId=" .. jobId .. ")",
                inline = false
            },
            {
                name = "**Join Script (PC)**",
                value = "```game:GetService(\"TeleportService\"):TeleportToPlaceInstance(" .. placeId .. ",\"" .. jobId .. "\", game.Players.LocalPlayer)```",
                inline = false
            }
        },
        timestamp = DateTime.now():ToIsoDate(),
        footer = {
            text = "Made by KLPN Hub • " .. os.date("%m/%d/%Y %I:%M %p") .. " • Dzi6 o " .. os.date("%H:%M")
        }
    }
    
    local payload = {
        embeds = {embed},
        username = "KLPN Hub Notifier",
        avatar_url = "https://cdn.discordapp.com/attachments/1128833213672656988/1215321493282160730/standard_1.gif"
    }
    
    -- Send webhook with error handling
    local success, result = pcall(function()
        local jsonPayload = Http:JSONEncode(payload)
        
        if syn and syn.request then
            return syn.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        elseif request then
            return request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        else
            return game:HttpGetAsync(webhookUrl, jsonPayload)
        end
    end)
    
    if success then
        webhookSentForCurrentServer = true  -- Mark as sent for this server
        showNotification("Webhook sent: " .. bestAnimal.DisplayName .. " (" .. moneyPerSecFormatted .. ")")
    else
        showNotification("Webhook failed: " .. tostring(result))
    end
    
    return success
end

-- Rest of your original script 2 functions remain exactly the same...
local function createNotificationSystem()
    if notificationGui and notificationGui.Parent then
        notificationGui:Destroy()
    end
    
    local playerGui = player:WaitForChild("PlayerGui")
    notificationGui = Instance.new("ScreenGui")
    notificationGui.Name = "ServerHopperNotifications"
    notificationGui.ResetOnSpawn = false
    notificationGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    notificationGui.Parent = playerGui
    
    return notificationGui
end

local function showNotification(title, text, duration)
    duration = duration or settings.notificationDuration or 4
    
    -- Create notification GUI if it doesn't exist
    if not notificationGui or not notificationGui.Parent then
        createNotificationSystem()
    end
    
    -- Remove existing notification
    if currentNotification then
        currentNotification:Destroy()
        currentNotification = nil
    end
    
    -- Create notification frame
    local notificationFrame = Instance.new("Frame")
    notificationFrame.Size = UDim2.new(0, 300, 0, 80)
    notificationFrame.Position = UDim2.new(0.5, -150, 0.1, 0)
    notificationFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    notificationFrame.BorderSizePixel = 0
    notificationFrame.ZIndex = 100
    notificationFrame.Parent = notificationGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = notificationFrame
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(100, 150, 255)
    stroke.Parent = notificationFrame
    
    local shadow = Instance.new("ImageLabel")
    shadow.Size = UDim2.new(1, 10, 1, 10)
    shadow.Position = UDim2.new(0, -5, 0, -5)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10, 10, 118, 118)
    shadow.ZIndex = 99
    shadow.Parent = notificationFrame
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 20)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title or "Notification"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 101
    titleLabel.Parent = notificationFrame
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -20, 1, -40)
    textLabel.Position = UDim2.new(0, 10, 0, 35)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text or ""
    textLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    textLabel.TextSize = 12
    textLabel.Font = Enum.Font.Gotham
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.TextYAlignment = Enum.TextYAlignment.Top
    textLabel.TextWrapped = true
    textLabel.ZIndex = 101
    textLabel.Parent = notificationFrame
    
    -- Animation
    notificationFrame.BackgroundTransparency = 1
    titleLabel.TextTransparency = 1
    textLabel.TextTransparency = 1
    stroke.Transparency = 1
    
    -- Fade in
    TweenService:Create(notificationFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    TweenService:Create(titleLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
    TweenService:Create(textLabel, TweenInfo.new(0.3), {TextTransparency = 0}):Play()
    TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 0}):Play()
    
    currentNotification = notificationFrame
    
    -- Auto remove after duration
    task.spawn(function()
        task.wait(duration)
        
        if notificationFrame and notificationFrame.Parent then
            -- Fade out
            TweenService:Create(notificationFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
            TweenService:Create(titleLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
            TweenService:Create(textLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
            TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
            
            task.wait(0.3)
            if notificationFrame and notificationFrame.Parent then
                notificationFrame:Destroy()
                if currentNotification == notificationFrame then
                    currentNotification = nil
                end
            end
        end
    end)
    
    return notificationFrame
end

local function checkAPIAvailability()
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local success, response = pcall(function() return game:HttpGet(mainAPI) end)
    return success and response ~= ""
end

local function saveSettings()
    local success, error = pcall(function()
        writefile(SETTINGS_FILE, Http:JSONEncode(settings))
    end)
    if not success then
        print("Failed to save settings:", error)
    end
end

local function loadSettings()
    local success, data = pcall(function()
        return readfile(SETTINGS_FILE)
    end)
    if success then
        local loadedSettings = Http:JSONDecode(data)
        for key, value in pairs(loadedSettings) do
            if settings[key] ~= nil then
                settings[key] = value
            end
        end
    end
end

local function saveGUIState()
    local success, error = pcall(function()
        writefile(GUI_STATE_FILE, Http:JSONEncode(guiState))
    end)
    if not success then
        print("Failed to save GUI state:", error)
    end
end

local function loadGUIState()
    local success, data = pcall(function()
        return readfile(GUI_STATE_FILE)
    end)
    if success then
        local loadedState = Http:JSONDecode(data)
        for key, value in pairs(loadedState) do
            if guiState[key] ~= nil then
                guiState[key] = value
            end
        end
    end
end

local function saveAPIState()
    local success, error = pcall(function()
        writefile(API_STATE_FILE, Http:JSONEncode(apiState))
    end)
    if not success then
        print("Failed to save API state:", error)
    end
end

local function loadAPIState()
    local success, data = pcall(function()
        return readfile(API_STATE_FILE)
    end)
    if success then
        local loadedState = Http:JSONDecode(data)
        for key, value in pairs(loadedState) do
            if apiState[key] ~= nil then
                apiState[key] = value
            end
        end
    end
end

local function playFoundSound()
    local sound = Instance.new("Sound")
    sound.SoundId = settings.customSoundId
    sound.Volume = 1
    sound.PlayOnRemove = true
    sound.Parent = workspace
    sound:Destroy()
end

local function getMutationTextAndColor(mutation)
    if not mutation or mutation.Visible == false then
        return "Normal", Color3.fromRGB(255, 255, 255), false
    end
    local name = mutation.Text
    if name == "" then
        return "Normal", Color3.fromRGB(255, 255, 255), false
    end
    if name == "Rainbow" then
        return "Rainbow", Color3.new(1, 1, 1), true
    end
    local color = mutationColors[name] or Color3.fromRGB(255, 255, 255)
    return name, color, false
end

local function isPlayerBase(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase.Enabled then
            return true
        end
    end
    return false
end

local function getAllPodiums()
    if cachedPodiums and tick() - lastPodiumCheck < PODIUM_CACHE_DURATION then
        return cachedPodiums
    end
    
    local podiums = {}
    
    if not cachedPlots then
        cachedPlots = Workspace:FindFirstChild("Plots")
    end
    
    if not cachedPlots then 
        lastPodiumCheck = tick()
        cachedPodiums = podiums
        return podiums 
    end
    
    local plotChildren = cachedPlots:GetChildren()
    
    for i = 1, #plotChildren do
        local plot = plotChildren[i]
        
        if not isPlayerBase(plot) then
            -- Original search method
            local animalPods = plot:FindFirstChild("AnimalPodiums")
            if animalPods then
                local podChildren = animalPods:GetChildren()
                for j = 1, #podChildren do
                    local pod = podChildren[j]
                    local base = pod:FindFirstChild("Base")
                    if base then
                        local spawn = base:FindFirstChild("Spawn")
                        if spawn then
                            local attach = spawn:FindFirstChild("Attachment")
                            if attach then
                                local animalOverhead = attach:FindFirstChild("AnimalOverhead")
                                if animalOverhead and (base:IsA("BasePart") or base:IsA("Model")) then
                                    table.insert(podiums, { 
                                        overhead = animalOverhead, 
                                        base = base,
                                        pod = pod,
                                        plot = plot
                                    })
                                end
                            end
                        end
                    end
                end
            end
            
            -- Alternative search method
            if plot:IsA("Model") then
                for _, model in pairs(plot:GetChildren()) do
                    if model:IsA("Model") then
                        for _, obj in pairs(model:GetDescendants()) do
                            if obj:IsA("Attachment") and obj.Name == "OVERHEAD_ATTACHMENT" then
                                local overhead = obj:FindFirstChild("AnimalOverhead")
                                if overhead then
                                    -- Find a suitable base, perhaps the parent model or something
                                    local base = model:FindFirstChild("Base") or model
                                    if base and (base:IsA("BasePart") or base:IsA("Model")) then
                                        table.insert(podiums, { 
                                            overhead = overhead, 
                                            base = base,
                                            pod = model,
                                            plot = plot
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    lastPodiumCheck = tick()
    cachedPodiums = podiums
    return podiums
end

local function getPrimaryPartPosition(obj)
    if not obj then return nil end
    if obj:IsA("Model") and obj.PrimaryPart then
        return obj.PrimaryPart.Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
    return nil
end

local function getServersFromAPI(baseUrl, isMainAPI)
    local servers = {}
    local cursor = ""
    local maxPages = 3
    
    if isMainAPI then
        apiState.mainApiUses = apiState.mainApiUses + 1
        saveAPIState()
    end
    
    for page = 1, maxPages do
        local url = baseUrl
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        
        local success, response = pcall(function() return game:HttpGet(url) end)
        if not success then break end
        
        local body = Http:JSONDecode(response)
        if not body.data then break end
        
        for _, v in body.data do
            if v.playing and v.maxPlayers and v.playing >= settings.minPlayers and v.playing < v.maxPlayers and v.id ~= game.JobId and not table.find(settings.recentVisited, v.id) then
                table.insert(servers, v.id)
                if not table.find(apiState.cachedServers, v.id) then
                    table.insert(apiState.cachedServers, v.id)
                end
            end
        end
        
        cursor = body.nextPageCursor or ""
        if cursor == "" then break end
    end
    
    while #apiState.cachedServers > 300 do
        table.remove(apiState.cachedServers, 1)
    end
    
    apiState.lastCacheUpdate = tick()
    saveAPIState()
    return servers
end

local function getCachedServers()
    local availableServers = {}
    local recentCount = math.min(#settings.recentVisited, 5)
    local recentServers = {}
    
    for i = #settings.recentVisited - recentCount + 1, #settings.recentVisited do
        if settings.recentVisited[i] then
            table.insert(recentServers, settings.recentVisited[i])
        end
    end
    
    for _, serverId in ipairs(apiState.cachedServers) do
        if not table.find(recentServers, serverId) and serverId ~= game.JobId then
            table.insert(availableServers, serverId)
        end
    end
    
    return availableServers
end

local function findClosestModel(podiumBase, models)
    if not podiumBase then return nil end
    local podiumPos = getPrimaryPartPosition(podiumBase)
    if not podiumPos then return nil end
    
    local closestModel = nil
    local minDistance = math.huge
    
    for i = 1, #models do
        local model = models[i]
        local modelPos = getPrimaryPartPosition(model)
        if modelPos then
            local distance = (podiumPos - modelPos).Magnitude
            if distance < minDistance then
                minDistance = distance
                closestModel = model
            end
        end
    end
    
    return closestModel
end

local function isStolenPodium(overhead)
    if not overhead then return false end
    local stolenLabel = overhead:FindFirstChild("Stolen")
    if stolenLabel and stolenLabel:IsA("TextLabel") then
        return string.upper(stolenLabel.Text) == "FUSING"
    end
    return false
end

local function getAvailableServers()
    if apiState.mainApiUses >= 3 or apiState.useCachedServers then
        if not checkAPIAvailability() then
            apiState.useCachedServers = true
            saveAPIState()
            return getCachedServers()
        else
            apiState.useCachedServers = false
            apiState.mainApiUses = 0
            saveAPIState()
        end
    end
    
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local servers = getServersFromAPI(mainAPI, true)
    
    if #servers > 0 then return servers end
    
    apiState.useCachedServers = true
    saveAPIState()
    return getCachedServers()
end

local function matchesFilters(labels, overhead)
    if isStolenPodium(overhead) then
        return false
    end
    
    local genValue = extractNumber(labels.Generation)
    local hasTargetName = false
    
    if #settings.targetNames > 0 then
        for i = 1, #settings.targetNames do
            local name = settings.targetNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                hasTargetName = true
                break
            end
        end
        if not hasTargetName then return false end
    end
    
    if settings.targetMutation ~= "" then
        if string.lower(labels.Mutation) ~= string.lower(settings.targetMutation) then
            return false
        end
        return true
    end
    
    if hasTargetName then
        return true
    end
    
    if genValue < settings.minGeneration then
        return false
    end
    
    if #settings.blacklistNames > 0 then
        for i = 1, #settings.blacklistNames do
            local name = settings.blacklistNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                return false
            end
        end
    end
    
    if settings.targetRarity ~= "" then
        if string.lower(labels.Rarity) ~= string.lower(settings.targetRarity) then
            return false
        end
    end
    
    return true
end

local function checkPodiumsForWebhooksAndFilters()
    if game.PlaceId ~= ALLOWED_PLACE_ID then
        return false, {}
    end
    
    local podiums = getAllPodiums()
    local filteredPodiums = {}
    
    local workspaceModels = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") then
            table.insert(workspaceModels, child)
        end
    end
    
    for i = 1, #podiums do
        local podium = podiums[i]
        
        if isStolenPodium(podium.overhead) then
            continue
        end
        
        local displayNameLabel = podium.overhead:FindFirstChild("DisplayName")
        local genLabel = podium.overhead:FindFirstChild("Generation")
        local rarityLabel = podium.overhead:FindFirstChild("Rarity")
        
        if displayNameLabel and genLabel and rarityLabel then
            local mutation = podium.overhead:FindFirstChild("Mutation")
            local mutText, _, _ = getMutationTextAndColor(mutation)
            
            local modelText = string.format("%s Generation: %s Mutation: %s Rarity: %s", 
                displayNameLabel.Text, 
                genLabel.Text, 
                mutText, 
                rarityLabel.Text)
            
            local genValue = extractNumber(genLabel.Text)
            local displayName = displayNameLabel.Text
            
            local labels = {
                DisplayName = displayNameLabel.Text,
                Generation = genLabel.Text,
                Mutation = mutText,
                Rarity = rarityLabel.Text
            }
            
            if matchesFilters(labels, podium.overhead) then
                local closestModel = findClosestModel(podium.base, workspaceModels)
                table.insert(filteredPodiums, { 
                    base = podium.base, 
                    labels = labels, 
                    closestModel = closestModel, 
                    overhead = podium.overhead,
                    pod = podium.pod,
                    plot = podium.plot
                })
            end
        end
    end
    
    return #filteredPodiums > 0, filteredPodiums
end

local function formatGeneration(genStr)
    local genValue = extractNumber(genStr)
    if genValue >= 1000000000 then
        return string.format("%.1fB", genValue / 1000000000)
    elseif genValue >= 1000000 then
        return string.format("%.1fM", genValue / 1000000)
    elseif genValue >= 1000 then
        return string.format("%.1fK", genValue / 1000)
    else
        return tostring(genValue)
    end
end

local function tryTeleportWithRetries()
    if not isRunning then
        return
    end

    local attempts = 0
    local maxAttempts = 5
    while attempts < maxAttempts and isRunning do
        local servers = getAvailableServers()
        if #servers == 0 then
            task.wait(RETRY_DELAY)
            attempts = attempts + 1
            continue
        end
        local randomServer = servers[math.random(1, #servers)]
        local success, err = pcall(function()
            TPS:TeleportToPlaceInstance(ALLOWED_PLACE_ID, randomServer)
        end)
        if success then
            return
        else
            if not isRunning then
                return
            end
            task.wait(RETRY_DELAY)
            attempts = attempts + 1
        end
    end
    if isRunning then
        isRunning = false
    end
end

local function monitorFoundPodiums()
    if monitoringConnection then
        monitoringConnection:Disconnect()
    end
    
    monitoringConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or #foundPodiumsData == 0 then return end
        
        local lostAny = false
        local lostPodiums = {}
        
        for i = #foundPodiumsData, 1, -1 do
            local data = foundPodiumsData[i]
            if data and data.overhead and data.overhead.Parent then
                local displayNameLabel = data.overhead:FindFirstChild("DisplayName")
                if displayNameLabel and displayNameLabel.Text then
                    local currentLabels = {
                        DisplayName = displayNameLabel.Text,
                        Generation = data.labels and data.labels.Generation or "Unknown",
                        Mutation = data.labels and data.labels.Mutation or "Normal",
                        Rarity = data.labels and data.labels.Rarity or "None"
                    }
                    
                    if not matchesFilters(currentLabels, data.overhead) then
                        table.insert(lostPodiums, data.labels.DisplayName)
                        table.remove(foundPodiumsData, i)
                        lostAny = true
                    end
                else
                    table.insert(lostPodiums, data.labels.DisplayName)
                    table.remove(foundPodiumsData, i)
                    lostAny = true
                end
            else
                if data then
                    table.insert(lostPodiums, data.labels.DisplayName)
                    table.remove(foundPodiumsData, i)
                    lostAny = true
                end
            end
        end
        
        if lostAny then
            local lostText = ""
            if #lostPodiums > 0 then
                lostText = "Lost: " .. table.concat(lostPodiums, ", ")
            else
                lostText = "Lost podium(s)"
            end
            
            showNotification("Not found", lostText)
        end
    end)
end

-- MODIFIED: Added webhook sending when animals are found
local function runServerCheck()
    if not isRunning then return end
    
    local foundPets, results = checkPodiumsForWebhooksAndFilters()
    
    if foundPets and #results > 0 then
        foundPodiumsData = results
        local displayResults = {}
        for _, entry in ipairs(results) do
            local genValue = extractNumber(entry.labels.Generation)
            table.insert(displayResults, {entry = entry, gen = genValue})
        end
        table.sort(displayResults, function(a, b) return a.gen > b.gen end)
        local foundText = ""
        local numToShow = math.min(3, #displayResults)
        for i = 1, numToShow do
            local entry = displayResults[i].entry
            local genFormatted = formatGeneration(entry.labels.Generation)
            foundText = foundText .. entry.labels.DisplayName .. " (" .. genFormatted .. ")"
            if i < numToShow then
                foundText = foundText .. ", "
            end
        end
        if #displayResults > 3 then
            local extra = #displayResults - 3
            foundText = foundText .. " and " .. extra .. " more..."
        end
        showNotification("Found", foundText)
        playFoundSound()
        
        -- Send webhook when animals are found
        sendAnimalWebhooks()
        
        monitorFoundPodiums()
        return
    end
    
    if not isRunning then return end
    
    settings.hopCount = settings.hopCount + 1
    saveSettings()
    tryTeleportWithRetries()
end

-- ... rest of your GUI functions remain exactly the same ...

loadSettings()
loadGUIState()
loadAPIState()

if game.PlaceId == ALLOWED_PLACE_ID then
    createSettingsGUI()
else
    -- If not in the target game, you might want to show a different message
    showNotification("Server Hopper", "Not in target game. Waiting...", 5)
end
